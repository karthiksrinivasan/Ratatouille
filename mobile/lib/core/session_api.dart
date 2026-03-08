import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api_client.dart';

/// Typed models for session-related API responses.

class ActivateResponse {
  final String sessionId;
  final String status;
  final String wsEndpoint;

  const ActivateResponse({
    required this.sessionId,
    required this.status,
    required this.wsEndpoint,
  });

  factory ActivateResponse.fromJson(Map<String, dynamic> json) {
    return ActivateResponse(
      sessionId: json['session_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      wsEndpoint: json['ws_endpoint'] as String? ?? '',
    );
  }
}

class VisionCheckResponse {
  final String sessionId;
  final String assessment;
  final double confidence;
  final String stage;
  final List<String> observations;
  final String recommendation;

  const VisionCheckResponse({
    required this.sessionId,
    required this.assessment,
    required this.confidence,
    required this.stage,
    this.observations = const [],
    required this.recommendation,
  });

  factory VisionCheckResponse.fromJson(Map<String, dynamic> json) {
    return VisionCheckResponse(
      sessionId: json['session_id'] as String? ?? '',
      assessment: json['assessment'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      stage: json['stage'] as String? ?? '',
      observations:
          (json['observations'] as List<dynamic>?)?.cast<String>() ?? [],
      recommendation: json['recommendation'] as String? ?? '',
    );
  }
}

class VisualGuideResponse {
  final String sessionId;
  final String guideImageUrl;
  final String targetState;
  final List<String> visualCues;
  final String stage;

  const VisualGuideResponse({
    required this.sessionId,
    required this.guideImageUrl,
    required this.targetState,
    this.visualCues = const [],
    required this.stage,
  });

  factory VisualGuideResponse.fromJson(Map<String, dynamic> json) {
    return VisualGuideResponse(
      sessionId: json['session_id'] as String? ?? '',
      guideImageUrl: json['guide_image_url'] as String? ?? '',
      targetState: json['target_state'] as String? ?? '',
      visualCues:
          (json['visual_cues'] as List<dynamic>?)?.cast<String>() ?? [],
      stage: json['stage'] as String? ?? '',
    );
  }
}

class TasteCheckResponse {
  final String sessionId;
  final Map<String, double> dimensions;
  final String recommendation;
  final String confidence;

  const TasteCheckResponse({
    required this.sessionId,
    this.dimensions = const {},
    required this.recommendation,
    required this.confidence,
  });

  factory TasteCheckResponse.fromJson(Map<String, dynamic> json) {
    final dims = json['dimensions'] as Map<String, dynamic>? ?? {};
    return TasteCheckResponse(
      sessionId: json['session_id'] as String? ?? '',
      dimensions:
          dims.map((k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0.0)),
      recommendation: json['recommendation'] as String? ?? '',
      confidence: json['confidence'] as String? ?? '',
    );
  }
}

class RecoveryResponse {
  final String sessionId;
  final String immediateAction;
  final String explanation;
  final List<String> alternativeActions;
  final String severity;

  const RecoveryResponse({
    required this.sessionId,
    required this.immediateAction,
    required this.explanation,
    this.alternativeActions = const [],
    required this.severity,
  });

  factory RecoveryResponse.fromJson(Map<String, dynamic> json) {
    return RecoveryResponse(
      sessionId: json['session_id'] as String? ?? '',
      immediateAction: json['immediate_action'] as String? ?? '',
      explanation: json['explanation'] as String? ?? '',
      alternativeActions:
          (json['alternative_actions'] as List<dynamic>?)?.cast<String>() ??
              [],
      severity: json['severity'] as String? ?? '',
    );
  }
}

class CompleteResponse {
  final String sessionId;
  final String status;
  final Map<String, dynamic>? summary;

  const CompleteResponse({
    required this.sessionId,
    required this.status,
    this.summary,
  });

  factory CompleteResponse.fromJson(Map<String, dynamic> json) {
    return CompleteResponse(
      sessionId: json['session_id'] as String? ?? '',
      status: json['status'] as String? ?? '',
      summary: json['summary'] as Map<String, dynamic>?,
    );
  }
}

/// Typed API service for all session-related endpoints.
class SessionApiService {
  final ApiClient _api;

  SessionApiService({required ApiClient api}) : _api = api;

  /// POST /v1/sessions/{id}/activate
  Future<ActivateResponse> activate(String sessionId) async {
    try {
      final data = await _api.postWithRetry('/v1/sessions/$sessionId/activate');
      return ActivateResponse.fromJson(data);
    } catch (e) {
      _logContractError('activate', e);
      rethrow;
    }
  }

  /// POST /v1/sessions/{id}/vision-check
  Future<VisionCheckResponse> visionCheck(
    String sessionId, {
    required String frameUri,
    String? currentStep,
  }) async {
    try {
      final data = await _api.postWithRetry(
        '/v1/sessions/$sessionId/vision-check',
        body: {
          'frame_uri': frameUri,
          if (currentStep != null) 'current_step': currentStep,
        },
      );
      return VisionCheckResponse.fromJson(data);
    } catch (e) {
      _logContractError('vision-check', e);
      rethrow;
    }
  }

  /// POST /v1/sessions/{id}/visual-guide
  Future<VisualGuideResponse> visualGuide(
    String sessionId, {
    required String stage,
    String? sourceFrameUri,
  }) async {
    try {
      final data = await _api.postWithRetry(
        '/v1/sessions/$sessionId/visual-guide',
        body: {
          'stage': stage,
          if (sourceFrameUri != null) 'source_frame_uri': sourceFrameUri,
        },
      );
      return VisualGuideResponse.fromJson(data);
    } catch (e) {
      _logContractError('visual-guide', e);
      rethrow;
    }
  }

  /// POST /v1/sessions/{id}/taste-check
  Future<TasteCheckResponse> tasteCheck(
    String sessionId, {
    required String diagnostic,
  }) async {
    try {
      final data = await _api.postWithRetry(
        '/v1/sessions/$sessionId/taste-check',
        body: {'diagnostic': diagnostic},
      );
      return TasteCheckResponse.fromJson(data);
    } catch (e) {
      _logContractError('taste-check', e);
      rethrow;
    }
  }

  /// POST /v1/sessions/{id}/recover
  Future<RecoveryResponse> recover(
    String sessionId, {
    required String issue,
  }) async {
    try {
      final data = await _api.postWithRetry(
        '/v1/sessions/$sessionId/recover',
        body: {'issue': issue},
      );
      return RecoveryResponse.fromJson(data);
    } catch (e) {
      _logContractError('recover', e);
      rethrow;
    }
  }

  /// POST /v1/sessions/{id}/complete
  Future<CompleteResponse> complete(String sessionId) async {
    try {
      final data =
          await _api.postWithRetry('/v1/sessions/$sessionId/complete');
      return CompleteResponse.fromJson(data);
    } catch (e) {
      _logContractError('complete', e);
      rethrow;
    }
  }

  void _logContractError(String endpoint, dynamic error) {
    if (error is FormatException) {
      debugPrint(
          'SessionApiService: contract mismatch on $endpoint — $error');
    }
  }
}
