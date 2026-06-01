import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/translations.dart';
import '../../core/services/audio_prompt_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/language_service.dart';
import '../../core/services/uploads_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../shared/widgets/primary_button.dart';
import '../auth/auth_provider.dart';
import 'profile_strings.dart';

/// Step 2 of profile completion. Asks for camera permission on entry, shows
/// a live front-camera preview, captures on tap of the shutter, then offers
/// confirm/retake. Confirm uploads to /uploads/selfie and PATCHes /auth/me.
class ProfileSetupSelfieScreen extends ConsumerStatefulWidget {
  const ProfileSetupSelfieScreen({super.key});

  @override
  ConsumerState<ProfileSetupSelfieScreen> createState() => _ProfileSetupSelfieScreenState();
}

class _ProfileSetupSelfieScreenState extends ConsumerState<ProfileSetupSelfieScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  Future<void>? _initFuture;
  bool _permissionDenied = false;
  String? _error;

  File? _photo;
  bool _isCapturing = false;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootCamera();
    WidgetsBinding.instance.addPostFrameCallback((_) => _playPrompt());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AudioPromptService.instance.stop();
    _camera?.dispose();
    super.dispose();
  }

  /// Pause/resume the preview when the app is backgrounded — required by the
  /// `camera` package, otherwise the texture freezes when returning.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;
    if (s == AppLifecycleState.inactive || s == AppLifecycleState.paused) {
      cam.dispose();
      _camera = null;
    } else if (s == AppLifecycleState.resumed) {
      _bootCamera();
    }
  }

  AppLanguage get _lang =>
      ref.read(languageProvider).valueOrNull ?? AppLanguage.hindi;

  Future<void> _playPrompt() =>
      AudioPromptService.instance.play(PromptIds.takeSelfie, _lang);

  Future<void> _bootCamera() async {
    setState(() {
      _permissionDenied = false;
      _error = null;
    });
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _error = 'No camera available');
        return;
      }
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      _camera = controller;
      _initFuture = controller.initialize();
      await _initFuture;
      if (!mounted) return;
      setState(() {});
    } on CameraException catch (e) {
      // CameraAccessDenied is what gets thrown when the user (or settings)
      // refuses the permission prompt the package raises on initialize().
      if (e.code == 'CameraAccessDenied' || e.code == 'CameraAccessRestricted') {
        setState(() => _permissionDenied = true);
      } else {
        setState(() => _error = e.description ?? e.code);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    }
  }

  Future<void> _capture() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized || _isCapturing) return;
    setState(() {
      _isCapturing = true;
      _error = null;
    });
    try {
      final shot = await cam.takePicture();
      if (!mounted) return;
      setState(() {
        _photo = File(shot.path);
        _isCapturing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _error = e.toString();
      });
    }
  }

  void _retake() {
    setState(() {
      _photo = null;
      _error = null;
    });
  }

  Future<void> _confirm() async {
    if (_photo == null) return;
    setState(() {
      _isUploading = true;
      _error = null;
    });
    try {
      final url = await UploadsService().uploadSelfie(_photo!);
      await AuthService().updateMe(selfieUrl: url);
      await ref.read(authProvider.notifier).refreshMe();
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUploading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ProfileStrings.of(_lang);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.background,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/profile/setup/name'),
        ),
        actions: [
          TextButton.icon(
            onPressed: _playPrompt,
            icon: const Icon(Icons.volume_up_rounded, color: AppColors.primary),
            label: Text(s.replay,
                style: AppTextStyles.body.copyWith(color: AppColors.primary)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _StepDots(current: 2, total: 2),
              const SizedBox(height: 28),
              Text(s.takeSelfie, style: AppTextStyles.heading1),
              const SizedBox(height: 8),
              Text(s.selfieHint,
                  style: AppTextStyles.body.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 24),
              Expanded(
                child: Center(child: _viewport()),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(color: AppColors.error)),
              ],
              const SizedBox(height: 16),
              _controls(s),
            ],
          ),
        ),
      ),
    );
  }

  Widget _viewport() {
    if (_permissionDenied) {
      return _PermissionBlocked(onRetry: _bootCamera);
    }
    if (_photo != null) {
      return _CircleFrame(child: Image.file(_photo!, fit: BoxFit.cover));
    }
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) {
      return const _CircleFrame(child: Center(child: CircularProgressIndicator()));
    }
    // Front-camera previews come in mirrored by default on most platforms.
    // Flipping horizontally matches the visual the user expects from a mirror.
    return _CircleFrame(
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1.0, 1.0, 1.0),
        child: CameraPreview(cam),
      ),
    );
  }

  Widget _controls(ProfileStrings s) {
    if (_permissionDenied) return const SizedBox.shrink();

    if (_photo == null) {
      // Shutter button — capture
      return Center(
        child: GestureDetector(
          onTap: _isCapturing ? null : _capture,
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
            child: _isCapturing
                ? const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: AppColors.onPrimary,
                    ),
                  )
                : const Icon(Icons.camera_alt_rounded,
                    color: AppColors.onPrimary, size: 32),
          ),
        ),
      );
    }

    // Captured — confirm or retry
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isUploading ? null : _retake,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(s.retake, style: AppTextStyles.button),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              side: const BorderSide(color: AppColors.border),
              foregroundColor: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: PrimaryButton(
            label: _isUploading ? s.uploading : s.useThisPhoto,
            isLoading: _isUploading,
            onPressed: _confirm,
            trailingIcon: Icons.check_rounded,
          ),
        ),
      ],
    );
  }
}

class _CircleFrame extends StatelessWidget {
  final Widget child;
  const _CircleFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      height: 260,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surfaceMuted,
        border: Border.all(color: AppColors.border, width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
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
            size: 48, color: AppColors.textSecondary),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            t.cameraAccessNeeded,
            textAlign: TextAlign.center,
            style: t.style(AppTextStyles.body),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(onPressed: onRetry,
            child: Text(t.tryAgain,
                style: t.style(AppTextStyles.button)
                    .copyWith(color: AppColors.primary))),
      ],
    );
  }
}

class _StepDots extends StatelessWidget {
  final int current;
  final int total;
  const _StepDots({required this.current, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final active = i < current;
        return Container(
          width: 28, height: 4,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}
