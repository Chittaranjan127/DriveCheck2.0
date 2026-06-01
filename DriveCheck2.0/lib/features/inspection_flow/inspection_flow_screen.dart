import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/i18n/translations.dart';
import '../../core/models/inspection.dart';
import '../../core/models/inspection_step.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../home/inspections_provider.dart';
import '../../core/services/tts_service.dart';
import 'inspection_flow_provider.dart';
import 'state/assistant_utterance_provider.dart';
import 'state/step_rows_provider.dart';
import 'steps/arrival_step.dart';
import 'steps/engine_sound_step.dart';
import 'steps/instrument_cluster_step.dart';
import 'steps/placeholder_step.dart';
import 'steps/rc_document_step.dart';
import 'steps/simple_photo_step.dart';
import 'steps/test_drive_step.dart';
import 'steps/tyres_step.dart';
import 'widgets/assistant_bottom_bar.dart';
import 'widgets/step_example_dialog.dart';
import 'widgets/step_progress_bar.dart';

/// Inspection flow shell. Hosts every step + progress + voice strip.
class InspectionFlowScreen extends ConsumerStatefulWidget {
  final String inspectionId;
  const InspectionFlowScreen({super.key, required this.inspectionId});

  @override
  ConsumerState<InspectionFlowScreen> createState() => _InspectionFlowScreenState();
}

class _InspectionFlowScreenState extends ConsumerState<InspectionFlowScreen> {
  String get inspectionId => widget.inspectionId;

  /// Step ids that have already shown their auto-closing
  /// [StepExampleDialog] this session. Re-entering the flow on a
  /// later run won't replay the modals — feels noisy. Cleared when
  /// the shell is disposed.
  final Set<String> _examplesShown = <String>{};

  @override
  void dispose() {
    // Stop any in-flight TTS and clear the floating assistant bubble so
    // it doesn't persist visually or audibly after we leave the flow.
    // Covers both the explicit exit dialog and OS back / deep links.
    unawaited(TtsService.instance.stop());
    // ref may already be invalidated when we're being torn down by a
    // `context.go(...)` (e.g. test-drive save → /inspection/:id/report
    // tears the flow shell down in the same frame as the navigator
    // pushes the new route). Swallow the "ref after dispose" throw —
    // the bubble's transient state is moot once we're gone.
    try {
      ref.read(assistantUtteranceProvider.notifier).clear();
    } catch (_) {/* ignore */}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final t = ref.watch(translationsProvider);
    final inspections = ref.watch(inspectionsProvider);
    final inspection = inspections.firstWhere((i) => i.id == inspectionId);
    final state = ref.watch(inspectionFlowProvider(inspectionId));
    final notifier = ref.read(inspectionFlowProvider(inspectionId).notifier);
    final step = state.currentStep;
    final title = _t(t, step.titleKey);
    final instruction = _t(t, step.instructionKey);

    final isFirstStep = state.currentStepIndex == 0;

    // First time we land on each step (per shell session) pop the
    // auto-dismissing example modal so the jockey knows what a good
    // capture looks like. Skip:
    //   - arrival: tap-to-confirm screen, no subject to show
    //   - audio (engine_sound): instructions are auditory, the
    //     in-step countdown UI is self-explanatory
    //   - voiceQA (test_drive): hands-free conversational drive,
    //     spoken intro covers what's expected
    //   - already-completed steps (the jockey is revisiting to view
    //     the saved capture; an "example" pop-up is just noise)
    final savedRows = ref.watch(stepRowsProvider(inspectionId)).valueOrNull;
    final isAlreadySubmitted = savedRows
            ?.where((r) => r.stepId == step.id)
            .firstOrNull
            ?.isCompleted ==
        true;
    if (step.type != StepType.arrival &&
        step.type != StepType.audio &&
        step.type != StepType.voiceQA &&
        !isAlreadySubmitted &&
        !_examplesShown.contains(step.id)) {
      _examplesShown.add(step.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        StepExampleDialog.show(
          context,
          step: step,
          t: t,
          title: title,
          instruction: instruction,
        );
      });
    } else if (isAlreadySubmitted) {
      // Stash it so a forward + back nav within the same session
      // doesn't accidentally re-pop the modal if the saved-rows
      // cache turns over while we're here.
      _examplesShown.add(step.id);
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          // First step exits the inspection (with confirm); later steps go
          // back one step. The arrow is a small, neutral icon so it doesn't
          // compete visually with the primary step CTA.
          icon: Icon(isFirstStep ? Icons.close_rounded : Icons.arrow_back_rounded),
          onPressed: isFirstStep
              ? () => _confirmExit(context, t)
              : notifier.back,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(inspection.carTitle, style: AppTextStyles.heading3.copyWith(fontSize: 15)),
            if (inspection.subtitle.isNotEmpty)
              Text(inspection.subtitle, style: AppTextStyles.caption),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Retry this step',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: notifier.retry,
          ),
        ],
      ),
      body: SafeArea(
        // Column instead of a Stack so the AI bar sits BELOW the step
        // body — never overlapping the product view (camera frame /
        // captured photo / verdict cards). The bar collapses to
        // zero-height when there's no active utterance, so step CTAs
        // get the full bottom strip back when the AI is silent.
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    StepProgressBar(currentStep: state.currentStepIndex + 1, totalSteps: state.totalSteps, t: t),
                    const SizedBox(height: 14),
                    // Step title — tells the user what photo/audio this
                    // step is asking for. Sits between the progress bar
                    // and the camera frame so it's visible the moment
                    // they land on the step.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: t.style(AppTextStyles.heading2).copyWith(
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              color: AppColors.textPrimary,
                            ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      // Key includes stepAttempt so the Retry button (which bumps
                      // attempt) rebuilds the step widget from scratch.
                      child: KeyedSubtree(
                        key: ValueKey('${step.id}-${state.stepAttempt}'),
                        child: _stepBody(step, title, instruction, inspection, t, notifier),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Apple-Intelligence-style AI bar — full-width capsule
            // with an animated rainbow border. Steps push intros +
            // verdict messages into `assistantUtteranceProvider`;
            // this widget surfaces them.
            const AssistantBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _stepBody(InspectionStep step, String title, String instruction, Inspection inspection, Translations t, InspectionFlowNotifier notifier) {
    if (step.type == StepType.arrival) {
      return ArrivalStep(
        inspectionId: inspectionId,
        customerArea: inspection.area,
        address: inspection.address,
        latitude: inspection.latitude,
        longitude: inspection.longitude,
        onArrived: notifier.next,
      );
    }
    if (step.id == 'rc_document') {
      return RcDocumentStep(inspectionId: inspectionId, onAdvance: notifier.next);
    }
    if (step.id == 'instrument_cluster') {
      return InstrumentClusterStep(
        inspectionId: inspectionId,
        onAdvance: notifier.next,
      );
    }
    if (step.id == 'tyres') {
      return TyresStep(inspectionId: inspectionId, onAdvance: notifier.next);
    }
    if (step.id == 'engine_sound') {
      return EngineSoundStep(
        inspectionId: inspectionId,
        onAdvance: notifier.next,
      );
    }
    if (step.id == 'test_drive') {
      return TestDriveStep(
        inspectionId: inspectionId,
        onAdvance: notifier.next,
      );
    }
    // Freeform single-photo exterior / interior shots — all share the
    // SimplePhotoStep capture-upload-persist pipeline. Sides + roof use
    // a wider 16:9 frame; everything else defaults to 4:3 landscape.
    if (step.type == StepType.photo) {
      const wideRatio = 16 / 9;
      const standardRatio = 4 / 3;
      final aspect = switch (step.id) {
        'lhs_full' || 'rhs_full' || 'roof' => wideRatio,
        _ => standardRatio,
      };
      return SimplePhotoStep(
        inspectionId: inspectionId,
        stepId: step.id,
        aspectRatio: aspect,
        onAdvance: notifier.next,
      );
    }
    return PlaceholderStep(
      step: step,
      title: title,
      instruction: instruction,
      onAdvance: notifier.next,
    );
  }

  Future<void> _confirmExit(BuildContext context, Translations t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(t.exitInspectionTitle, style: t.style(AppTextStyles.heading3)),
        content: Text(t.exitInspectionBody, style: t.style(AppTextStyles.body)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.exit, style: AppTextStyles.button.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) context.go('/home');
  }

  String _t(Translations t, String key) {
    switch (key) {
      case 'stepArrivalTitle':       return t.stepArrivalTitle;
      case 'stepArrivalInstruction': return t.stepArrivalInstruction;
      case 'stepRcTitle':            return t.stepRcTitle;
      case 'stepRcInstruction':      return t.stepRcInstruction;
      case 'stepClusterTitle':       return t.stepClusterTitle;
      case 'stepClusterInstruction': return t.stepClusterInstruction;
      case 'stepEngineBayTitle':     return t.stepEngineBayTitle;
      case 'stepEngineBayInstruction': return t.stepEngineBayInstruction;
      case 'stepFrontTitle':         return t.stepFrontTitle;
      case 'stepFrontInstruction':   return t.stepFrontInstruction;
      case 'stepLeftTitle':          return t.stepLeftTitle;
      case 'stepLeftInstruction':    return t.stepLeftInstruction;
      case 'stepRightTitle':         return t.stepRightTitle;
      case 'stepRightInstruction':   return t.stepRightInstruction;
      case 'stepRearTitle':          return t.stepRearTitle;
      case 'stepRearInstruction':    return t.stepRearInstruction;
      case 'stepRoofTitle':          return t.stepRoofTitle;
      case 'stepRoofInstruction':    return t.stepRoofInstruction;
      case 'stepInteriorTitle':      return t.stepInteriorTitle;
      case 'stepInteriorInstruction':return t.stepInteriorInstruction;
      case 'stepTyresTitle':         return t.stepTyresTitle;
      case 'stepTyresInstruction':   return t.stepTyresInstruction;
      case 'stepEngineSoundTitle':   return t.stepEngineSoundTitle;
      case 'stepEngineSoundInstruction': return t.stepEngineSoundInstruction;
      case 'stepTestDriveTitle':     return t.stepTestDriveTitle;
      case 'stepTestDriveInstruction': return t.stepTestDriveInstruction;
      default: return key;
    }
  }
}
