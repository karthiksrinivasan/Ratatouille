import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../core/api_client.dart';
import '../../../core/auth_service.dart';
import '../../../core/env_config.dart';
import '../models/scan_models.dart';

/// Service layer for inventory scan API calls.
class ScanService {
  final ApiClient _api;
  final AuthService? _authService;

  ScanService({required ApiClient api, AuthService? authService})
      : _api = api,
        _authService = authService;

  /// Upload images and create a scan.
  /// Returns a [ScanCreateResponse] with the scan_id.
  Future<ScanCreateResponse> createScan({
    required String source,
    required List<File> imageFiles,
  }) async {
    final uri = Uri.parse('${EnvConfig.backendUrl}/v1/inventory-scans');
    final request = http.MultipartRequest('POST', uri);

    // Auth header.
    if (_authService != null) {
      final token = await _authService!.getIdToken();
      if (token != null) {
        request.headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
      }
    }

    request.fields['source'] = source;

    for (int i = 0; i < imageFiles.length; i++) {
      request.files.add(
        await http.MultipartFile.fromPath('images', imageFiles[i].path),
      );
    }

    final streamedResponse = await http.Client().send(request);
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ScanCreateResponse.fromJson(body);
    }

    final detail = _extractError(response.body);
    throw ApiException(statusCode: response.statusCode, message: detail);
  }

  /// Trigger ingredient detection on a scan.
  Future<DetectResponse> detectIngredients(String scanId) async {
    final data = await _api.post('/v1/inventory-scans/$scanId/detect');
    return DetectResponse.fromJson(data);
  }

  /// Confirm/edit the ingredient list.
  Future<ConfirmResponse> confirmIngredients(
    String scanId,
    List<String> ingredients,
  ) async {
    final data = await _api.post(
      '/v1/inventory-scans/$scanId/confirm-ingredients',
      body: {'confirmed_ingredients': ingredients},
    );
    return ConfirmResponse.fromJson(data);
  }

  /// Fetch dual-lane suggestions.
  Future<SuggestionsResponse> getSuggestions(String scanId) async {
    final data = await _api.get('/v1/inventory-scans/$scanId/suggestions');
    return SuggestionsResponse.fromJson(data);
  }

  /// Get expanded "Why this recipe?" explanation.
  Future<ExplainResponse> explainSuggestion(
    String scanId,
    String suggestionId,
  ) async {
    final data = await _api.get(
      '/v1/inventory-scans/$scanId/suggestions/$suggestionId/explain',
    );
    return ExplainResponse.fromJson(data);
  }

  /// Start a session from a selected suggestion.
  Future<StartSessionResponse> startSession(
    String scanId,
    String suggestionId, {
    Map<String, dynamic>? modeSettings,
  }) async {
    final data = await _api.post(
      '/v1/inventory-scans/$scanId/start-session',
      body: {
        'suggestion_id': suggestionId,
        if (modeSettings != null) 'mode_settings': modeSettings,
      },
    );
    return StartSessionResponse.fromJson(data);
  }

  String _extractError(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['detail']?.toString() ?? 'Request failed';
    } catch (_) {
      return 'Request failed';
    }
  }
}
