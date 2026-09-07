/// Клиент собственного API в Яндекс Облаке.
///
/// Заменяет прямое обращение к Firebase: приложение больше не ходит в базу
/// само, а спрашивает сервер, который и решает, что этому человеку можно.
/// Права проверяются там, а не здесь, — в этом весь смысл переезда.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Адрес шлюза. Меняется вместе с окружением, поэтому вынесен отдельно.
const apiBaseUrl =
    'https://d5dgk7qogd0dbekvq977.7qsg961h.apigw.yandexcloud.net';

/// Ошибка от сервера с текстом, который можно показать человеку: тексты
/// приходят готовыми и на русском, придумывать свои поверх незачем.
class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode, this.maintenanceLock});

  final String message;
  final int? statusCode;
  final Map<String, dynamic>? maintenanceLock;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, this.baseUrl = apiBaseUrl})
    : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  static const _tokenKey = 'tchm_api_token';

  String? _token;

  /// Токен живёт между запусками: иначе человек вводил бы пароль при каждом
  /// открытии приложения.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
  }

  String? get token => _token;

  bool get hasToken => (_token ?? '').isNotEmpty;

  Future<void> setToken(String? value) async {
    _token = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, value);
    }
  }

  Map<String, String> get _headers => {
    'Content-Type': 'application/json; charset=utf-8',
    if (hasToken) 'Authorization': 'Bearer $_token',
  };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    Map<String, dynamic> body;
    try {
      body =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException(
        'Сервер ответил непонятным образом (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        body['error']?.toString() ?? 'Ошибка ${response.statusCode}.',
        statusCode: response.statusCode,
        maintenanceLock:
            body['code'] == 'maintenance_full' ||
                body['code'] == 'maintenance_read_only'
            ? body['lock'] as Map<String, dynamic>?
            : null,
      );
    }
    return body;
  }

  Future<Map<String, dynamic>> get(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await _client.get(_uri(path, query), headers: _headers);
    return _decode(response);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _client.post(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> put(
    String path,
    Map<String, Object?> body,
  ) async {
    final response = await _client.put(
      _uri(path),
      headers: _headers,
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final response = await _client.delete(_uri(path), headers: _headers);
    return _decode(response);
  }
}
