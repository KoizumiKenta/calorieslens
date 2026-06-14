import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// Camera barcode scanner. Pops the detected EAN/UPC string, or the sentinel
/// [manualSentinel] if the user chooses to type it instead. Web builds don't
/// use this screen — they go straight to manual entry.
///
/// Uses flutter_zxing (zxing-cpp, native) rather than ML Kit: ML Kit routes
/// through a Google Play Services optional module that returns a null model on
/// some MIUI/Xiaomi and Play-Services-flaky devices, surfacing as
/// MobileScannerErrorCode.genericError ("invoke virtual method ... on a null
/// object reference"). zxing has no Play Services dependency, so it works on
/// any Android device with a camera.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  static const manualSentinel = '__manual__';

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  // Retail packaged-food barcodes are 1D EAN/UPC.
  static const _formats =
      Format.ean13 | Format.ean8 | Format.upca | Format.upce;

  bool _handled = false;

  void _onScan(Code code) {
    if (_handled) return;
    final value = code.text;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan barcode'),
        actions: [
          IconButton(
            tooltip: 'Type instead',
            icon: const Icon(Icons.keyboard),
            onPressed: () =>
                Navigator.pop(context, BarcodeScannerScreen.manualSentinel),
          ),
        ],
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          ReaderWidget(
            onScan: _onScan,
            codeFormat: _formats,
            tryHarder: true,
            tryInverted: true,
            showGallery: false,
            showToggleCamera: false,
            scanDelay: const Duration(milliseconds: 500),
          ),
          const Positioned(
            bottom: 40,
            left: 24,
            right: 24,
            child: Text(
              'Point at a packaged-food barcode',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 8, color: Colors.black)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
