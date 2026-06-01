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
import '../ai/rc_analysis.dart';
import '../inspection_flow_provider.dart';
import '../prompts/step_intro_prompts.dart';
import '../state/assistant_utterance_provider.dart';
import '../state/step_rows_provider.dart';

/// Step 2: RC document. Live rear-camera preview is embedded inside an
/// RC-card-shaped frame so the jockey can line up the card; tap the shutter
/// to capture → GPT-4o vision OCR → upload photo to S3 → mark the
/// InspectionSteps row complete on the backend → enable "Next".
class RcDocumentStep extends ConsumerStatefulWidget {
  final String inspectionId;
  final VoidCallback onAdvance;

  const RcDocumentStep({super.key, required this.inspectionId, required this.onAdvance});

  @override
  ConsumerState<RcDocumentStep> createState() => _RcDocumentStepState();
}

/// Pipeline phases after the user shoots.
/// - idle: live preview, no photo yet
/// - analyzing: OCR running (no network upload yet — the bytes never
///   leave the device until the user confirms)
/// - readyToConfirm: photo captured, OCR done, RC details shown. Nothing
///   has touched S3 or the backend yet.
/// - uploading / saving: user tapped Continue; S3 upload then updateStep
/// - saved: backend acknowledged; advances to next step
/// - badQuality / error: stuck states, user must retake
enum _Phase {
  idle, analyzing, readyToConfirm, uploading, saving, saved, badQuality, error,
  // The user is revisiting a step they already completed; the saved
  // image + extracted data are shown read-only with a "Redo" button
  // that drops back into capture mode.
  persisted,
}

/// Indian RC smart card is 85.6×54 mm (ISO ID-1, same as a credit card) →
/// 1.586 ratio. Round to 1.6 for the preview frame.
const double _rcCardAspectRatio = 1.6;

class _RcDocumentStepState extends ConsumerState<RcDocumentStep>
    with WidgetsBindingObserver {
  static const _stepId = 'rc_document';

  CameraController? _camera;
  bool _cameraReady = false;
  bool _permissionDenied = false;
  String? _cameraError;

  File? _image;
  // Populated only in the persisted phase (revisiting a completed step)
  // — the previously captured photo lives at this S3 URL.
  String? _persistedImageUrl;
  RcAnalysisResult? _result;
  _Phase _phase = _Phase.idle;
  String? _error;
  bool _isCapturing = false;

  final _service = InspectionsService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // If the user is revisiting a step they already completed AND hasn't
    // hit the Retry button this session (stepAttempt == 0), skip the
    // camera and render the saved image + extracted data instead. The
    // camera is only booted in fresh-capture mode.
    if (!_hydrateFromSaved()) {
      _bootCamera();
    }
    // Push the step intro to the shell-level assistant bubble so its
    // text always matches the active step — including when the user
    // navigates back to a completed step. For persisted steps we set
    // `autoplay: false` so the bubble updates silently (text + tap-to-
    // play) rather than re-narrating something the user already heard.
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

  /// Returns true if we hydrated from a server-side completed step row
  /// and set [_Phase.persisted]; false if the user should be put into
  /// fresh capture mode.
  bool _hydrateFromSaved() {
    final attempt =
        ref.read(inspectionFlowProvider(widget.inspectionId)).stepAttempt;
    if (attempt != 0) return false; // user tapped Retry — start fresh
    final rows = ref.read(stepRowsProvider(widget.inspectionId)).valueOrNull;
    if (rows == null) return false;
    final row = rows.where((r) => r.stepId == _stepId).firstOrNull;
    if (row == null || !row.isCompleted) return false;
    if (row.mediaUrls.isEmpty || row.data.isEmpty) return false;

    RcAnalysisResult parsed;
    try {
      parsed = RcAnalysisResult.fromJson(row.data);
    } catch (_) {
      return false;
    }
    _result = parsed;
    _persistedImageUrl = row.mediaUrls.first;
    _phase = _Phase.persisted;
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  /// Pause/resume the preview with app lifecycle — required by the `camera`
  /// package, otherwise the texture freezes when returning from background.
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
      // takePicture returns the full sensor frame regardless of how the
      // preview is cropped on screen. Centre-crop the saved JPEG to the
      // same aspect ratio as the card-shaped viewport so OCR only sees
      // what the user lined up — not the surroundings.
      final cropped = await _cropToCardAspect(File(shot.path));
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

  /// Centre-crops a captured JPEG to [_rcCardAspectRatio] (landscape).
  /// Runs on the main isolate — RC photos at `ResolutionPreset.high` are
  /// ~2-3 MP, decode + crop + re-encode takes well under a second on a
  /// mid-range Android. Writes the cropped file next to the original so
  /// the original is still discoverable for debugging.
  Future<File> _cropToCardAspect(File source) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return source; // bail out, ship the original

    // The sensor produces a landscape image when the phone is held in
    // portrait (90° rotation). Bake the EXIF orientation in so width/height
    // below match what the preview showed.
    final upright = img.bakeOrientation(decoded);
    final w = upright.width;
    final h = upright.height;

    // Match the on-screen card aspect ratio. Preview uses BoxFit.cover so
    // the visible region inside the frame is the centred 1.6:1 slice.
    final visibleW = h * _rcCardAspectRatio > w ? w : (h * _rcCardAspectRatio).round();
    final visibleH = h * _rcCardAspectRatio > w ? (w / _rcCardAspectRatio).round() : h;
    // Then inset to match the alignment guide (92% width × 86% height of
    // the visible area) — that's the rectangle the user actually lined
    // the card up against.
    final cropW = (visibleW * 0.92).round();
    final cropH = (visibleH * 0.86).round();
    final x = ((w - cropW) / 2).round();
    final y = ((h - cropH) / 2).round();

    final cropped = img.copyCrop(upright, x: x, y: y, width: cropW, height: cropH);
    final outBytes = img.encodeJpg(cropped, quality: 85);

    final tmpDir = await getTemporaryDirectory();
    final outFile = File('${tmpDir.path}/rc_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await outFile.writeAsBytes(outBytes, flush: true);
    return outFile;
  }

  /// User chose to retake — drop the photo, re-init the preview if needed.
  /// Because nothing has touched S3 yet, there's no orphan to clean up.
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

  /// OCR only. Stops at `readyToConfirm` — no S3 upload, no backend write.
  /// The captured bytes stay on-device until the user explicitly taps
  /// Continue, which fires [_confirmAndAdvance].
  Future<void> _runOcr() async {
    if (_image == null) return;

    RcAnalysisResult result;
    try {
      // Pass the current app language so the model writes qualityReason
      // in a tongue + script the user can both read on screen AND that
      // ElevenLabs TTS will pronounce correctly. Default to Hindi for the
      // edge case where the user hasn't picked yet — matches the same
      // default used elsewhere in the app.
      final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
      result = await RcAnalyzer().analyze(_image!, language: lang);
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
      // Push the bad-quality feedback through the shell-level assistant
      // bubble. It speaks + animates in the same component the intro
      // used, so the user sees one continuous conversational thread.
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

    // Same channel as the intro / bad-quality paths — shell-level bubble.
    final spoken = result.successMessageSpoken;
    if (spoken != null && spoken.trim().isNotEmpty) {
      ref.read(assistantUtteranceProvider.notifier)
          .say(spoken, display: result.successMessageDisplay);
    }
  }

  /// User tapped "Continue" on the result card. Uploads the captured
  /// photo to S3, then marks the step completed on the backend. The
  /// upload happens here (rather than right after capture) so test
  /// photos that the user discards never leave the device.
  ///
  /// Before any network traffic fires: if the OCR'd vehicle metadata
  /// (carTitle / model / year / fuel) differs from what the booking
  /// originally said, pop a confirmation modal listing the diffs side
  /// by side. The jockey has to explicitly accept the RC-derived
  /// values before we overwrite the parent inspection — silent
  /// changes were causing surprise mid-flow.
  Future<void> _confirmAndAdvance() async {
    final result = _result;
    final image = _image;
    if (result == null || image == null) return;

    // ---- 0. Compute parent-metadata diff before any I/O ----
    final ocrTitle = [result.make, result.model]
        .whereType<String>()
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .join(' ');
    final ocrModel = result.model?.trim();
    final ocrYear = _yearFromIsoDate(result.manufacturingDate);
    final ocrFuel = result.fuelType?.trim();
    final inspection = ref
        .read(inspectionsProvider)
        .where((i) => i.id == widget.inspectionId)
        .firstOrNull;
    final diffs = <_FieldDiff>[];
    final parentUpdates = <String, dynamic>{};
    if (inspection != null) {
      if (ocrTitle.isNotEmpty && ocrTitle != inspection.carTitle.trim()) {
        parentUpdates['carTitle'] = ocrTitle;
        diffs.add(_FieldDiff('Car title', inspection.carTitle, ocrTitle));
      }
      if (ocrModel != null && ocrModel.isNotEmpty &&
          ocrModel != (inspection.model?.trim() ?? '')) {
        parentUpdates['model'] = ocrModel;
        diffs.add(_FieldDiff('Model', inspection.model ?? '—', ocrModel));
      }
      if (ocrYear != null && ocrYear != inspection.yearOfMake) {
        parentUpdates['yearOfMake'] = ocrYear;
        diffs.add(_FieldDiff('Year',
            inspection.yearOfMake?.toString() ?? '—', ocrYear.toString()));
      }
      if (ocrFuel != null && ocrFuel.isNotEmpty &&
          ocrFuel != (inspection.fuelType?.trim() ?? '')) {
        parentUpdates['fuelType'] = ocrFuel;
        diffs.add(_FieldDiff('Fuel', inspection.fuelType ?? '—', ocrFuel));
      }
    }

    // ---- 0b. Mismatch confirm gate ----
    // Only pop the modal when something is actually different — a
    // clean OCR that matches the booking continues straight through.
    if (diffs.isNotEmpty) {
      final accepted = await _confirmMismatch(diffs);
      if (!mounted) return;
      if (accepted != true) return;
    }

    // ---- 1. Upload photo to S3 ----
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

    // ---- 2. Mark step completed on the backend ----
    if (!mounted) return;
    setState(() => _phase = _Phase.saving);
    try {
      final updatesPayload = parentUpdates.isEmpty ? null : parentUpdates;

      await _service.updateStep(
        widget.inspectionId,
        _stepId,
        mediaUrls: [mediaUrl],
        data: result.toBackendData(),
        aiAnalysis: {
          'quality': result.quality.name,
          'qualityReasonDisplay': result.qualityReasonDisplay,
          'qualityReasonSpoken': result.qualityReasonSpoken,
        },
        status: 'completed',
        parentUpdates: updatesPayload,
      );

      // Refresh /inspections so the home card and the AppBar title +
      // computed subtitle (year/fuel/km) both pick up the reconciled
      // values on the next render.
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
    // Refresh the step rows cache so a back-nav to this step shows the
    // persisted view rather than re-running the camera.
    unawaited(ref.read(stepRowsProvider(widget.inspectionId).notifier).refresh());
    widget.onAdvance();
  }

  /// User tapped "Redo this step" from the persisted view. Goes through
  /// the existing per-step retry mechanism, which bumps stepAttempt and
  /// remounts the step widget fresh into capture mode.
  void _redo() {
    ref.read(inspectionFlowProvider(widget.inspectionId).notifier).retry();
  }

  /// RC's `manufacturingDate` comes back from OCR as either "YYYY-MM-DD"
  /// or "YYYY-MM" (only month + year were printed). We only need the
  /// year for the parent's [yearOfMake]; anything else (including a
  /// non-numeric prefix) collapses to null.
  static int? _yearFromIsoDate(String? iso) {
    if (iso == null || iso.length < 4) return null;
    return int.tryParse(iso.substring(0, 4));
  }

  /// Modal confirm gate: lists the booking → RC value diffs in a
  /// side-by-side row, asks the jockey to accept or cancel. Cancel
  /// leaves them on the result card so they can re-take if the wrong
  /// RC card was photographed; confirm proceeds with upload + save +
  /// parentUpdate.
  Future<bool?> _confirmMismatch(List<_FieldDiff> diffs) {
    final t = ref.read(translationsProvider);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
        actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        title: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: AppColors.warning, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(t.carDetailsDiffer,
                  style: t.style(const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 17))),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.useRcValuesBody,
              style: t.style(const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.4,
              )),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (final d in diffs) ...[
                    if (d != diffs.first) const Divider(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 78,
                          child: Text(d.label,
                              style: AppTextStyles.caption.copyWith(
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w600,
                              )),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                d.bookingValue,
                                style: AppTextStyles.body.copyWith(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: AppColors.textHint,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  const Icon(Icons.arrow_forward_rounded,
                                      size: 12, color: AppColors.success),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      d.rcValue,
                                      style: AppTextStyles.body.copyWith(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.success,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.cancel,
                style: t.style(AppTextStyles.button)
                    .copyWith(color: AppColors.primary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
            child: Text(t.useRcValues,
                style: t.style(AppTextStyles.button)),
          ),
        ],
      ),
    );
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
          _CardFrame(
            image: _image,
            // Only used in the persisted phase; ignored when the user
            // is in fresh-capture mode (where _image takes over).
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
          // The assistant speaks via the shell-level bubble now —
          // this step only renders the structured details card on
          // success. Bad-quality / error state is conveyed entirely
          // through the bubble's text + audio.
          if (_result != null && _result!.isUsable)
            _ResultCard(result: _result!, t: t),
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

/// RC-card-shaped viewport. Shows (in priority order): captured photo →
/// persisted S3 photo (revisit) → busy overlay → permission-denied →
/// live preview → loading spinner.
class _CardFrame extends StatelessWidget {
  final File? image;
  final String? imageUrl;
  final CameraController? camera;
  final bool cameraReady;
  final bool permissionDenied;
  final String? cameraError;
  final String? overlayLabel;
  final VoidCallback onRetryPermission;

  const _CardFrame({
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
      aspectRatio: _rcCardAspectRatio,
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
              // Card-shaped guide outline — helps the user line up the RC.
              // Skip when any image (fresh or persisted) is showing.
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
      // Persisted photo from S3. Show a spinner while fetching, and a
      // small error icon if the URL fails (rare — the bucket prefix is
      // public-read for inspections/*).
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
    // CameraPreview returns the sensor's native aspect ratio — wrap in a
    // FittedBox so it fills the card-shaped frame (cropped, not stretched).
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

/// Dashed inner border that mimics the shape of an RC card to give the user
/// a visual target for alignment.
class _AlignmentGuide extends StatelessWidget {
  const _AlignmentGuide();
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.92,
          heightFactor: 0.86,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.85),
                width: 2,
              ),
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
            const SizedBox(
                height: 36, width: 36, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
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
        const Icon(Icons.no_photography_rounded, size: 40, color: AppColors.textSecondary),
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

/// Structured details card — appears on success below the shell-level
/// assistant bubble. Shows the OCR'd fields for at-a-glance verification.
class _ResultCard extends StatelessWidget {
  final RcAnalysisResult result;
  final Translations t;
  const _ResultCard({required this.result, required this.t});

  @override
  Widget build(BuildContext context) {
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
            Text('RC details extracted',
                style: AppTextStyles.heading3.copyWith(color: AppColors.success)),
          ]),
          const SizedBox(height: 14),
          _row('Registration', result.registrationNumber),
          _row('Owner', result.ownerName),
          _row('Vehicle',
              [result.make, result.model].whereType<String>().join(' ')),
          _row('Colour', result.colour),
          _row('Fuel', result.fuelType),
          _row('Manufactured', result.manufacturingDate),
          _row('Registered', result.registrationDate),
          _row('Chassis', result.chassisNumber),
          _row('Engine', result.engineNumber),
        ],
      ),
    );
  }

  Widget _row(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 100, child: Text(label, style: AppTextStyles.caption)),
          Expanded(
            child: Text(value,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
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
    // Revisit of an already-completed step. Two actions: jump back into
    // capture (Redo) or move forward (Next).
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

/// One row in the RC-vs-booking mismatch confirm dialog. Both values
/// are pre-formatted for display ("—" placeholder when the booking
/// field was empty). Top-level class so the dialog method and the
/// builder can share the type.
class _FieldDiff {
  final String label;
  final String bookingValue;
  final String rcValue;
  const _FieldDiff(this.label, this.bookingValue, this.rcValue);
}

