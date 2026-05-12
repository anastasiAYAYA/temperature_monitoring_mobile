part of '../app_repository.dart';

extension AppRepositoryHttpHelpers on AppRepository {
  String? parseError(String body) {
    // достать detail из типичного FastAPI ответа
    try {
      final decoded =
          jsonDecode(body) as Map<String, dynamic>; // JSON объект ошибки
      return decoded['detail'] as String?; // строка для пользователя
    } catch (_) {
      return null;
    } // не JSON — без detail
  }

  // ── HTTP хелперы ──────────────────────────────────────────────────────────

  Future<http.Response> get(String path) => // GET с Bearer
  http
      .get(
        Uri.parse('$baseUrl$path'), // полный URL
        headers: {'Authorization': 'Bearer $token'},
      )
      .timeout(_kTimeout); // JWT и таймаут

  Future<http.Response> post(
    String path,
    Map<String, dynamic> body,
  ) => // POST JSON
  http
      .post(
        Uri.parse('$baseUrl$path'), // URL
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }, // заголовки
        body: jsonEncode(body),
      )
      .timeout(_kTimeout); // сериализация тела

  Future<http.Response> patch(
    String path,
    Map<String, dynamic> body,
  ) => // PATCH JSON
  http
      .patch(
        Uri.parse('$baseUrl$path'), // URL
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }, // заголовки
        body: jsonEncode(body),
      )
      .timeout(_kTimeout); // тело

  Future<http.Response> delete(String path) => // DELETE с Bearer
  http
      .delete(
        Uri.parse('$baseUrl$path'), // URL
        headers: {'Authorization': 'Bearer $token'},
      )
      .timeout(_kTimeout); // JWT и таймаут
}
