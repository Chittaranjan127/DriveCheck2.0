import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/inspection_step_row.dart';
import '../../../core/services/inspections_service.dart';

/// Fetches the InspectionSteps rows for one inspection (one round-trip
/// to `GET /inspections/{id}/steps`). Steps watch this provider to know
/// whether they've already been completed on the backend; if so the step
/// screen renders the saved media + extracted data instead of the empty
/// capture viewport.
///
/// [refresh] is called by a step after it writes new data so a back-nav
/// to that step picks up the just-saved state.
class StepRowsNotifier extends FamilyAsyncNotifier<List<InspectionStepRow>, String> {
  @override
  Future<List<InspectionStepRow>> build(String inspectionId) async {
    try {
      return await InspectionsService().listSteps(inspectionId);
    } catch (e) {
      debugPrint('[steps] fetch failed for $inspectionId: $e');
      rethrow;
    }
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }
}

final stepRowsProvider = AsyncNotifierProvider
    .family<StepRowsNotifier, List<InspectionStepRow>, String>(
        StepRowsNotifier.new);
