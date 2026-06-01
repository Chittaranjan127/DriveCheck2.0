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

/// Step 11: tyres. Multi-photo capture — one shot per wheel (FL, FR,
/// RL, RR). Each tyre is uploaded individually so progress survives a
/// back-out partway through; the step row only flips to `completed`
/// once all four positions are filled.
///
/// Position → URL mapping is stored on the InspectionSteps row under
/// `data.tyres.{position}` so a revisit knows which URL belongs to
/// which wheel (the flat `mediaUrls` list alone wouldn't tell us).
class TyresStep extends ConsumerStatefulWidget {
  final String inspectionId;
  final VoidCallback onAdvance;

  const TyresStep({
    super.key,
    required this.inspectionId,
    required this.onAdvance,
  });

  @override
  ConsumerState<TyresStep> createState() => _TyresStepState();
}

/// Wheel positions in the order they appear in the 2×2 grid.
enum TyrePosition {
  frontLeft,
  frontRight,
  rearLeft,
  rearRight;

  /// Backend storage key — kept as the enum name so JSON round-trips
  /// without a parsing table.
  String get key => name;
}

/// Capture-mode sub-state — distinguishes "shooting", "AI-checking",
/// "AI rejected, retake", and "AI approved, awaiting Use-this-photo".
enum _Capture { idle, analyzing, badQuality, readyToConfirm }

enum _Mode { overview, capturing }

class _TyresStepState extends ConsumerState<TyresStep>
    with WidgetsBindingObserver {
  static const _stepId = 'tyres';

  CameraController? _camera;
  bool _cameraReady = false;
  bool _permissionDenied = false;
  String? _cameraError;

  // Per-position state. _uploaded survives across the session and is
  // the source of truth for "is this tyre done?". _captured holds the
  // local-only file between capture and confirm. _qualityByPos
  // carries the AI verdict for each wheel — populated as captures
  // happen AND when hydrating from a revisit.
  final Map<TyrePosition, String?> _uploaded = {};
  final Map<TyrePosition, PhotoQualityResult> _qualityByPos = {};
  File? _capturedFile;
  TyrePosition? _activePosition;
  PhotoQualityResult? _quality;

  _Mode _mode = _Mode.overview;
  _Capture _capturePhase = _Capture.idle;
  bool _isCapturing = false;
  bool _isUploading = false;
  String? _error;

  final _service = InspectionsService();
  final _analyzer = PhotoQualityAnalyzer();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hydrateFromSaved();
    // Always push the intro to the shell bubble; silent if every tyre
    // is already saved (back-nav to a completed step).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lang = ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;
      final t = ref.read(translationsProvider);
      final intro = stepIntroFor(_stepId, lang, t: t);
      ref.read(assistantUtteranceProvider.notifier).say(
            intro.spokenSsml,
            display: intro.display,
            autoplay: !_isAllDone,
          );
    });
  }

  bool get _isAllDone =>
      TyrePosition.values.every((p) => _uploaded[p] != null);

  /// Pull any per-position URLs the backend already has for this step.
  /// Partial state is fine — missing wheels are left blank for the
  /// jockey to capture. Also rehydrates per-position AI verdicts from
  /// the `aiAnalysis.tyres` map so revisits can show the same chip
  /// the jockey saw at capture time, no second OpenAI call needed.
  void _hydrateFromSaved() {
    final attempt =
        ref.read(inspectionFlowProvider(widget.inspectionId)).stepAttempt;
    if (attempt != 0) return; // user tapped Retry — wipe and start fresh
    final rows = ref.read(stepRowsProvider(widget.inspectionId)).valueOrNull;
    if (rows == null) return;
    final row = rows.where((r) => r.stepId == _stepId).firstOrNull;
    if (row == null) return;
    final tyres = (row.data['tyres'] as Map?)?.cast<String, dynamic>();
    if (tyres != null) {
      for (final p in TyrePosition.values) {
        final url = tyres[p.key];
        if (url is String && url.isNotEmpty) {
          _uploaded[p] = url;
        }
      }
    }
    final aiTyres = (row.aiAnalysis?['tyres'] as Map?)?.cast<String, dynamic>();
    if (aiTyres != null) {
      for (final p in TyrePosition.values) {
        final entry = aiTyres[p.key];
        if (entry is Map) {
          try {
            _qualityByPos[p] =
                PhotoQualityResult.fromJson(entry.cast<String, dynamic>());
          } catch (_) {/* shape drift — skip */}
        }
      }
    }
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
    } else if (s == AppLifecycleState.resumed &&
        _mode == _Mode.capturing &&
        _capturedFile == null) {
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

  void _startCapture(TyrePosition pos) {
    setState(() {
      _activePosition = pos;
      _capturedFile = null;
      _quality = null;
      _capturePhase = _Capture.idle;
      _mode = _Mode.capturing;
      _error = null;
    });
    _bootCamera();
  }

  void _exitCapture() {
    setState(() {
      _mode = _Mode.overview;
      _activePosition = null;
      _capturedFile = null;
      _quality = null;
      _capturePhase = _Capture.idle;
      _isUploading = false;
    });
    _camera?.dispose();
    _camera = null;
    _cameraReady = false;
  }

  Future<void> _capture() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final shot = await cam.takePicture();
      final cropped = await _cropSquare(File(shot.path));
      if (!mounted) return;
      setState(() {
        _capturedFile = cropped;
        _quality = null;
        _isCapturing = false;
        _capturePhase = _Capture.analyzing;
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

  /// Per-tyre AI check. Mirrors SimplePhotoStep: if the model flags the
  /// photo as blurry / wrong-subject, the spoken reason goes through
  /// the shell-level assistant bubble and the user is forced to retake.
  Future<void> _runQualityCheck() async {
    final image = _capturedFile;
    if (image == null) return;
    final subject = StepPhotoSubjects.forStep('tyre');
    if (subject == null) {
      // Should never happen — 'tyre' is in the subjects table — but
      // degrade gracefully rather than locking the user out.
      setState(() => _capturePhase = _Capture.readyToConfirm);
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
        _capturePhase = _Capture.badQuality;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _quality = result);

    if (!result.isUsable) {
      setState(() => _capturePhase = _Capture.badQuality);
      final spoken = result.qualityReasonSpoken;
      if (spoken != null && spoken.trim().isNotEmpty) {
        ref.read(assistantUtteranceProvider.notifier)
            .say(spoken, display: result.qualityReasonDisplay);
      }
      return;
    }
    setState(() => _capturePhase = _Capture.readyToConfirm);
    final spoken = result.successMessageSpoken;
    if (spoken != null && spoken.trim().isNotEmpty) {
      ref.read(assistantUtteranceProvider.notifier)
          .say(spoken, display: result.successMessageDisplay);
    }
  }

  /// Centre-crop to 1:1 so the saved tyre photo matches the square
  /// thumbnail shown in the overview grid.
  Future<File> _cropSquare(File source) async {
    final bytes = await source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return source;

    final upright = img.bakeOrientation(decoded);
    final w = upright.width;
    final h = upright.height;
    final side = w < h ? w : h;
    final x = ((w - side) / 2).round();
    final y = ((h - side) / 2).round();

    final cropped = img.copyCrop(upright, x: x, y: y, width: side, height: side);
    final outBytes = img.encodeJpg(cropped, quality: 85);

    final tmpDir = await getTemporaryDirectory();
    final outFile = File(
        '${tmpDir.path}/tyre_${_activePosition?.key}_${DateTime.now().millisecondsSinceEpoch}.jpg');
    await outFile.writeAsBytes(outBytes, flush: true);
    return outFile;
  }

  void _retakeTyre() {
    setState(() {
      _capturedFile = null;
      _quality = null;
      _capturePhase = _Capture.idle;
      _error = null;
    });
  }

  /// Upload this tyre's photo + persist the partial state to the backend.
  /// Flips the step to `completed` if this is the 4th tyre, advances the
  /// inspection. Otherwise returns to the overview grid so the user can
  /// pick the next wheel.
  Future<void> _saveActiveTyre() async {
    final pos = _activePosition;
    final file = _capturedFile;
    if (pos == null || file == null) return;

    setState(() {
      _isUploading = true;
      _error = null;
    });

    String url;
    try {
      final bytes = await file.readAsBytes();
      url = await _service.uploadStepMedia(
        widget.inspectionId,
        _stepId,
        bytes,
        mimeType: 'image/jpeg',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _error = 'Upload failed: $e';
      });
      return;
    }

    _uploaded[pos] = url;
    if (_quality != null) {
      // Stash the AI verdict per position so the overview tile gets
      // its colour-coded chip without re-fetching from the backend.
      _qualityByPos[pos] = _quality!;
    }
    final allDone = _isAllDone;

    try {
      final orderedUrls = TyrePosition.values
          .map((p) => _uploaded[p])
          .whereType<String>()
          .toList();
      final tyresMap = <String, String>{
        for (final p in TyrePosition.values)
          if (_uploaded[p] != null) p.key: _uploaded[p]!,
      };
      // Stash the AI verdict per position so the persisted view can
      // surface "Front-left tyre: cluster's already flagged this one
      // as low-tread" later without re-calling the model.
      final qualityMap = <String, dynamic>{
        ...(((ref.read(stepRowsProvider(widget.inspectionId))
                        .valueOrNull
                        ?.where((r) => r.stepId == _stepId)
                        .firstOrNull
                        ?.aiAnalysis?['tyres'] as Map?) ??
                    const {})
                .cast<String, dynamic>()),
        if (_quality != null) pos.key: _quality!.toAiAnalysis(),
      };
      await _service.updateStep(
        widget.inspectionId,
        _stepId,
        mediaUrls: orderedUrls,
        data: {'tyres': tyresMap},
        aiAnalysis: {'tyres': qualityMap},
        status: allDone ? 'completed' : null,
      );
    } catch (e) {
      // Roll back the in-memory upload so the user can retry without
      // ending up with a server/client mismatch.
      _uploaded.remove(pos);
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _error = 'Save failed: $e';
      });
      return;
    }

    if (!mounted) return;
    unawaited(ref.read(stepRowsProvider(widget.inspectionId).notifier).refresh());

    if (allDone) {
      widget.onAdvance();
      return;
    }
    _exitCapture(); // back to grid
  }

  void _redoAll() {
    // User wants to start over — wipe local state and bump retry so
    // hydration doesn't restore the old URLs on the next mount.
    setState(() {
      _uploaded.clear();
      _capturedFile = null;
      _activePosition = null;
      _mode = _Mode.overview;
    });
    ref.read(inspectionFlowProvider(widget.inspectionId).notifier).retry();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    if (_mode == _Mode.capturing) {
      return _CaptureView(
        t: t,
        position: _activePosition!,
        capturedFile: _capturedFile,
        capturePhase: _capturePhase,
        camera: _camera,
        cameraReady: _cameraReady,
        permissionDenied: _permissionDenied,
        cameraError: _cameraError,
        isCapturing: _isCapturing,
        isUploading: _isUploading,
        error: _error,
        onShutter: _capture,
        onRetake: _retakeTyre,
        onUse: _saveActiveTyre,
        onCancel: _exitCapture,
        onRetryPermission: _bootCamera,
      );
    }
    return _OverviewView(
      t: t,
      uploaded: _uploaded,
      qualityByPos: _qualityByPos,
      allDone: _isAllDone,
      onTileTap: _startCapture,
      onNext: widget.onAdvance,
      onRedoAll: _redoAll,
    );
  }
}

// ---- Overview: 2×2 grid of tyre tiles + bottom action row ----

class _OverviewView extends StatelessWidget {
  final Translations t;
  final Map<TyrePosition, String?> uploaded;
  final Map<TyrePosition, PhotoQualityResult> qualityByPos;
  final bool allDone;
  final void Function(TyrePosition) onTileTap;
  final VoidCallback onNext;
  final VoidCallback onRedoAll;

  const _OverviewView({
    required this.t,
    required this.uploaded,
    required this.qualityByPos,
    required this.allDone,
    required this.onTileTap,
    required this.onNext,
    required this.onRedoAll,
  });

  @override
  Widget build(BuildContext context) {
    final doneCount = uploaded.values.whereType<String>().length;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Progress chip — quick "3 of 4 done" glance.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: allDone
                  ? AppColors.success.withValues(alpha: 0.12)
                  : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: allDone
                    ? AppColors.success.withValues(alpha: 0.4)
                    : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  allDone
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 18,
                  color: allDone ? AppColors.success : AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  '$doneCount / 4',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: allDone ? AppColors.success : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: TyrePosition.values
                .map((p) => _TyreTile(
                      position: p,
                      label: _label(p, t),
                      imageUrl: uploaded[p],
                      quality: qualityByPos[p],
                      onTap: () => onTileTap(p),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),
          if (allDone) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onRedoAll,
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
                    onPressed: onNext,
                    icon: const Icon(Icons.arrow_forward_rounded, color: AppColors.onCtaDark),
                    label: Text(t.next, style: AppTextStyles.button),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Localised tyre position labels. Kept in-step rather than a global
  /// translations key because they're only used here.
  String _label(TyrePosition p, Translations t) {
    switch (t.language) {
      case AppLanguage.english:
        return switch (p) {
          TyrePosition.frontLeft  => 'Front left',
          TyrePosition.frontRight => 'Front right',
          TyrePosition.rearLeft   => 'Rear left',
          TyrePosition.rearRight  => 'Rear right',
        };
      case AppLanguage.hindi:
        return switch (p) {
          TyrePosition.frontLeft  => 'आगे बायाँ',
          TyrePosition.frontRight => 'आगे दायाँ',
          TyrePosition.rearLeft   => 'पीछे बायाँ',
          TyrePosition.rearRight  => 'पीछे दायाँ',
        };
      case AppLanguage.telugu:
        return switch (p) {
          TyrePosition.frontLeft  => 'ముందు ఎడమ',
          TyrePosition.frontRight => 'ముందు కుడి',
          TyrePosition.rearLeft   => 'వెనుక ఎడమ',
          TyrePosition.rearRight  => 'వెనుక కుడి',
        };
      case AppLanguage.bengali:
        return switch (p) {
          TyrePosition.frontLeft  => 'সামনে বাঁ',
          TyrePosition.frontRight => 'সামনে ডান',
          TyrePosition.rearLeft   => 'পিছনে বাঁ',
          TyrePosition.rearRight  => 'পিছনে ডান',
        };
    }
  }
}

class _TyreTile extends StatelessWidget {
  final TyrePosition position;
  final String label;
  final String? imageUrl;
  final PhotoQualityResult? quality;
  final VoidCallback onTap;

  const _TyreTile({
    required this.position,
    required this.label,
    required this.imageUrl,
    required this.quality,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final filled = imageUrl != null;
    // Border + bottom-right badge mirror the AI's verdict colour when
    // we have one — green for accepted, amber/red for problem flags.
    // Falls back to plain success-green on filled tiles where the
    // verdict didn't make it back (older rows).
    final tone = quality == null
        ? AppColors.success
        : (quality!.isUsable ? AppColors.success : AppColors.error);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: filled ? tone.withValues(alpha: 0.5) : AppColors.border,
            width: filled ? 2 : 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (filled)
                Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image_rounded,
                        size: 32, color: AppColors.textHint),
                  ),
                )
              else
                Center(
                  child: Icon(Icons.add_a_photo_outlined,
                      size: 36, color: AppColors.textHint),
                ),
              // Bottom label gradient — kept readable over a photo OR
              // the empty surface tile.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: filled ? 0.55 : 0.0),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.body.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: filled ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      if (filled)
                        Icon(
                          quality == null || quality!.isUsable
                              ? Icons.check_circle_rounded
                              : Icons.warning_rounded,
                          color: tone,
                          size: 20,
                        ),
                    ],
                  ),
                ),
              ),
              // AI verdict chip — only when we have a problem flag.
              // Accepted photos already get the green check above; the
              // chip is reserved for "look here, the model flagged
              // something". Sits top-left so it doesn't fight the
              // bottom label row.
              if (filled && quality != null && !quality!.isUsable)
                Positioned(
                  left: 6, top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: tone,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _shortQualityLabel(quality!.quality),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Compact label for the corner chip — long-form messages live in
  /// the assistant bubble; the tile just needs a glance-able tag.
  String _shortQualityLabel(PhotoQuality q) {
    switch (q) {
      case PhotoQuality.good:         return 'OK';
      case PhotoQuality.blurry:       return 'Blurry';
      case PhotoQuality.dark:         return 'Dark';
      case PhotoQuality.partial:      return 'Partial';
      case PhotoQuality.wrongSubject: return 'Wrong shot';
      case PhotoQuality.unreadable:   return 'Unclear';
    }
  }
}

// ---- Capture: full-frame preview for one tyre ----

class _CaptureView extends StatelessWidget {
  final Translations t;
  final TyrePosition position;
  final File? capturedFile;
  final _Capture capturePhase;
  final CameraController? camera;
  final bool cameraReady;
  final bool permissionDenied;
  final String? cameraError;
  final bool isCapturing;
  final bool isUploading;
  final String? error;
  final VoidCallback onShutter;
  final VoidCallback onRetake;
  final VoidCallback onUse;
  final VoidCallback onCancel;
  final VoidCallback onRetryPermission;

  const _CaptureView({
    required this.t,
    required this.position,
    required this.capturedFile,
    required this.capturePhase,
    required this.camera,
    required this.cameraReady,
    required this.permissionDenied,
    required this.cameraError,
    required this.isCapturing,
    required this.isUploading,
    required this.error,
    required this.onShutter,
    required this.onRetake,
    required this.onUse,
    required this.onCancel,
    required this.onRetryPermission,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: onCancel,
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                _positionLabel(position, t),
                style: t.style(AppTextStyles.heading3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AspectRatio(
          aspectRatio: 1.0,
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
                  if (capturePhase == _Capture.analyzing)
                    _busyOverlay('Checking photo…'),
                  if (isUploading) _busyOverlay('Uploading…'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (error != null)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Text(error!,
                style: AppTextStyles.body.copyWith(color: AppColors.error)),
          ),
        if (capturedFile == null)
          Center(
            child: GestureDetector(
              onTap: cameraReady && !isCapturing ? onShutter : null,
              child: Opacity(
                opacity: cameraReady && !isCapturing ? 1 : 0.5,
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
                  child: isCapturing
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
          )
        else if (capturePhase == _Capture.analyzing)
          // Spinner / AI overlay is already covering the frame; bottom
          // action row is intentionally empty so the user can't tap
          // anything mid-analysis.
          const SizedBox.shrink()
        else if (capturePhase == _Capture.badQuality)
          // AI rejected the tyre photo — only Retake offered. No
          // "Use this anyway" escape; mirrors SimplePhotoStep.
          SizedBox(
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
          )
        else
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isUploading ? null : onRetake,
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
                  onPressed: isUploading ? null : onUse,
                  icon: const Icon(Icons.check_rounded, color: AppColors.onCtaDark),
                  label: Text(t.useThis,
                      style: t.style(AppTextStyles.button)),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _busyOverlay(String label) => Container(
        color: AppColors.ctaDark.withValues(alpha: 0.55),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                height: 36, width: 36,
                child: CircularProgressIndicator(
                    strokeWidth: 3, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(label,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15)),
            ],
          ),
        ),
      );

  Widget _content() {
    if (capturedFile != null) {
      return Image.file(capturedFile!, fit: BoxFit.cover);
    }
    if (permissionDenied) {
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
          TextButton(onPressed: onRetryPermission,
              child: Text(t.tryAgain,
                  style: t.style(AppTextStyles.button)
                      .copyWith(color: AppColors.primary))),
        ],
      );
    }
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
          width: 36, height: 36,
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

  String _positionLabel(TyrePosition p, Translations t) {
    switch (t.language) {
      case AppLanguage.english:
        return switch (p) {
          TyrePosition.frontLeft  => 'Front left tyre',
          TyrePosition.frontRight => 'Front right tyre',
          TyrePosition.rearLeft   => 'Rear left tyre',
          TyrePosition.rearRight  => 'Rear right tyre',
        };
      case AppLanguage.hindi:
        return switch (p) {
          TyrePosition.frontLeft  => 'आगे का बायाँ टायर',
          TyrePosition.frontRight => 'आगे का दायाँ टायर',
          TyrePosition.rearLeft   => 'पीछे का बायाँ टायर',
          TyrePosition.rearRight  => 'पीछे का दायाँ टायर',
        };
      case AppLanguage.telugu:
        return switch (p) {
          TyrePosition.frontLeft  => 'ముందు ఎడమ టైర్',
          TyrePosition.frontRight => 'ముందు కుడి టైర్',
          TyrePosition.rearLeft   => 'వెనుక ఎడమ టైర్',
          TyrePosition.rearRight  => 'వెనుక కుడి టైర్',
        };
      case AppLanguage.bengali:
        return switch (p) {
          TyrePosition.frontLeft  => 'সামনের বাঁ টায়ার',
          TyrePosition.frontRight => 'সামনের ডান টায়ার',
          TyrePosition.rearLeft   => 'পিছনের বাঁ টায়ার',
          TyrePosition.rearRight  => 'পিছনের ডান টায়ার',
        };
    }
  }
}
