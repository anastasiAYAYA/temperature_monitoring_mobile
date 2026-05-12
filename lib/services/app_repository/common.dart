part of '../app_repository.dart';

extension AppRepositoryCommon on AppRepository {
  List<dynamic> _extractDataList(String body) {
    // функция для извлечения списка данных
    try {
      final decoded = jsonDecode(body); // декодируем JSON
      if (decoded is List)
        return decoded; // если decoded является списком, то возвращаем его
      if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
        // если decoded является мапой и содержит ключ 'data', то возвращаем список данных
        return decoded['data'] as List<dynamic>;
      }
      return []; // возвращаем пустой список
    } catch (_) {
      return [];
    }
  }

  // ── Аутентификация ────────────────────────────────────────────────────────
}
