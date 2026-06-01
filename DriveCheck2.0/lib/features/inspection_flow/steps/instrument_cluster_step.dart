import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../../../core/i18n/translations.dart';
import '../../../core/services/inspections_service.dart';
import '../../../core/services/language_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../home/inspections_provider.dart';
import '../ai/instrument_cluster_analysis.dart';
import '../inspection_flow_provider.dart';
import '../prompts/step_intro_prompts.dart';
import '../state/assistant_utterance_provider.dart';
import '../state/step_rows_provider.dart';

/// Step 3: instrument cluster. Live rear-camera preview embedded in a
/// wide landscape frame matching a typical dashboard cluster's shape.
/// Tap shutter → GPT-4o vision OCR (odometer, fuel, warning lights,
/// tachometer) → assistant bubble + audio feedback → upload + persist
/// only after the user taps Next.
class InstrumentClusterStep extends ConsumerStatefulWidget {
  final String inspectionId;
  final VoidCallback onAdvance;

  const InstrumentClusterStep({
    super.key,
    required this.inspectionId,
    required this.onAdvance,
  });

  @override
  ConsumerState<InstrumentClusterStep> createState() => _InstrumentClusterStepState();
}

enum _Phase {
  idle, analyzing, readyToConfirm, uploading, saving, saved, badQuality, error,
  // Revisiting a step that's already completed on the backend — show
  // the saved image + extracted data, no camera, with a Redo button.
  persisted,
}

/// Instrument clusters are typically wider than tall — a 2:1 landscape
/// frame matches the dashboard binnacle of most Indian passenger cars
/// (Swift, Brezza, Creta, etc.) without much wasted area.
const double _clusterAspectRatio = 2.0;

class _InstrumentClusterStepState extends ConsumerState<InstrumentClusterStep>
    with WidgetsBindingObserver {
  static const _stepId = 'instrument_cluster';

  CameraController? _camera;
  bool _cameraReady = false;
  bool _permissionDenied = false;
  String? _cameraError;

  File? _image;
  String? _persistedImageUrl;
  InstrumentClusterResult? _result;
  _Phase _phase = _Phase.idle;
  String? _error;
  bool _isCapturing = false;

  final _service = InspectionsService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Skip booting the camera if we have a server-side completed row to
    // hydrate from — the persisted view replaces the live preview.
    if (!_hydrateFromSaved()) {
      _bootCamera();
    }
    // Always push the intro so the bubble reflects the active step
    // even on back-nav. For a completed step we update silently —
    // text + tap-to-play, no autoplay (the user already heard it).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
      final t = ref.read(translationsProvider);
      final intro = stepIntroFor(_stepId, lang, t: t);
      ref.read(assistantUtteranceProvider.notifier).say(
            intro.spokenSsml,
            display: intro.display,
            autoplay: _phase != _Phase.persisted,
          );
    });
  }

  bool _hydrateFromSaved() {
    final attempt =
        ref.read(inspectionFlowProvider(widget.inspectionId)).stepAttempt;
    if (attempt != 0) return false;
    final rows = ref.read(stepRowsProvider(widget.inspectionId)).valueOrNull;
    if (rows == null) return false;
    final row = rows.where((r) => r.stepId == _stepId).firstOrNull;
    if (row == null || !row.isCompleted) return false;
    if (row.mediaUrls.isEmpty || row.data.isEmpty) return false;

    InstrumentClusterResult parsed;
    try {
      parsed = InstrumentClusterResult.fromJson(row.data);
    } catch (_) {
      return false;
    }
    _result = parsed;
    _persistedImageUrl = row.mediaUrls.first;
    _phase = _Phase.persisted;
    return true;
  }

  void _redo() {
    ref.read(inspectionFlowProvider(widget.inspectionId).notifier).retry();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
      cam.dispose();
      _camera = null;
      _cameraReady = false;
    } else if (s == AppLifecycleState.resumed && _image == null) {
      _bootCamera();
    }
  }

  Future<void> _bootCamera() async {
    setState(() {
      _permissionDenied = false;
      _cameraError = null;
      _cameraReady = false;
    });
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _cameraError = 'No camera available');
        return;
      }
      final back = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _camera = controller;
      await controller.initialize();
      if (!mounted) return;
      setState(() => _cameraReady = true);
    } on CameraException catch (e) {
      if (!mounted) return;
      if (e.code == 'CameraAccessDenied' || e.code == 'CameraAccessRestricted') {
        setState(() => _permissionDenied = true);
      } else {
        setState(() => _cameraError = e.description ?? e.code);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _cameraError = e.toString());
    }
  }

  Future<void> _capture() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final shot = await cam.takePicture();
      final cropped = await _cropToClusterAspect(File(shot.path));
      if (!mounted) return;
      setState(() {
        _image = cropped;
        _result = null;
        _error = null;
        _isCapturing = false;
        _phase = _Phase.analyzing;
      });
      await _runOcr();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _cameraError = e.toString();
      });
    }
  }

  /// Same centre-crop logic as the RC step, just with the wider cluster
  /// aspect ratio. The inset matches the alignment-guide rectangle so
  /// OCR sees exactly what the user lined up.
  Future<File> _cropToClusterAspect(File source) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return source;

    final upright = img.bakeOrientation(decoded);
    final w = upright.width;
    final h = upright.height;

    final visibleW =
        h * _clusterAspectRatio > w ? w : (h * _clusterAspectRatio).round();
    final visibleH =
        h * _clusterAspectRatio > w ? (w / _clusterAspectRatio).round() : h;
    final cropW = (visibleW * 0.95).round();
    final cropH = (visibleH * 0.85).round();
    final x = ((w - cropW) / 2).round();
    final y = ((h - cropH) / 2).round();

    final cropped = img.copyCrop(upright, x: x, y: y, width: cropW, height: cropH);
    final outBytes = img.encodeJpg(cropped, quality: 85);

    final tmpDir = await getTemporaryDirectory();
    final outFile = File('${tmpDir.path}/cluster_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await outFile.writeAsBytes(outBytes, flush: true);
    return outFile;
  }

  Future<void> _retake() async {
    setState(() {
      _image = null;
      _result = null;
      _error = null;
      _phase = _Phase.idle;
    });
    if (_camera == null || !(_camera!.value.isInitialized)) {
      await _bootCamera();
    }
  }

  Future<void> _runOcr() async {
    if (_image == null) return;

    InstrumentClusterResult result;
    try {
      final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
      result = await InstrumentClusterAnalyzer().analyze(_image!, language: lang);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'OCR failed: $e';
        _phase = _Phase.error;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _result = result);

    if (!result.isUsable) {
      setState(() => _phase = _Phase.badQuality);
      final spoken = result.qualityReasonSpoken;
      if (spoken != null && spoken.trim().isNotEmpty) {
        ref.read(assistantUtteranceProvider.notifier)
            .say(spoken, display: result.qualityReasonDisplay);
      }
      return;
    }

    ref.read(inspectionFlowProvider(widget.inspectionId).notifier)
        .recordAnswer(_stepId, result.toBackendData());

    setState(() => _phase = _Phase.readyToConfirm);

    final spoken = result.successMessageSpoken;
    if (spoken != null && spoken.trim().isNotEmpty) {
      ref.read(assistantUtteranceProvider.notifier)
          .say(spoken, display: result.successMessageDisplay);
    }
  }

  /// Upload-on-Next: defers S3 + completed-status write to confirm time.
  /// Test photos that get retaken never leave the device.
  Future<void> _confirmAndAdvance() async {
    final result = _result;
    final image = _image;
    if (result == null || image == null) return;

    setState(() => _phase = _Phase.uploading);
    String mediaUrl;
    try {
      final bytes = await image.readAsBytes();
      mediaUrl = await _service.uploadStepMedia(
        widget.inspectionId,
        _stepId,
        bytes,
        mimeType: 'image/jpeg',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Upload failed: $e';
        _phase = _Phase.error;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _phase = _Phase.saving);
    try {
      // Cluster OCR is authoritative for the odometer reading. Push it
      // through parentUpdates as `kmDriven` so the home card and flow
      // header's computed subtitle pick up the live mileage. Only sent
      // when it actually differs from what the inspection already has —
      // avoids no-op writes on a Redo.
      final inspection = ref
          .read(inspectionsProvider)
          .where((i) => i.id == widget.inspectionId)
          .firstOrNull;
      final updatesPayload = (result.odometerKm != null &&
              inspection != null &&
              result.odometerKm != inspection.kmDriven)
          ? {'kmDriven': result.odometerKm}
          : null;

      await _service.updateStep(
        widget.inspectionId,
        _stepId,
        mediaUrls: [mediaUrl],
        data: result.toBackendData(),
        aiAnalysis: {
          'quality': result.quality.name,
          'qualityReasonDisplay': result.qualityReasonDisplay,
          'qualityReasonSpoken': result.qualityReasonSpoken,
          'successMessageDisplay': result.successMessageDisplay,
          'successMessageSpoken': result.successMessageSpoken,
        },
        status: 'completed',
        parentUpdates: updatesPayload,
      );

      if (updatesPayload != null) {
        unawaited(ref.read(inspectionsAsyncProvider.notifier).refresh());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Save failed: $e';
        _phase = _Phase.error;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _phase = _Phase.saved);
    // Refresh saved rows so a back-nav re-enters persisted view.
    unawaited(ref.read(stepRowsProvider(widget.inspectionId).notifier).refresh());
    widget.onAdvance();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final busy = _phase == _Phase.analyzing ||
        _phase == _Phase.uploading ||
        _phase == _Phase.saving;
    final overlayLabel = switch (_phase) {
      _Phase.analyzing => 'Analysing…',
      _Phase.uploading => 'Uploading photo…',
      _Phase.saving    => 'Saving…',
      _                => null,
    };

    final isPersisted = _phase == _Phase.persisted;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ClusterFrame(
            image: _image,
            imageUrl: isPersisted ? _persistedImageUrl : null,
            camera: _camera,
            cameraReady: _cameraReady,
            permissionDenied: _permissionDenied,
            cameraError: _cameraError,
            overlayLabel: overlayLabel,
            onRetryPermission: _bootCamera,
          ),
          const SizedBox(height: 16),
          if (_phase == _Phase.error && _error != null)
            _ErrorCard(message: _error!, onRetry: _runOcr),
          // Bad-quality + intro speech come through the shell-level
          // assistant bubble. This body only shows the structured
          // cluster details once a usable read is in.
          if (_result != null && _result!.isUsable)
            _ClusterResultCard(result: _result!, t: t),
          const SizedBox(height: 16),
          _PrimaryAction(
            t: t,
            phase: _phase,
            hasImage: _image != null,
            cameraReady: _cameraReady,
            isCapturing: _isCapturing,
            busy: busy,
            onCapture: _capture,
            onRetake: _retake,
            onContinue: isPersisted ? widget.onAdvance : _confirmAndAdvance,
            onRedo: _redo,
          ),
        ],
      ),
    );
  }
}

// ---- Viewport / shutter / overlays (mirror of RC, wider aspect) ----

class _ClusterFrame extends StatelessWidget {
  final File? image;
  final String? imageUrl;
  final CameraController? camera;
  final bool cameraReady;
  final bool permissionDenied;
  final String? cameraError;
  final String? overlayLabel;
  final VoidCallback onRetryPermission;

  const _ClusterFrame({
    required this.image,
    required this.camera,
    required this.cameraReady,
    required this.permissionDenied,
    required this.cameraError,
    required this.overlayLabel,
    required this.onRetryPermission,
    this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    final hasAnyImage = image != null || imageUrl != null;
    return AspectRatio(
      aspectRatio: _clusterAspectRatio,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _content(),
              if (!hasAnyImage && cameraReady) const _AlignmentGuide(),
              if (overlayLabel != null) _BusyOverlay(label: overlayLabel!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    if (image != null) return Image.file(image!, fit: BoxFit.cover);
    if (imageUrl != null) {
      // Persisted photo loaded from S3 on revisit.
      return Image.network(
        imageUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) =>
            progress == null
                ? child
                : const Center(child: CircularProgressIndicator(strokeWidth: 3)),
        errorBuilder: (_, _, _) => const Center(
          child: Icon(Icons.broken_image_rounded,
              size: 40, color: AppColors.textHint),
        ),
      );
    }
    if (permissionDenied) return _PermissionBlocked(onRetry: onRetryPermission);
    if (cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(cameraError!,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(color: AppColors.error)),
        ),
      );
    }
    final cam = camera;
    if (cam == null || !cameraReady) {
      return const Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        width: cam.value.previewSize?.height ?? 1,
        height: cam.value.previewSize?.width ?? 1,
        child: CameraPreview(cam),
      ),
    );
  }
}

class _AlignmentGuide extends StatelessWidget {
  const _AlignmentGuide();
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.95,
          heightFactor: 0.85,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
            ),
          ),
        ),
      ),
    );
  }
}

class _BusyOverlay extends StatelessWidget {
  final String label;
  const _BusyOverlay({required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.ctaDark.withValues(alpha: 0.55),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 36, width: 36, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _PermissionBlocked extends ConsumerWidget {
  final VoidCallback onRetry;
  const _PermissionBlocked({required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.no_photography_rounded, size: 40, color: AppColors.textSecondary),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(t.cameraAccessNeeded,
              textAlign: TextAlign.center,
              style: t.style(AppTextStyles.body)),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onRetry,
            child: Text(t.tryAgain,
                style: t.style(AppTextStyles.button)
                    .copyWith(color: AppColors.primary))),
      ],
    );
  }
}

// ---- Result card: prominent odometer + warning chip strip ----

class _ClusterResultCard extends StatelessWidget {
  final InstrumentClusterResult result;
  final Translations t;
  const _ClusterResultCard({required this.result, required this.t});

  @override
  Widget build(BuildContext context) {
    final lit = result.warningLights
        .where((w) => w != WarningLight.unknown || true) // keep unknowns visible
        .toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F8F1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
            const SizedBox(width: 8),
            Text('Cluster read', style: AppTextStyles.heading3.copyWith(color: AppColors.success)),
          ]),
          const SizedBox(height: 14),
          // Odometer is the headline. Big, bold, instantly verifiable.
          if (result.odometerKm != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    _formatKm(result.odometerKm!),
                    style: AppTextStyles.heading1.copyWith(
                      fontSize: 32,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text('km', style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ),
          _row('Fuel', _fuelLabel(result.fuelLevel)),
          if (result.tachometerRpm != null && result.tachometerRpm! > 0)
            _row('RPM', result.tachometerRpm.toString()),
          if (result.tripMeterKm != null)
            _row('Trip', '${result.tripMeterKm!.toStringAsFixed(1)} km'),
          if (result.clusterType != null) _row('Cluster', _clusterLabel(result.clusterType!)),
          if (lit.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Warning lights (${lit.length})',
              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: lit.map(_WarningChip.new).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 70, child: Text(label, style: AppTextStyles.caption)),
          Expanded(child: Text(value, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  String? _fuelLabel(FuelLevel? l) {
    if (l == null) return null;
    switch (l) {
      case FuelLevel.empty:        return 'Empty';
      case FuelLevel.low:          return 'Low';
      case FuelLevel.quarter:      return '¼ tank';
      case FuelLevel.half:         return '½ tank';
      case FuelLevel.threeQuarter: return '¾ tank';
      case FuelLevel.full:         return 'Full';
    }
  }

  String _clusterLabel(ClusterType c) {
    switch (c) {
      case ClusterType.analog:  return 'Analog';
      case ClusterType.digital: return 'Digital';
      case ClusterType.hybrid:  return 'Hybrid';
    }
  }

  /// Indian-style number formatting with commas (47000 → "47,000").
  /// Keeps the odometer legible at a glance for the jockey.
  String _formatKm(int km) {
    final s = km.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _WarningChip extends StatelessWidget {
  final WarningLight light;
  const _WarningChip(this.light);

  @override
  Widget build(BuildContext context) {
    final c = _severityColour(light.severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            light.displayName,
            style: AppTextStyles.caption.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Color _severityColour(WarningSeverity s) {
    switch (s) {
      case WarningSeverity.critical: return AppColors.error;
      case WarningSeverity.caution:  return AppColors.warning;
      case WarningSeverity.info:     return AppColors.textSecondary;
    }
  }
}

class _ErrorCard extends ConsumerWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider);
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message,
              style: t.style(AppTextStyles.body)
                  .copyWith(color: AppColors.error))),
          TextButton(onPressed: onRetry,
              child: Text(t.tryAgain,
                  style: t.style(AppTextStyles.button)
                      .copyWith(color: AppColors.primary))),
        ],
      ),
    );
  }
}

// ---- Primary action (shutter / next / retake) ----

class _PrimaryAction extends StatelessWidget {
  final Translations t;
  final _Phase phase;
  final bool hasImage;
  final bool cameraReady;
  final bool isCapturing;
  final bool busy;
  final VoidCallback onCapture;
  final VoidCallback onRetake;
  final VoidCallback onContinue;
  final VoidCallback onRedo;

  const _PrimaryAction({
    required this.t,
    required this.phase,
    required this.hasImage,
    required this.cameraReady,
    required this.isCapturing,
    required this.busy,
    required this.onCapture,
    required this.onRetake,
    required this.onContinue,
    required this.onRedo,
  });

  @override
  Widget build(BuildContext context) {
    if (busy) return const SizedBox.shrink();
    // Revisit of an already-completed step: Redo (re-enters capture)
    // or Next (advance, no backend write needed).
    if (phase == _Phase.persisted) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onRedo,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(t.redo, style: t.style(AppTextStyles.button).copyWith(color: AppColors.primary)),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.onCtaDark),
              label: Text(t.next, style: AppTextStyles.button),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
            ),
          ),
        ],
      );
    }
    if (!hasImage) {
      return _ShutterButton(
        enabled: cameraReady && !isCapturing,
        loading: isCapturing,
        onTap: onCapture,
      );
    }
    if (phase == _Phase.readyToConfirm || phase == _Phase.saved) {
      return ElevatedButton.icon(
        onPressed: onContinue,
        icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.onCtaDark),
        label: Text(t.next, style: AppTextStyles.button),
      );
    }
    return OutlinedButton.icon(
      onPressed: onRetake,
      icon: const Icon(Icons.refresh_rounded),
      label: Text(t.retake, style: t.style(AppTextStyles.button).copyWith(color: AppColors.primary)),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
    );
  }
}

class _ShutterButton extends StatelessWidget {
  final bool enabled;
  final bool loading;
  final VoidCallback onTap;
  const _ShutterButton({required this.enabled, required this.loading, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Opacity(
          opacity: enabled || loading ? 1 : 0.5,
          child: Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary,
              border: Border.all(color: AppColors.onPrimary, width: 4),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: loading
                ? const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.onPrimary),
                  )
                : const Icon(Icons.camera_alt_rounded, color: AppColors.onPrimary, size: 32),
          ),
        ),
      ),
    );
  }
}

