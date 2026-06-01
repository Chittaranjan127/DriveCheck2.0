import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../constants/api_endpoints.dart';
import '../models/inspection.dart';
import '../models/inspection_report.dart';
import '../models/inspection_step_row.dart';
import 'api_service.dart';

/// Calls /inspections* endpoints.
class InspectionsService {
  final Dio _dio;
  InspectionsService([ApiService? api]) : _dio = (api ?? ApiService.create()).dio;

  /// Lists rows assigned to [assignedTo]. When [from]+[to] are provided the
  /// backend uses the `byAssignee` GSI; otherwise it returns the jockey's
  /// full set.
  Future<List<Inspection>> list({
    required String assignedTo,
    DateTime? from,
    DateTime? to,
  }) async {
    try {
      final res = await _dio.get(
        ApiEndpoints.inspections,
        queryParameters: {
          'assignedTo': assignedTo,
          if (from != null) 'from': from.toUtc().toIso8601String(),
          if (to != null) 'to': to.toUtc().toIso8601String(),
        },
      );
      final data = (res.data as Map)['data'] as List;
      return data
          .cast<Map<String, dynamic>>()
          .map(Inspection.fromJson)
          .toList();
    } on DioException catch (e) {
      throw InspectionsException(_dioMessage(e));
    }
  }

  Future<Inspection> getById(String id) async {
    try {
      final res = await _dio.get(ApiEndpoints.inspection(id));
      final data = (res.data as Map)['data'] as Map<String, dynamic>;
      return Inspection.fromJson(data);
    } on DioException catch (e) {
      throw InspectionsException(_dioMessage(e));
    }
  }

  /// Returns the 13 step rows for this inspection in display order.
  Future<List<InspectionStepRow>> listSteps(String id) async {
    try {
      final res = await _dio.get(ApiEndpoints.inspectionSteps(id));
      final data = (res.data as Map)['data'] as List;
      return data
          .cast<Map<String, dynamic>>()
          .map(InspectionStepRow.fromJson)
          .toList();
    } on DioException catch (e) {
      throw InspectionsException(_dioMessage(e));
    }
  }

  /// Patches one step row. Pass [status]='completed' to finalize it; the
  /// backend will set completedAt and bump the parent inspection's
  /// completedStepCount.
  ///
  /// [parentUpdates] is a whitelisted map of fields to reconcile on the
  /// parent Inspection (e.g. RC OCR pushing the real `carTitle`). Backend
  /// drops any field not on its allowlist, so passing extra keys is safe.
  Future<InspectionStepRow> updateStep(
    String id,
    String stepId, {
    List<String>? mediaUrls,
    Map<String, dynamic>? data,
    Map<String, dynamic>? aiAnalysis,
    String? notes,
    String? status,
    Map<String, dynamic>? parentUpdates,
  }) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.inspectionStep(id, stepId),
        data: {
          'mediaUrls': ?mediaUrls,
          'data': ?data,
          'aiAnalysis': ?aiAnalysis,
          'notes': ?notes,
          'status': ?status,
          'parentUpdates': ?parentUpdates,
        },
      );
      final body = (res.data as Map)['data'] as Map<String, dynamic>;
      return InspectionStepRow.fromJson(body);
    } on DioException catch (e) {
      throw InspectionsException(_dioMessage(e));
    }
  }

  /// Uploads a single piece of step media (image or audio) and returns
  /// its public S3 URL. The caller is responsible for passing the
  /// returned URL back via [updateStep] (`mediaUrls`) — this method
  /// only writes to S3 and does NOT mutate the step row.
  ///
  /// Supported `mimeType` values are: image/jpeg, image/png, audio/wav,
  /// audio/mpeg, audio/m4a, audio/aac. The backend derives the S3 key's
  /// extension from this header, so passing the right one matters.
  Future<String> uploadStepMedia(
    String id,
    String stepId,
    Uint8List bytes, {
    String mimeType = 'image/jpeg',
  }) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.inspectionStepMedia(id, stepId),
        data: {
          'mediaBase64': base64Encode(bytes),
          'mimeType': mimeType,
        },
      );
      final body = (res.data as Map)['data'] as Map<String, dynamic>;
      return body['url'] as String;
    } on DioException catch (e) {
      throw InspectionsException(_dioMessage(e));
    }
  }

  /// Fetches the post-inspection report: aggregated step data, AI-
  /// generated price estimate, jockey pitch + next-step instructions.
  /// The AI bundle may be null on the server side if OpenAI hiccupped;
  /// callers should render the structured data even when those fields
  /// are missing.
  ///
  /// [lang] is the 2-letter app language code (`en` / `hi` / `te` /
  /// `bn`). The backend generates the customer-facing copy (jockey
  /// pitch, next-steps instruction, etiquette tips) in that
  /// language's native script.
  Future<InspectionReport> getReport(String id, {String lang = 'en'}) async {
    try {
      final res = await _dio.get(
        ApiEndpoints.inspectionReport(id),
        queryParameters: {'lang': lang},
      );
      final data = (res.data as Map)['data'] as Map<String, dynamic>;
      return InspectionReport.fromJson(data);
    } on DioException catch (e) {
      throw InspectionsException(_dioMessage(e));
    }
  }

  /// Submits a closed-deal lead — the customer agreed to the AI-
  /// suggested price after the jockey's pitch. Writes to the
  /// InspectionLeads table with a full snapshot of the inspection
  /// for procurement to pick up.
  Future<InspectionLead> createLead(
    String inspectionId, {
    required int agreedPriceInr,
    required int aiPriceInr,
    String? notes,
  }) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.inspectionLeads(inspectionId),
        data: {
          'agreedPriceInr': agreedPriceInr,
          'aiPriceInr': aiPriceInr,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      final data = (res.data as Map)['data'] as Map<String, dynamic>;
      return InspectionLead.fromJson(data);
    } on DioException catch (e) {
      throw InspectionsException(_dioMessage(e));
    }
  }

  /// Submits the customer's decision after the jockey reads out the AI
  /// price. [outcome] is what the customer said; [aiPriceInr] is the
  /// price the model generated (echoed back for the ticket record);
  /// [customerPriceInr] is required when [outcome] is `countered`.
  /// [notes] is free-text from the jockey.
  Future<InspectionTicket> createTicket(
    String inspectionId, {
    required TicketOutcome outcome,
    required int aiPriceInr,
    int? customerPriceInr,
    String? notes,
  }) async {
    try {
      final res = await _dio.post(
        ApiEndpoints.inspectionTickets(inspectionId),
        data: {
          'outcome': outcome.wire,
          'aiPriceInr': aiPriceInr,
          'customerPriceInr': ?customerPriceInr,
          if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
        },
      );
      final data = (res.data as Map)['data'] as Map<String, dynamic>;
      return InspectionTicket.fromJson(data);
    } on DioException catch (e) {
      throw InspectionsException(_dioMessage(e));
    }
  }

  /// Server-side completion gate. Throws [InspectionsIncompleteException]
  /// listing the unfinished stepIds if the inspection isn't ready.
  Future<Inspection> complete(String id) async {
    try {
      final res = await _dio.post(ApiEndpoints.inspectionComplete(id));
      final data = (res.data as Map)['data'] as Map<String, dynamic>;
      return Inspection.fromJson(data);
    } on DioException catch (e) {
      final body = e.response?.data;
      if (body is Map && body['error'] is Map) {
        final err = body['error'] as Map;
        final details = err['details'];
        if (details is Map && details['pendingSteps'] is List) {
          throw InspectionsIncompleteException(
            (details['pendingSteps'] as List).cast<String>(),
          );
        }
      }
      throw InspectionsException(_dioMessage(e));
    }
  }
}

class InspectionsException implements Exception {
  final String message;
  const InspectionsException(this.message);
  @override
  String toString() => message;
}

/// Thrown by [InspectionsService.complete] when the backend refused
/// because some steps are still pending.
class InspectionsIncompleteException implements Exception {
  final List<String> pendingSteps;
  const InspectionsIncompleteException(this.pendingSteps);
  @override
  String toString() =>
      'Inspection has ${pendingSteps.length} pending step(s): ${pendingSteps.join(", ")}';
}

String _dioMessage(DioException e) {
  final s = e.response?.statusCode;
  final body = e.response?.data;
  if (body is Map && body['error'] is Map) {
    return (body['error'] as Map)['message']?.toString() ?? 'Request failed';
  }
  if (s != null) return 'HTTP $s';
  return e.message ?? 'Network error';
}
