//final - неизменяемые значения, this. - ссылка на свойство класса, required - обязательное значение,
// null - значение по умолчанию, const - константа, enum - перечисление
class AuditEntry { // модель записи аудита
  AuditEntry({ // конструктор модели записи аудита
    required this.user, // пользователь
    required this.action, // действие
    required this.time, // время
  });

  final String user; // пользователь
  final String action; // действие
  final String time; // время
}
