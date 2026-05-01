import 'audit_entry.dart';
import 'location_model.dart';
import 'user_model.dart';

/// Обёртка результата loadLocationDetails (вместо Dart record для совместимости).
class LocationDetailsResult {
  const LocationDetailsResult({this.data, this.error});
  final LocationDetails? data;
  final String? error;
}

/// Данные экрана выбранной локации (admin).
/// Загружается одним запросом: GET /locations/{id}/details
class LocationDetails {
  LocationDetails._internal({
    required this.location,
    required this.users,
    required this.auditLogs,
    required this.rawAuditLogs,
  });

  final LocationModel location;

  /// Сотрудники локации, без admin-ов.
  final List<UserModel> users;

  /// Распарсенные записи аудита (user_id заменён на имя).
  final List<AuditEntry> auditLogs;

  /// Сырые записи для точной фильтрации по user_id в UI.
  final List<Map<String, dynamic>> rawAuditLogs;

  factory LocationDetails.fromJson(Map<String, dynamic> json) {
    final locJson = json['location'] as Map<String, dynamic>;
    final location = LocationModel(
      id:       (locJson['id']  as num?)?.toInt() ?? 0,
      name:     locJson['name'] as String? ?? '',
      imageUrl: locJson['image_url'] as String?,
    );

    final usersJson = (json['users'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    final users = usersJson
        .where((u) => (u['role'] as String?) != 'admin')
        .map((u) => UserModel(
              id:       (u['id']       as num?)?.toInt() ?? 0,
              username: u['username']  as String? ?? '',
              fullName: u['full_name'] as String? ?? '',
              role:     u['role']      as String? ?? 'viewer',
              email:    u['email']     as String?,
            ))
        .toList();

    final userNames = <int, String>{
      for (final u in users)
        u.id: u.fullName.isNotEmpty ? u.fullName : u.username,
    };

    final rawLogs = (json['audit_logs'] as List<dynamic>? ?? [])
        .cast<Map<String, dynamic>>();

    final auditLogs = rawLogs.map((e) {
      final uid   = (e['user_id'] as num?)?.toInt() ?? 0;
      final tsRaw = e['timestamp'] as String? ?? '';
      String timeFmt = tsRaw;
      try {
        final dt = DateTime.parse(tsRaw).toLocal();
        final h  = dt.hour.toString().padLeft(2, '0');
        final mn = dt.minute.toString().padLeft(2, '0');
        final d  = dt.day.toString().padLeft(2, '0');
        final mo = dt.month.toString().padLeft(2, '0');
        timeFmt = '$d.$mo.${dt.year}  $h:$mn';
      } catch (_) {}
      return AuditEntry(
        user:   userNames[uid] ?? 'ID:$uid',
        action: e['action'] as String? ?? '',
        time:   timeFmt,
      );
    }).toList();

    return LocationDetails._internal(
      location:     location,
      users:        users,
      auditLogs:    auditLogs,
      rawAuditLogs: rawLogs,
    );
  }
}