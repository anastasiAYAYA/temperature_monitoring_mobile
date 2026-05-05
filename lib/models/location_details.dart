import 'audit_entry.dart';
import 'location_model.dart';
import 'user_model.dart';

//final - неизменяемые значения, this. - ссылка на свойство класса, required - обязательное значение,
// null - значение по умолчанию, const - константа, enum - перечисление

// Обёртка результата loadLocationDetails
class LocationDetailsResult { // модель результата загрузки данных локации
  const LocationDetailsResult({this.data, this.error}); // конструктор модели результата загрузки данных локации
  final LocationDetails? data; // данные локации
  final String? error; // ошибка
}

// Данные экрана выбранной локации (admin).
// Загружается одним запросом: GET /locations/{id}/details
class LocationDetails { // модель данных экрана выбранной локации
  LocationDetails._internal({ // конструктор модели данных экрана выбранной локации
    required this.location, // локация
    required this.users, // сотрудники локации
    required this.auditLogs, // записи аудита
    required this.rawAuditLogs, // сырые записи для точной фильтрации по user_id в UI
  });

  final LocationModel location; // локация
  final List<UserModel> users; // сотрудники локации, без admin-ов
  final List<AuditEntry> auditLogs; // распарсенные записи аудита (user_id заменён на имя)
  final List<Map<String, dynamic>> rawAuditLogs; // сырые записи для точной фильтрации по user_id в UI

  factory LocationDetails.fromJson(Map<String, dynamic> json) { // фабричный метод для создания модели данных экрана выбранной локации из JSON
    final locJson = json['location'] as Map<String, dynamic>; // JSON локации
    final location = LocationModel( // создание модели локации из JSON
      id:       (locJson['id']  as num?)?.toInt() ?? 0, // id локации
      name:     locJson['name'] as String? ?? '', // название локации
      imageUrl: locJson['image_url'] as String?, // URL изображения локации
    );

    final usersJson = (json['users'] as List<dynamic>? ?? []) // JSON сотрудников
        .cast<Map<String, dynamic>>(); // преобразование в список Map<String, dynamic>, dynamic - любой тип данных

    final users = usersJson
        .where((u) => (u['role'] as String?) != 'admin') // фильтрация сотрудников, без admin-ов
        .map((u) => UserModel( // создание модели сотрудника из JSON
              id:       (u['id']       as num?)?.toInt() ?? 0, // id сотрудника
              username: u['username']  as String? ?? '', // username сотрудника
              fullName: u['full_name'] as String? ?? '', // fullName сотрудника
              role:     u['role']      as String? ?? 'viewer', // role сотрудника
              email:    u['email']     as String?, // email сотрудника
            ))
        .toList(); // преобразование в список UserModel

    final userNames = <int, String>{ // создание словаря id сотрудника -> имя сотрудника
      for (final u in users)
        u.id: u.fullName.isNotEmpty ? u.fullName : u.username, // имя сотрудника
    };

    final rawLogs = (json['audit_logs'] as List<dynamic>? ?? []) // JSON записей аудита
        .cast<Map<String, dynamic>>(); // преобразование в список Map<String, dynamic>

    final auditLogs = rawLogs.map((e) { // преобразование в список AuditEntry
      final uid   = (e['user_id'] as num?)?.toInt() ?? 0; // id сотрудника, если не найдено, то 0
      final tsRaw = e['timestamp'] as String? ?? ''; // время, если не найдено, то пустая строка
      String timeFmt = tsRaw; // время в формате dd.mm.yyyy hh:mm, если не найдено
      try { // преобразование в время в формате dd.mm.yyyy hh:mm
        final dt = DateTime.parse(tsRaw).toLocal(); // преобразование в DateTime
        final h  = dt.hour.toString().padLeft(2, '0'); // час
        final mn = dt.minute.toString().padLeft(2, '0'); // минута
        final d  = dt.day.toString().padLeft(2, '0'); // день
        final mo = dt.month.toString().padLeft(2, '0'); // месяц
        timeFmt = '$d.$mo.${dt.year}  $h:$mn'; // время в формате dd.mm.yyyy hh:mm
      } catch (_) {} // ошибка при преобразовании в время в формате dd.mm.yyyy hh:mm, _ - неиспользуемая переменная
      return AuditEntry( // создание модели записи аудита из JSON
        user:   userNames[uid] ?? 'ID:$uid', // имя сотрудника, если не найдено, то ID:$uid
        action: e['action'] as String? ?? '', // действие, если не найдено, то пустая строка
        time:   timeFmt, // время в формате dd.mm.yyyy hh:mm
      );
    }).toList(); // преобразование в список AuditEntry

    return LocationDetails._internal( // создание модели данных экрана выбранной локации из JSON
      location:     location, // локация
      users:        users, // сотрудники локации
      auditLogs:    auditLogs, // записи аудита
      rawAuditLogs: rawLogs, // сырые записи для точной фильтрации по user_id в UI
    );
  }
}