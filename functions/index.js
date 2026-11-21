// Forge Cloud Functions.
//
// deleteAccount: removes everything an account owns, then the Auth
// user itself. Callable only by the signed-in owner of the account.
// Idempotent and Auth-last, so a failed run can be retried: the
// user stays signed in until it succeeds.
//
// What it removes:
//   - users/{uid} and every subcollection under it (profile, programs,
//     coachPrograms, workouts, records, bodyweight, submissions) —
//     recursiveDelete
//   - top-level submissions where userId == uid (the public mirror)
//   - coachLinks where the user is client or coach
//   - pairingCodes where the user is the client
//   - every Storage file under users/{uid}/ (set videos)
//   - the Firebase Auth user
//
// redeemPairingCode: the only way a coach links to a client. Verifies
// the pairing code exists, is unexpired, and is not the caller's own,
// then creates the coachLinks doc and deletes the code in one
// transaction, so a code is single-use by construction. Client-side
// create on coachLinks is denied in firestore.rules — a code is the
// credential, and only this function may spend it.
//
// Deploys with: firebase deploy --only functions --project your-firebase-project-id
// (from the project root, after cd functions && npm install).

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();
const auth = admin.auth();

/** Deletes every doc in the query, in batches of 500. */
async function deleteQuery(query) {
  const snap = await query.get();
  if (snap.empty) return;
  const writer = db.bulkWriter();
  snap.docs.forEach((doc) => writer.delete(doc.ref));
  await writer.close();
}

exports.deleteAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to delete your account.");
  }

  // 1. Everything under users/{uid} — profile, programs,
  // coachPrograms, workouts, records, bodyweight, submissions.
  await db.recursiveDelete(db.doc(`users/${uid}`));

  // 2. Top-level docs that name the user.
  await deleteQuery(db.collection("submissions").where("userId", "==", uid));
  await deleteQuery(
    db.collection("coachLinks").where("clientUid", "==", uid),
  );
  await deleteQuery(
    db.collection("coachLinks").where("coachUid", "==", uid),
  );
  await deleteQuery(
    db.collection("pairingCodes").where("clientUid", "==", uid),
  );

  // 3. Every Storage file under users/{uid}/ (set videos).
  await admin.storage().bucket().deleteFiles({prefix: `users/${uid}/`});

  // 4. The Auth user, last — if anything above throws, the account
  // is still there and the user can retry.
  await auth.deleteUser(uid);

  return {deleted: true};
});

/**
 * Redeems a pairing code and links the calling coach to the client
 * who created it. The code is verified server-side (it exists, is
 * unexpired, and is not the caller's own) and spent atomically: the
 * coachLinks doc is created and the code deleted in one transaction,
 * so a code can never be redeemed twice — even if two coaches scan
 * it at the same moment, only one transaction wins and the other
 * sees the code as gone.
 *
 * Errors (surfaced to the coach as-is by the app):
 *   unauthenticated — not signed in
 *   invalid-argument — malformed code, or the caller's own code
 *   not-found — no live code with that value
 *   failed-precondition — the code has expired
 */
exports.redeemPairingCode = onCall(async (request) => {
  const coachUid = request.auth?.uid;
  if (!coachUid) {
    throw new HttpsError("unauthenticated", "Sign in to link a client.");
  }
  const rawCode = request.data?.code;
  const code =
    typeof rawCode === "string"
      ? rawCode.toUpperCase().replace(/[^A-Z0-9]/g, "")
      : "";
  if (code.length !== 6) {
    throw new HttpsError(
      "invalid-argument",
      "That code does not look right. Check it and try again.",
    );
  }

  const codeRef = db.collection("pairingCodes").doc(code);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(codeRef);
    if (!snap.exists) {
      throw new HttpsError(
        "not-found",
        "No client found for that code. Ask them to show a fresh one.",
      );
    }
    const data = snap.data();
    const clientUid = data.clientUid;
    if (typeof clientUid !== "string" || clientUid.length === 0) {
      throw new HttpsError(
        "not-found",
        "No client found for that code. Ask them to show a fresh one.",
      );
    }
    if (clientUid === coachUid) {
      throw new HttpsError(
        "invalid-argument",
        "That is your own code — you cannot coach yourself.",
      );
    }
    const expiresRaw = data.expiresAt;
    const expiresMillis =
      expiresRaw?.toMillis?.() ??
      (expiresRaw instanceof Date
        ? expiresRaw.getTime()
        : Date.parse(expiresRaw));
    if (!expiresMillis || expiresMillis <= Date.now()) {
      throw new HttpsError(
        "failed-precondition",
        "That code has expired. Ask the client for a new one.",
      );
    }

    const linkId = `${coachUid}_${clientUid}`;
    const now = admin.firestore.Timestamp.now();
    tx.set(db.collection("coachLinks").doc(linkId), {
      id: linkId,
      coachUid,
      clientUid,
      createdAt: now,
      lastViewedAt: null,
      status: "active",
    });
    tx.delete(codeRef);
    return {
      id: linkId,
      coachUid,
      clientUid,
      createdAtMillis: now.toMillis(),
    };
  });
});
