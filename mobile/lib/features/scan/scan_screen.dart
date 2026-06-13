import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'scan_controller.dart';

/// Capture screen. On web/desktop image_picker opens a file dialog; on
/// device builds this becomes the full camera UI (multi-angle, barcode,
/// label modes — reference/pubspec.full.yaml).
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _picker = ImagePicker();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final file = await _picker.pickImage(source: source, maxWidth: 1280);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    ref.read(scanControllerProvider.notifier).setImage(bytes);
  }

  Future<void> _analyze() async {
    final ok = await ref
        .read(scanControllerProvider.notifier)
        .analyze(note: _noteController.text);
    if (ok && mounted) context.push('/scan/review');
  }

  /// image_picker's camera source works on Android/iOS (no camera plugin
  /// needed for single shots — the full multi-angle capture UI comes with
  /// the device milestone).
  bool get _hasCamera =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan a meal')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: state.imageBytes == null
                    ? _emptyState(scheme)
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(state.imageBytes!, fit: BoxFit.cover),
                          if (state.analyzing) _analyzingOverlay(scheme),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              enabled: !state.analyzing,
              textInputAction: TextInputAction.done,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Tell the AI more (optional)',
                hintText: 'e.g. "milo kosong, chicken is air-fried, no skin"',
                counterText: '',
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (state.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(state.error!,
                    style: TextStyle(color: scheme.error),
                    textAlign: TextAlign.center),
              ),
            Row(
              children: [
                if (_hasCamera) ...[
                  OutlinedButton(
                    onPressed: state.analyzing
                        ? null
                        : () => _pick(ImageSource.camera),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(52, 52),
                        padding: EdgeInsets.zero),
                    child: const Icon(Icons.photo_camera_outlined),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: state.analyzing
                        ? null
                        : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    // "Gallery" when a camera button sits beside it; the
                    // fuller "Choose photo" on web where it's the only picker.
                    label: Text(
                      state.imageBytes != null
                          ? 'Change'
                          : (_hasCamera ? 'Gallery' : 'Choose photo'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(64, 52)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: state.imageBytes == null || state.analyzing
                        ? null
                        : _analyze,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      state.analyzing ? 'Analyzing…' : 'Analyze',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(ColorScheme scheme) {
    return InkWell(
      onTap: () => _pick(ImageSource.gallery),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.restaurant_rounded, size: 64, color: scheme.primary),
          const SizedBox(height: 16),
          const Text('Snap or choose a meal photo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Mixed dishes welcome — nasi lemak gets broken into rice, sambal, egg, anchovies and more.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('📐', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'For the most accurate calories: shoot from slightly above, '
                    'and put a fork, spoon or your hand in frame for scale.',
                    style: TextStyle(
                        color: scheme.onSurfaceVariant, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _analyzingOverlay(ColorScheme scheme) {
    return Container(
      color: Colors.black54,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Detecting foods…\nestimating portions…',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }
}
