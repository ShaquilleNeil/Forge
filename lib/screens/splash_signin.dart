import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';

/// Sign-in screen: app icon, FORGE wordmark, Google + email sign-in.
/// After a successful sign-in AuthGate routes on its own — to profile
/// setup when the user has no profile yet, otherwise to the app.
class SplashSignInScreen extends StatefulWidget {
  const SplashSignInScreen({super.key});

  @override
  State<SplashSignInScreen> createState() => _SplashSignInScreenState();
}

class _SplashSignInScreenState extends State<SplashSignInScreen> {
  final _auth = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;
  String? _error;

  /// The email fields hide behind their own button; Google is the
  /// primary path and the only filled button on the screen.
  bool _showEmailForm = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _auth.signInWithGoogle();
      // AuthGate routes from here: setup for a fresh user, app shell
      // for everyone else.
    } catch (e, st) {
      // TEMPORARY debug: print the real error + stack trace to the
      // flutter run log so we can see why sign-in fails.
      debugPrint('GOOGLE SIGN-IN ERROR: $e');
      debugPrint('$st');
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithEmail({required bool createAccount}) async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!email.contains('@') || email.isEmpty) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    if (password.length < 6) {
      setState(
        () => _error = 'Password must be at least 6 characters.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (createAccount) {
        await _auth.signUpWithEmail(email, password);
      } else {
        await _auth.signInWithEmail(email, password);
      }
      // AuthGate routes from here: setup for a fresh user, app shell
      // for everyone else.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _friendlyError(e);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyError(Object e) {
    final message = e.toString();
    if (message.contains('canceled') || message.contains('cancelled')) {
      return 'Sign-in was cancelled. Try again when you are ready.';
    }
    if (message.contains('user-not-found') ||
        message.contains('wrong-password') ||
        message.contains('invalid-credential')) {
      return 'Wrong email or password. Check them and try again.';
    }
    if (message.contains('email-already-in-use')) {
      return 'An account already exists for this email. Sign in instead.';
    }
    if (message.contains('network')) {
      return 'No connection. Check your internet and try again.';
    }
    return 'Sign-in failed. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ForgeTheme.scaffoldBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 128,
                    height: 128,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'FORGE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 10,
                  color: ForgeTheme.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Train private. Submit when ready.',
                textAlign: TextAlign.center,
                style: ForgeTheme.bodyMuted.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: _busy ? null : _signInWithGoogle,
                style: FilledButton.styleFrom(
                  backgroundColor: ForgeTheme.text,
                  foregroundColor: ForgeTheme.scaffoldBg,
                  minimumSize: const Size(0, 56),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Official multicolor Google "G" asset, per Google
                    // sign-in branding — no recolored or letterform "G".
                    Image.asset(
                      'assets/google_g_logo.png',
                      width: 24,
                      height: 24,
                    ),
                    const SizedBox(width: 12),
                    const Text('Continue with Google'),
                  ],
                ),
              ),
              if (_busy) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: ForgeTheme.errorText,
                ),
              ],
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => setState(
                          () => _showEmailForm = !_showEmailForm,
                        ),
                child: const Text('Sign in with email'),
              ),
              if (_showEmailForm) ...[
                const SizedBox(height: 24),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _signInWithEmail(createAccount: false),
                  child: const Text('Sign in'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _signInWithEmail(createAccount: true),
                  child: const Text('Create account'),
                ),
              ],
              const SizedBox(height: 32),
              const Text(
                'Private by default — nothing leaves your account unless you submit it.',
                textAlign: TextAlign.center,
                style: ForgeTheme.bodyMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
