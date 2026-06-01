import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/inspection_steps.dart';
import '../../core/models/inspection_step.dart';
import '../home/inspections_provider.dart';

/// Live state for an inspection in progress.
class InspectionFlowState {
  final String inspectionId;
  final int currentStepIndex;
  final Map<String, dynamic> answers;
  final DateTime? arrivedAt;
  // Incremented every time the user taps Retry on the current step. The
  // flow screen uses (stepIndex, stepAttempt) as the widget key so bumping
  // this rebuilds the step widget from scratch — drops any captured photo,
  // re-inits the camera, clears OCR state, etc. Resets to 0 on every step
  // change (next / back), so each step starts at attempt 0.
  final int stepAttempt;

  const InspectionFlowState({
    required this.inspectionId,
    this.currentStepIndex = 0,
    this.answers = const {},
    this.arrivedAt,
    this.stepAttempt = 0,
  });

  InspectionStep get currentStep => kInspectionSteps[currentStepIndex];
  int get totalSteps => kInspectionSteps.length;
  bool get isLast => currentStepIndex == totalSteps - 1;
  double get progress => (currentStepIndex + 1) / totalSteps;

  InspectionFlowState copyWith({
    int? currentStepIndex,
    Map<String, dynamic>? answers,
    DateTime? arrivedAt,
    int? stepAttempt,
  }) =>
      InspectionFlowState(
        inspectionId: inspectionId,
        currentStepIndex: currentStepIndex ?? this.currentStepIndex,
        answers: answers ?? this.answers,
        arrivedAt: arrivedAt ?? this.arrivedAt,
        stepAttempt: stepAttempt ?? this.stepAttempt,
      );
}

class InspectionFlowNotifier extends FamilyNotifier<InspectionFlowState, String> {
  @override
  InspectionFlowState build(String inspectionId) {
    // Resume at the first non-completed step using the cached inspection's
    // server-side completedStepCount. ref.read (not watch) — we only want
    // to seed once on first build; later refreshes of the inspections list
    // shouldn't yank the user out of whatever step they're currently on.
    final inspection = ref
        .read(inspectionsProvider)
        .where((i) => i.id == inspectionId)
        .firstOrNull;
    final completed = inspection?.completedStepCount ?? 0;
    final resumeIndex = completed.clamp(0, kInspectionSteps.length - 1);

    return InspectionFlowState(
      inspectionId: inspectionId,
      currentStepIndex: resumeIndex,
      // If arrival (step 0) is already complete on the server, mark it
      // arrived locally so the "Yes, I've arrived" button doesn't re-fire
      // the backend write should the user back up to step 1.
      arrivedAt: completed >= 1 ? DateTime.now() : null,
      answers: completed >= 1 ? const {'arrived': true} : const {},
    );
  }

  void next() {
    if (state.isLast) return;
    state = state.copyWith(currentStepIndex: state.currentStepIndex + 1, stepAttempt: 0);
  }

  void back() {
    if (state.currentStepIndex == 0) return;
    state = state.copyWith(currentStepIndex: state.currentStepIndex - 1, stepAttempt: 0);
  }

  /// Force the current step to start over. The flow screen keys each step
  /// widget by (stepIndex, stepAttempt), so bumping stepAttempt rebuilds
  /// the widget from scratch — any local state (captured photo, OCR
  /// result, audio recording, etc.) is dropped. Backend writes that have
  /// already happened stay; subsequent updateStep calls are idempotent at
  /// the row level.
  void retry() {
    state = state.copyWith(stepAttempt: state.stepAttempt + 1);
  }

  void recordAnswer(String key, dynamic value) {
    state = state.copyWith(answers: {...state.answers, key: value});
  }

  void markArrived() {
    state = state.copyWith(arrivedAt: DateTime.now(), answers: {...state.answers, 'arrived': true});
  }
}

final inspectionFlowProvider =
    NotifierProvider.family<InspectionFlowNotifier, InspectionFlowState, String>(
        InspectionFlowNotifier.new);
