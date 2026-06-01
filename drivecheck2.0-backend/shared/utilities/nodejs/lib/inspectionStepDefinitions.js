/**
 * Server-side mirror of `lib/core/constants/inspection_steps.dart`.
 *
 * Source of truth for what steps an inspection has. Used by
 * createInspection to seed one row per step into the InspectionSteps
 * table when a new inspection is created.
 *
 * Keep this in sync with the Flutter constant — adding a step here
 * without also adding it on the client (or vice-versa) means new
 * inspections will have an unreachable step row.
 */
const INSPECTION_STEPS = [
  { stepId: 'arrival',            order: 1,  type: 'arrival',    section: 'arrival',    photoCount: 0, audioSeconds: 0 },
  { stepId: 'rc_document',        order: 2,  type: 'photo',      section: 'documents',  photoCount: 1, audioSeconds: 0 },
  { stepId: 'instrument_cluster', order: 3,  type: 'photo',      section: 'interior',   photoCount: 1, audioSeconds: 0 },
  { stepId: 'engine_bay',         order: 4,  type: 'photo',      section: 'mechanical', photoCount: 1, audioSeconds: 0 },
  { stepId: 'front_full',         order: 5,  type: 'photo',      section: 'exterior',   photoCount: 1, audioSeconds: 0 },
  { stepId: 'lhs_full',           order: 6,  type: 'photo',      section: 'exterior',   photoCount: 1, audioSeconds: 0 },
  { stepId: 'rhs_full',           order: 7,  type: 'photo',      section: 'exterior',   photoCount: 1, audioSeconds: 0 },
  { stepId: 'rear_full',          order: 8,  type: 'photo',      section: 'exterior',   photoCount: 1, audioSeconds: 0 },
  { stepId: 'roof',               order: 9,  type: 'photo',      section: 'exterior',   photoCount: 1, audioSeconds: 0 },
  { stepId: 'interior',           order: 10, type: 'photo',      section: 'interior',   photoCount: 1, audioSeconds: 0 },
  { stepId: 'tyres',              order: 11, type: 'multiPhoto', section: 'exterior',   photoCount: 4, audioSeconds: 0 },
  { stepId: 'engine_sound',       order: 12, type: 'audio',      section: 'mechanical', photoCount: 0, audioSeconds: 15 },
  { stepId: 'test_drive',         order: 13, type: 'voiceQA',    section: 'testDrive',  photoCount: 0, audioSeconds: 0 },
];

const STEP_IDS = new Set(INSPECTION_STEPS.map((s) => s.stepId));
const STEP_BY_ID = Object.fromEntries(INSPECTION_STEPS.map((s) => [s.stepId, s]));

module.exports = { INSPECTION_STEPS, STEP_IDS, STEP_BY_ID };
