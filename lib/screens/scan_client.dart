import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/auth_service.dart';
import '../services/coach_service.dart';
import '../services/firestore_service.dart';
import '../theme.dart';
import '../widgets/side_pill.dart';

/// Coach side: scan a client's QR (or type the code in) to link them.
/// The code is single-use and 24-hour lived; the link it creates is what
/// gives the coach access — not the scan itself.
class ScanClientScreen extends StatefulWidget {
  const ScanClientScreen({super.key});

  @override
  State<ScanClientScreen> createState() => _ScanClientScreenState();
}

class _ScanClientScreenState extends State<ScanClientScreen> {
  final _coach = CoachService();
  final _auth = AuthService();
  final _codeController = TextEditingController();
  final _scannerController = MobileScannerController();

  bool _cameraGranted = false;
  bool _processing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkCamera();
  }

  Future<void> _checkCamera() async {
    final status = await Permission.camera.status;
    if (status.isGranted) {
      setState(() => _cameraGranted = true);
      return;
    }
    final result = await Permission.camera.request();
    if (mounted) setState(() => _cameraGranted = result.isGranted);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _redeem(String rawCode) async {
    if (_processing) return;
    final coachUid = _auth.currentUid;
    if (coachUid == null) return;
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      final link = await _coach.redeemCode(coachUid, rawCode);
      final profile =
          await FirestoreService().getProfile(link.clientUid);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${profile?.displayName ?? 'Client'} is now your client.',
          ),
        ),
      );
    } on CoachCodeError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _processing = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not link that client. Check the code and try again.';
          _processing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan a client code'),
        actions: [
          const SidePill(),
          if (_cameraGranted)
            IconButton(
              icon: const Icon(Icons.flashlight_on_outlined),
              tooltip: 'Torch',
              onPressed: () => _scannerController.toggleTorch(),
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _cameraGranted
                ? MobileScanner(
                    controller: _scannerController,
                    onDetect: (capture) {
                      final value = capture.barcodes.firstOrNull?.rawValue;
                      if (value != null && value.isNotEmpty) {
                        _redeem(value);
                      }
                    },
                  )
                : Container(
                    color: ForgeTheme.surface,
                    child: const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Camera access is off, so scanning is unavailable. '
                          'Type the code in below instead — or allow the '
                          'camera in your phone settings.',
                          textAlign: TextAlign.center,
                          style: ForgeTheme.bodyMuted,
                        ),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Or enter the code by hand',
                  style: ForgeTheme.bodyMediumBold,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _codeController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Client code',
                    hintText: 'FORGE-7K2Q9X',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _processing
                      ? null
                      : () => _redeem(_codeController.text),
                  child: _processing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Link client'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: ForgeTheme.errorText,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
