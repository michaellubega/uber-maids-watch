import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Error raised for any failed API call.  [isNetwork] distinguishes "the phone
/// has no signal" from "the server said no", which the UI treats very
/// differently (offline mode vs. validation error).
class ApiException implements Exception {
  ApiException({
    required this.message,
    this.statusCode,
    this.details = const <String, dynamic>{},
    this.isNetwork = false,
  });

  factory ApiException.network([String? message]) => ApiException(
        message: message ??
            'Cannot reach the server. Check the connection and the API address.',
        isNetwork: true,
      );

  factory ApiException.fromResponse(int statusCode, String body) {
    Map<String, dynamic> details = <String, dynamic>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        details = Map<String, dynamic>.from(decoded);
      } else if (decoded != null) {
        details = {'detail': decoded};
      }
    } catch (_) {
      if (body.trim().isNotEmpty) details = {'detail': body.trim()};
    }
    return ApiException(
      statusCode: statusCode,
      message: _summarise(details, statusCode),
      details: details,
    );
  }

  final String message;
  final int? statusCode;
  final Map<String, dynamic> details;
  final bool isNetwork;

  bool get isUnauthorised => statusCode == 401;
  bool get isForbidden => statusCode == 403;

  @override
  String toString() => message;

  static String _summarise(Map<String, dynamic> details, int status) {
    final detail = details['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    if (detail is List && detail.isNotEmpty) return detail.join(' ');
    for (final entry in details.entries) {
      final value = entry.value;
      if (value is List && value.isNotEmpty) {
        return '${_label(entry.key)}: ${value.first}';
      }
      if (value is String && value.isNotEmpty) {
        return '${_label(entry.key)}: $value';
      }
      if (value is Map && value.isNotEmpty) {
        return '${_label(entry.key)}: ${_firstLine(value)}';
      }
    }
    if (status == 401) return 'Your session has expired. Please sign in again.';
    if (status == 403) return 'Your role does not permit this action.';
    if (status == 404) return 'The record was not found on the server.';
    return 'The server rejected the request ($status).';
  }

  static String _firstLine(Map<dynamic, dynamic> value) {
    for (final entry in value.entries) {
      return '${entry.key}: ${entry.value}';
    }
    return '';
  }

  static String _label(String key) {
    final spaced = key.replaceAll('_', ' ').trim();
    if (spaced.isEmpty) return key;
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}

/// Thin JSON client with a single automatic token-refresh retry.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.accessToken,
    this.onRefresh,
  }) : _http = httpClient ?? http.Client();

  String baseUrl;
  final http.Client _http;

  /// Returns the current access token, or null when signed out.
  String? Function()? accessToken;

  /// Refreshes expired credentials and returns a new access token.
  Future<String?> Function()? onRefresh;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) {
    return _request('GET', path,
        query: query, authenticated: authenticated);
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Object? body,
    bool authenticated = true,
  }) {
    return _request('POST', path, body: body, authenticated: authenticated);
  }

  Future<Map<String, dynamic>> patch(
    String path, {
    Object? body,
    bool authenticated = true,
  }) {
    return _request('PATCH', path, body: body, authenticated: authenticated);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool authenticated = true,
    bool allowRefresh = true,
  }) async {
    final root = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final suffix = path.startsWith('/') ? path : '/$path';
    final uri = Uri.parse('$root$suffix').replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );

    final headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    if (authenticated) {
      final token = accessToken?.call();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }

    http.Response response;
    try {
      final encoded = body == null ? null : jsonEncode(body);
      response = await _http
          .send(http.Request(method, uri)
            ..headers.addAll(headers)
            ..body = encoded ?? '')
          .then(http.Response.fromStream)
          .timeout(ApiConfig.requestTimeout);
    } on TimeoutException {
      throw ApiException.network('The server took too long to respond.');
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException.network();
    }

    if (response.statusCode == 401 &&
        authenticated &&
        allowRefresh &&
        onRefresh != null) {
      String? refreshed;
      try {
        refreshed = await onRefresh!.call();
      } catch (_) {
        refreshed = null;
      }
      if (refreshed != null && refreshed.isNotEmpty) {
        return _request(
          method,
          path,
          query: query,
          body: body,
          authenticated: authenticated,
          allowRefresh: false,
        );
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
    if (response.body.trim().isEmpty) return <String, dynamic>{};

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return <String, dynamic>{'results': decoded};
    } catch (_) {
      throw ApiException(
        message: 'The server returned an unreadable response.',
        statusCode: response.statusCode,
      );
    }
  }

  void close() => _http.close();
}
