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
import '../ai/photo_quality_analysis.dart';
import '../inspection_flow_provider.dart';
import '../prompts/step_intro_prompts.dart';
import '../state/assistant_utterance_provider.dart';
import '../state/step_rows_provider.dart';

/// Generic single-photo capture step. Reused by every freeform exterior
/// / interior shot that doesn't need OCR: engine_bay, front_full,
/// lhs_full, rhs_full, rear_full, roof, interior.
///
/// Pipeline: live preview → capture → confirm → upload-to-S3 → mark
/// completed → advance. On revisit (state hydrated from
/// [stepRowsProvider]) renders the saved S3 image with Redo / Next
/// instead of booting the camera.
class SimplePhotoStep extends ConsumerStatefulWidget {
  final String inspectionId;
  final String stepId;
  final VoidCallback onAdvance;

  /// Aspect ratio of the framed viewport. 4:3 landscape (1.33) is the
  /// default — matches what a phone in portrait orientation crops to
  /// when you frame a car in a typical "stand 2 steps back" shot.
  final double aspectRatio;

  const SimplePhotoStep({
    super.key,
    required this.inspectionId,
    required this.stepId,
    required this.onAdvance,
    this.aspectRatio = 1.33,
  });

  @override
  ConsumerState<SimplePhotoStep> createState() => _SimplePhotoStepState();
}

/// Pipeline phases.
/// - idle: live preview
/// - analyzing: GPT-4o checking blur + subject match
/// - readyToConfirm: photo passed AI check, awaiting Use-this-photo
/// - badQuality: AI rejected the photo, user must retake
/// - uploading / saving: confirmed photo going to S3 + backend
/// - saved / error
/// - persisted: revisit of a completed step
enum _Phase {
  idle, analyzing, readyToConfirm, badQuality,
  uploading, saving, saved, error, persisted,
}

class _SimplePhotoStepState extends ConsumerState<SimplePhotoStep>
    with WidgetsBindingObserver {
  CameraController? _camera;
  bool _cameraReady = false;
  bool _permissionDenied = false;
  String? _cameraError;

  File? _image;
  String? _persistedImageUrl;
  _Phase _phase = _Phase.idle;
  String? _error;
  bool _isCapturing = false;
  PhotoQualityResult? _quality;

  final _service = InspectionsService();
  final _analyzer = PhotoQualityAnalyzer();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!_hydrateFromSaved()) {
      _bootCamera();
    }
    // Mirror the RC / Cluster pattern: push the intro to the shell
    // bubble; silent on revisit (the user already heard it).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
      final t = ref.read(translationsProvider);
      final intro = stepIntroFor(widget.stepId, lang, t: t);
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
    final row = rows.where((r) => r.stepId == widget.stepId).firstOrNull;
    if (row == null || !row.isCompleted) return false;
    if (row.mediaUrls.isEmpty) return false;
    _persistedImageUrl = row.mediaUrls.first;
    // Pull the AI verdict back out of the saved row so the persisted
    // view can render the same quality card the user saw at confirm
    // time — no second OpenAI call needed.
    final ai = row.aiAnalysis;
    if (ai != null && ai.isNotEmpty) {
      try {
        _quality = PhotoQualityResult.fromJson(ai);
      } catch (_) {
        // Older row shape (pre-quality-analysis) — fall through with
        // no verdict, view degrades to image-only.
      }
    }
    _phase = _Phase.persisted;
    return true;
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
      final cropped = await _cropToAspect(File(shot.path));
      if (!mounted) return;
      setState(() {
        _image = cropped;
        _quality = null;
        _error = null;
        _isCapturing = false;
        _phase = _Phase.analyzing;
      });
      await _runQualityCheck();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _cameraError = e.toString();
      });
    }
  }

  /// AI-side blur + subject check before we upload. Mirrors the RC
  /// step's OCR phase but uses the generic [PhotoQualityAnalyzer] so
  /// the model can also flag wrong-subject (e.g. user shot the engine
  /// instead of the requested front view). On bad-quality, pushes the
  /// model's spoken reason into the shell-level assistant bubble and
  /// forces a retake — nothing reaches S3 until the check passes.
  Future<void> _runQualityCheck() async {
    final image = _image;
    if (image == null) return;
    final subject = StepPhotoSubjects.forStep(widget.stepId);
    if (subject == null) {
      // Step opted out of AI quality checks — fall straight through
      // to the confirmation phase (preserves the original simple
      // capture-and-upload flow for future steps that don't need it).
      setState(() => _phase = _Phase.readyToConfirm);
      return;
    }

    PhotoQualityResult result;
    try {
      final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
      result = await _analyzer.analyze(
        image,
        language: lang,
        subjectShort: subject.shortLabel,
        subjectDescription: subject.description,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Quality check failed: $e';
        _phase = _Phase.error;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _quality = result);

    if (!result.isUsable) {
      setState(() => _phase = _Phase.badQuality);
      final spoken = result.qualityReasonSpoken;
      if (spoken != null && spoken.trim().isNotEmpty) {
        ref.read(assistantUtteranceProvider.notifier)
            .say(spoken, display: result.qualityReasonDisplay);
      }
      return;
    }

    setState(() => _phase = _Phase.readyToConfirm);
    final spoken = result.successMessageSpoken;
    if (spoken != null && spoken.trim().isNotEmpty) {
      ref.read(assistantUtteranceProvider.notifier)
          .say(spoken, display: result.successMessageDisplay);
    }
  }

  /// Centre-crop the captured JPEG to the same aspect ratio as the
  /// on-screen viewport so the saved file matches what the user saw.
  Future<File> _cropToAspect(File source) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return source;

    final upright = img.bakeOrientation(decoded);
    final w = upright.width;
    final h = upright.height;

    final visibleW =
        h * widget.aspectRatio > w ? w : (h * widget.aspectRatio).round();
    final visibleH =
        h * widget.aspectRatio > w ? (w / widget.aspectRatio).round() : h;
    final x = ((w - visibleW) / 2).round();
    final y = ((h - visibleH) / 2).round();

    final cropped = img.copyCrop(upright, x: x, y: y, width: visibleW, height: visibleH);
    final outBytes = img.encodeJpg(cropped, quality: 85);

    final tmpDir = await getTemporaryDirectory();
    final outFile = File(
        '${tmpDir.path}/${widget.stepId}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await outFile.writeAsBytes(outBytes, flush: true);
    return outFile;
  }

  Future<void> _retake() async {
    setState(() {
      _image = null;
      _quality = null;
      _error = null;
      _phase = _Phase.idle;
    });
    if (_camera == null || !(_camera!.value.isInitialized)) {
      await _bootCamera();
    }
  }

  void _redo() {
    ref.read(inspectionFlowProvider(widget.inspectionId).notifier).retry();
  }

  /// Upload the captured photo to S3 then mark the step completed on
  /// the backend. Mirrors the RC/Cluster upload-on-confirm pattern so
  /// retaken/discarded photos never leave the device.
  Future<void> _confirmAndAdvance() async {
    final image = _image;
    if (image == null) return;

    setState(() => _phase = _Phase.uploading);
    String mediaUrl;
    try {
      final bytes = await image.readAsBytes();
      mediaUrl = await _service.uploadStepMedia(
        widget.inspectionId,
        widget.stepId,
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
      await _service.updateStep(
        widget.inspectionId,
        widget.stepId,
        mediaUrls: [mediaUrl],
        aiAnalysis: _quality?.toAiAnalysis(),
        status: 'completed',
      );
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
      _Phase.analyzing => 'Checking photo…',
      _Phase.uploading => 'Uploading photo…',
      _Phase.saving    => 'Saving…',
      _                => null,
    };
    final isPersisted = _phase == _Phase.persisted;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PhotoFrame(
            aspectRatio: widget.aspectRatio,
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
            _ErrorCard(message: _error!, onRetry: _confirmAndAdvance),
          // AI quality verdict — shown after the model has analysed
          // the photo (readyToConfirm / badQuality) and when the user
          // revisits a completed step (persisted). Mirrors the result
          // cards in RC / Cluster steps so every photo step renders
          // its findings the same way.
          if (_quality != null &&
              (_phase == _Phase.persisted ||
               _phase == _Phase.readyToConfirm ||
               _phase == _Phase.badQuality))
            _QualityVerdictCard(quality: _quality!),
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

/// Aspect-ratio'd viewport identical in shape to the RC/Cluster frames
/// but without the dashed alignment guide — freeform car shots don't
/// have a card-shaped target to line up against.
class _PhotoFrame extends StatelessWidget {
  final double aspectRatio;
  final File? image;
  final String? imageUrl;
  final CameraController? camera;
  final bool cameraReady;
  final bool permissionDenied;
  final String? cameraError;
  final String? overlayLabel;
  final VoidCallback onRetryPermission;

  const _PhotoFrame({
    required this.aspectRatio,
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
    return AspectRatio(
      aspectRatio: aspectRatio,
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
            const SizedBox(
                height: 36,
                width: 36,
                child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
            const SizedBox(height: 12),
            Text(label,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
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
        const Icon(Icons.no_photography_rounded,
            size: 40, color: AppColors.textSecondary),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            t.cameraAccessNeeded,
            textAlign: TextAlign.center,
            style: t.style(AppTextStyles.body),
          ),
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

/// Renders the AI photo-quality verdict (good / blurry / dark / wrong
/// subject / partial / unreadable) with a colour-coded chip and the
/// model's spoken/displayed reason. Shown in the persisted-revisit
/// view AND in the live readyToConfirm / badQuality phases so the
/// jockey sees the same card across every state.
class _QualityVerdictCard extends StatelessWidget {
  final PhotoQualityResult quality;
  const _QualityVerdictCard({required this.quality});

  @override
  Widget build(BuildContext context) {
    final isGood = quality.isUsable;
    final tone = isGood ? AppColors.success : AppColors.error;
    final icon = isGood
        ? Icons.check_circle_rounded
        : Icons.warning_amber_rounded;
    final label = _labelFor(quality.quality);
    final caption = isGood
        ? (quality.successMessageDisplay ?? '')
        : (quality.qualityReasonDisplay ?? '');
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: tone, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.heading3
                        .copyWith(color: tone, fontSize: 15)),
                if (caption.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(caption,
                      style: AppTextStyles.body.copyWith(
                        color: AppColors.textPrimary,
                        height: 1.4,
                      )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _labelFor(PhotoQuality q) {
    switch (q) {
      case PhotoQuality.good:         return 'Photo accepted';
      case PhotoQuality.blurry:       return 'Photo is blurry';
      case PhotoQuality.dark:         return 'Photo is dark';
      case PhotoQuality.partial:      return 'Subject partial';
      case PhotoQuality.wrongSubject: return 'Wrong subject';
      case PhotoQuality.unreadable:   return 'Unreadable';
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
          Expanded(
            child: Text(message,
                style: t.style(AppTextStyles.body)
                    .copyWith(color: AppColors.error)),
          ),
          TextButton(onPressed: onRetry,
              child: Text(t.tryAgain,
                  style: t.style(AppTextStyles.button)
                      .copyWith(color: AppColors.primary))),
        ],
      ),
    );
  }
}

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
    // AI rejected the photo. Force retake — no "Use this anyway" escape
    // hatch on purpose: a wrong-subject / blurry photo passes nothing
    // useful downstream and just creates a bad data point.
    if (phase == _Phase.badQuality) {
      return SizedBox(
        height: 56,
        child: ElevatedButton.icon(
          onPressed: onRetake,
          icon: const Icon(Icons.refresh_rounded, color: AppColors.onCtaDark),
          label: Text(t.retake, style: AppTextStyles.button),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            minimumSize: const Size.fromHeight(56),
          ),
        ),
      );
    }
    // AI passed (readyToConfirm) — show Retake fallback alongside the
    // primary Use-this-photo action. Two-button row so the jockey can
    // still re-shoot if they personally don't like the framing even
    // though the model accepted it.
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onRetake,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(t.retake, style: t.style(AppTextStyles.button).copyWith(color: AppColors.primary)),
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
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: AppColors.onPrimary),
                  )
                : const Icon(Icons.camera_alt_rounded,
                    color: AppColors.onPrimary, size: 32),
          ),
        ),
      ),
    );
  }
}
