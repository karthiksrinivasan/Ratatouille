import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'env_config.dart';

/// Standard API error with status code and message.
class ApiException implements Exception {
  final int statusCode;
  final String message;
  final Map<String, dynamic>? details;

  const ApiException({
    required this.statusCode,
    required this.message,
    this.details,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isServerError => statusCode >= 500;
}

/// HTTP client wrapper with auth token injection and error handling.
class ApiClient {
  final AuthService authService;
  final http.Client _httpClient;
  final String _baseUrl;

  ApiClient({
    required this.authService,
    http.Client? httpClient,
    String? baseUrl,
  })  : _httpClient = httpClient ?? http.Client(),
        _baseUrl = baseUrl ?? EnvConfig.backendUrl;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Send a GET request.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final uri = _buildUri(path, queryParams);
    final headers = await _authHeaders();
    final response = await _httpClient.get(uri, headers: headers);
    return _handleResponse(response);
  }

  /// Send a POST request with a JSON body.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(path);
    final headers = await _authHeaders();
    headers[HttpHeaders.contentTypeHeader] = 'application/json';
    final response = await _httpClient.post(
      uri,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  /// Send a PUT request with a JSON body.
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = _buildUri(path);
    final headers = await _authHeaders();
    headers[HttpHeaders.contentTypeHeader] = 'application/json';
    final response = await _httpClient.put(
      uri,
      headers: headers,
      body: body != null ? jsonEncode(body) : null,
    );
    return _handleResponse(response);
  }

  /// Send a DELETE request.
  Future<Map<String, dynamic>> delete(String path) async {
    final uri = _buildUri(path);
    final headers = await _authHeaders();
    final response = await _httpClient.delete(uri, headers: headers);
    return _handleResponse(response);
  }

  /// Upload a file via multipart POST.
  Future<Map<String, dynamic>> uploadFile(
    String path, {
    required String filePath,
    String fieldName = 'file',
    Map<String, String>? extraFields,
  }) async {
    final uri = _buildUri(path);
    final request = http.MultipartRequest('POST', uri);

    // Auth header.
    final headers = await _authHeaders();
    request.headers.addAll(headers);

    // File attachment.
    request.files.add(await http.MultipartFile.fromPath(fieldName, filePath));

    // Extra form fields.
    if (extraFields != null) {
      request.fields.addAll(extraFields);
    }

    final streamedResponse = await _httpClient.send(request);
    final response = await http.Response.fromStream(streamedResponse);
    return _handleResponse(response);
  }

  /// Dispose of the underlying HTTP client.
  void dispose() {
    _httpClient.close();
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Uri _buildUri(String path, [Map<String, String>? queryParams]) {
    final base = _baseUrl.endsWith('/') ? _baseUrl.substring(0, _baseUrl.length - 1) : _baseUrl;
    final cleanPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$cleanPath').replace(queryParameters: queryParams);
  }

  Future<Map<String, String>> _authHeaders() async {
    final headers = <String, String>{
      HttpHeaders.acceptHeader: 'application/json',
    };

    final token = await authService.getIdToken();
    if (token != null) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    }

    return headers;
  }

  Map<String, dynamic> _handleResponse(http.Response response) {
    final body = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    throw ApiException(
      statusCode: response.statusCode,
      message: body['detail']?.toString() ?? 'Request failed',
      details: body,
    );
  }
}
