import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralised API endpoint registry. Swap base URL via .env.
class ApiEndpoints {
  static String get baseUrl => dotenv.env['API_BASE_URL'] ?? 'https://api.example.com';

  // Auth
  static String get requestOtp => '$baseUrl/auth/request-otp';
  static String get verifyOtp  => '$baseUrl/auth/verify-otp';
  static String get me         => '$baseUrl/auth/me';
  static String get logout     => '$baseUrl/auth/logout';
  static String get jockeyProfile => '$baseUrl/jockey/profile';

  // Jobs
  static String get todaysJobs => '$baseUrl/jobs/today';

  // Uploads
  static String get uploadPhoto  => '$baseUrl/upload/photo';
  static String get uploadAudio  => '$baseUrl/upload/audio';
  static String get uploadSelfie => '$baseUrl/uploads/selfie';

  // AI
  static String get analyzeImage       => '$baseUrl/ai/analyze-image';
  static String get analyzeAudio       => '$baseUrl/ai/analyze-audio';
  static String get analyzeAnswer      => '$baseUrl/ai/analyze-answer';
  static String get analyzeEngineSound => '$baseUrl/ai/analyze-engine-sound';
  static String get transcribe         => '$baseUrl/ai/transcribe';
  static String get tts                => '$baseUrl/ai/tts';

  // Inspections
  static String get inspections => '$baseUrl/inspections';
  static String inspection(String id) => '$baseUrl/inspections/$id';
  static String inspectionSteps(String id) => '$baseUrl/inspections/$id/steps';
  static String inspectionStep(String id, String stepId) =>
      '$baseUrl/inspections/$id/steps/$stepId';
  static String inspectionStepMedia(String id, String stepId) =>
      '$baseUrl/inspections/$id/steps/$stepId/media';
  static String inspectionComplete(String id) =>
      '$baseUrl/inspections/$id/complete';
  static String inspectionReport(String id) => '$baseUrl/inspections/$id/report';
  static String inspectionTickets(String id) => '$baseUrl/inspections/$id/tickets';
  static String inspectionLeads(String id) => '$baseUrl/inspections/$id/leads';

  // Report
  static String get generateReport => '$baseUrl/report/generate';
  static String get submitReport   => '$baseUrl/report/submit';
}
