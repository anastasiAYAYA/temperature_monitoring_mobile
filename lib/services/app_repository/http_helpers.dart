part of '../app_repository.dart';

extension AppRepositoryHttpHelpers on AppRepository {
  String? parseError(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      return decoded['detail'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response> get(String path) => http
      .get(
        Uri.parse('$baseUrl$path'),
        headers: {'Authorization': 'Bearer $token'},
      )
      .timeout(_kTimeout);

  Future<http.Response> post(String path, Map<String, dynamic> body) => http
      .post(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      )
      .timeout(_kTimeout);

  Future<http.Response> put(String path, Map<String, dynamic> body) => http
      .put(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      )
      .timeout(_kTimeout);

  Future<http.Response> patch(String path, Map<String, dynamic> body) => http
      .patch(
        Uri.parse('$baseUrl$path'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      )
      .timeout(_kTimeout);

  Future<http.Response> delete(String path) => http
      .delete(
        Uri.parse('$baseUrl$path'),
        headers: {'Authorization': 'Bearer $token'},
      )
      .timeout(_kTimeout);
}
