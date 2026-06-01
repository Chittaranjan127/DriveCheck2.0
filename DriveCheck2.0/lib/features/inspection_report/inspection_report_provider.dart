import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/inspection_report.dart';
import '../../core/services/inspections_service.dart';

/// Family key for [inspectionReportProvider]. Wrap (inspectionId, lang)
/// so two languages of the same inspection cache independently — if the
/// jockey ever switches language mid-flow we don't show a stale Hindi
/// pitch to an English user.
@immutable
class ReportKey {
  final String inspectionId;
  final String lang;
  const ReportKey(this.inspectionId, this.lang);

  @override
  bool operator ==(Object other) =>
      other is ReportKey &&
      other.inspectionId == inspectionId &&
      other.lang == lang;

  @override
  int get hashCode => Object.hash(inspectionId, lang);
}

/// Cached [InspectionReport] fetch. Backed by
/// `AsyncNotifierProvider.family` (NOT autoDispose) so the report
/// survives screen pop / re-push — we don't want to re-hit the
/// `/inspections/{id}/report` endpoint every time the user revisits,
/// because each call costs a gpt-4o roundtrip on the server side.
///
/// Use [InspectionReportNotifier.refresh] for explicit re-fetches
/// (e.g. a pull-to-refresh control or a "regenerate" button later).
class InspectionReportNotifier
    extends FamilyAsyncNotifier<InspectionReport, ReportKey> {
  @override
  Future<InspectionReport> build(ReportKey key) async {
    return InspectionsService().getReport(key.inspectionId, lang: key.lang);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => build(arg));
  }
}

final inspectionReportProvider = AsyncNotifierProvider
    .family<InspectionReportNotifier, InspectionReport, ReportKey>(
        InspectionReportNotifier.new);
