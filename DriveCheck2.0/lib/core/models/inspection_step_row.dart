/// A row in `DriveCheck-InspectionSteps-{stage}` — the per-inspection
/// per-step state stored on the backend.
///
/// Distinct from [InspectionStep] in `inspection_step.dart`, which is the
/// *definition* (id + type + title) loaded from a local constant; this one
/// is the *state* (status, mediaUrls, jockey notes, AI analysis) fetched
/// over the wire.
enum InspectionStepStatus { pending, inProgress, completed }

class InspectionStepRow {
  final String inspectionId;
  final String stepId;
  final int stepOrder;
  final String stepType;    // "arrival" | "photo" | "multiPhoto" | "audio" | "voiceQA"
  final String section;     // "arrival" | "documents" | "interior" | ...
  final int photoCount;
  final int audioSeconds;
  final InspectionStepStatus status;
  final List<String> mediaUrls;
  final Map<String, dynamic> data;
  final Map<String, dynamic>? aiAnalysis;
  final String notes;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? updatedAt;

  const InspectionStepRow({
    required this.inspectionId,
    required this.stepId,
    required this.stepOrder,
    required this.stepType,
    required this.section,
    this.photoCount = 0,
    this.audioSeconds = 0,
    this.status = InspectionStepStatus.pending,
    this.mediaUrls = const [],
    this.data = const {},
    this.aiAnalysis,
    this.notes = '',
    this.startedAt,
    this.completedAt,
    this.updatedAt,
  });

  bool get isCompleted => status == InspectionStepStatus.completed;

  factory InspectionStepRow.fromJson(Map<String, dynamic> j) => InspectionStepRow(
        inspectionId: j['inspectionId'] as String,
        stepId: j['stepId'] as String,
        stepOrder: (j['stepOrder'] as num?)?.toInt() ?? 0,
        stepType: (j['stepType'] as String?) ?? 'photo',
        section: (j['section'] as String?) ?? '',
        photoCount: (j['photoCount'] as num?)?.toInt() ?? 0,
        audioSeconds: (j['audioSeconds'] as num?)?.toInt() ?? 0,
        status: _statusFromString(j['status'] as String?),
        mediaUrls: (j['mediaUrls'] as List?)?.cast<String>() ?? const [],
        data: ((j['data'] as Map?)?.cast<String, dynamic>()) ?? const {},
        aiAnalysis: (j['aiAnalysis'] as Map?)?.cast<String, dynamic>(),
        notes: (j['notes'] as String?) ?? '',
        startedAt: _parseDate(j['startedAt']),
        completedAt: _parseDate(j['completedAt']),
        updatedAt: _parseDate(j['updatedAt']),
      );

  static InspectionStepStatus _statusFromString(String? s) {
    switch (s) {
      case 'inProgress': return InspectionStepStatus.inProgress;
      case 'completed':  return InspectionStepStatus.completed;
      default:           return InspectionStepStatus.pending;
    }
  }

  static DateTime? _parseDate(dynamic v) =>
      v is String ? DateTime.tryParse(v) : null;
}
