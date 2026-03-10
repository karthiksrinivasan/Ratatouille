import 'dart:async';
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

/// A lightweight cancel token for aborting in-flight API requests.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;

  void throwIfCancelled() {
    if (_cancelled) throw CancelledException();
  }
}

/// Thrown when a request is cancelled via [CancelToken].
class CancelledException implements Exception {
  @override
  String toString() => 'Request was cancelled';
}

/// Signature for a function that provides an auth token.
typedef TokenProvider = Future<String?> Function();

/// HTTP client wrapper with auth token injection and error handling.
class ApiClient {
  final AuthService? authService;
  final TokenProvider? _tokenProvider;
  final http.Client _httpClient;
  final String _baseUrl;

  ApiClient({
    this.authService,
    TokenProvider? tokenProvider,
    http.Client? httpClient,
    String? baseUrl,
  })  : _tokenProvider = tokenProvider,
        _httpClient = httpClient ?? http.Client(),
        _baseUrl = baseUrl ??
            (authService != null ? EnvConfig.backendUrl : 'http://localhost');

  static const Duration _defaultTimeout = Duration(seconds: 10);
  static const Duration _aiTimeout = Duration(seconds: 30);

  /// AI endpoint path fragments that get the longer timeout.
  static const _aiPaths = [
    'vision-check', 'visual-guide', 'taste-check', 'recover',
  ];

  Duration _timeoutFor(String path) {
    if (_aiPaths.any((p) => path.contains(p))) return _aiTimeout;
    return _defaultTimeout;
  }

  Future<T> _withTimeout<T>(Future<T> future, {Duration? timeout}) {
    return future.timeout(timeout ?? _defaultTimeout);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Send a GET request.
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? queryParams,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final uri = _buildUri(path, queryParams);
    final headers = await _authHeaders();
    final response = await _withTimeout(
      _httpClient.get(uri, headers: headers),
      timeout: _timeoutFor(path),
    );
    cancelToken?.throwIfCancelled();
    return _handleResponse(response);
  }

  /// Send a GET request expecting a JSON array response.
  Future<List<dynamic>> getList(
    String path, {
    Map<String, String>? queryParams,
  }) async {
    final uri = _buildUri(path, queryParams);
    final headers = await _authHeaders();
    final response = await _withTimeout(
      _httpClient.get(uri, headers: headers),
      timeout: _timeoutFor(path),
    );
    return _handleListResponse(response);
  }

  /// Send a POST request with a JSON body.
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final uri = _buildUri(path);
    final headers = await _authHeaders();
    headers[HttpHeaders.contentTypeHeader] = 'application/json';
    final response = await _withTimeout(
      _httpClient.post(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      ),
      timeout: _timeoutFor(path),
    );
    cancelToken?.throwIfCancelled();
    return _handleResponse(response);
  }

  /// Send a PUT request with a JSON body.
  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final uri = _buildUri(path);
    final headers = await _authHeaders();
    headers[HttpHeaders.contentTypeHeader] = 'application/json';
    final response = await _withTimeout(
      _httpClient.put(
        uri,
        headers: headers,
        body: body != null ? jsonEncode(body) : null,
      ),
      timeout: _timeoutFor(path),
    );
    cancelToken?.throwIfCancelled();
    return _handleResponse(response);
  }

  /// Send a DELETE request.
  Future<Map<String, dynamic>> delete(
    String path, {
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final uri = _buildUri(path);
    final headers = await _authHeaders();
    final response = await _withTimeout(
      _httpClient.delete(uri, headers: headers),
      timeout: _timeoutFor(path),
    );
    cancelToken?.throwIfCancelled();
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

    final String? token;
    if (_tokenProvider != null) {
      token = await _tokenProvider();
    } else if (authService != null) {
      token = await authService!.getIdToken();
    } else {
      token = null;
    }

    if (token != null) {
      headers[HttpHeaders.authorizationHeader] = 'Bearer $token';
    }

    return headers;
  }

  /// Execute a GET request with automatic 401 retry and 5xx exponential backoff.
  Future<Map<String, dynamic>> getWithRetry(
    String path, {
    Map<String, String>? queryParams,
    int maxRetries = 2,
  }) async {
    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await get(path, queryParams: queryParams);
      } on ApiException catch (e) {
        if (e.isUnauthorized && attempt == 0) {
          await _forceRefreshToken();
          continue;
        }
        if (e.statusCode >= 502 && e.statusCode <= 504 && attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * (1 << attempt)));
          continue;
        }
        rethrow;
      }
    }
    return get(path, queryParams: queryParams);
  }

  /// Execute a POST request with automatic 401 retry (force-refreshes token).
  Future<Map<String, dynamic>> postWithRetry(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      return await post(path, body: body);
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _forceRefreshToken();
        return post(path, body: body);
      }
      rethrow;
    }
  }

  Future<void> _forceRefreshToken() async {
    if (authService != null) {
      await authService!.getIdToken(forceRefresh: true);
    }
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

  List<dynamic> _handleListResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.isNotEmpty
          ? jsonDecode(response.body) as List<dynamic>
          : <dynamic>[];
    }

    final body = response.body.isNotEmpty
        ? jsonDecode(response.body) as Map<String, dynamic>
        : <String, dynamic>{};

    throw ApiException(
      statusCode: response.statusCode,
      message: body['detail']?.toString() ?? 'Request failed',
      details: body,
    );
  }
}
