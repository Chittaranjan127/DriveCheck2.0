/// Section grouping for inspection steps.
enum StepSection { arrival, documents, exterior, interior, mechanical, testDrive }

/// Step interaction type.
enum StepType { arrival, photo, multiPhoto, audio, voiceQA }

/// Single inspection step definition.
class InspectionStep {
  final String id;
  final StepSection section;
  final StepType type;
  final String titleKey;
  final String instructionKey;
  final String? referenceImagePath;
  final int photoCount;
  final int audioSeconds;

  const InspectionStep({
    required this.id,
    required this.section,
    required this.type,
    required this.titleKey,
    required this.instructionKey,
    this.referenceImagePath,
    this.photoCount = 1,
    this.audioSeconds = 0,
  });
}
