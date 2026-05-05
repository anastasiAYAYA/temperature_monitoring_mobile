//final - неизменяемые значения, this. - ссылка на свойство класса, required - обязательное значение,
// null - значение по умолчанию, const - константа, enum - перечисление

enum AlarmStatus { newAlarm, acknowledged, resolved } // статус тревоги, список фиксированных значений

enum AlarmSeverity { warning, critical, info } // уровень критичности, список фиксированных значений

class AlarmModel { // модель тревоги
  AlarmModel({ // конструктор модели тревоги
    required this.id, // id тревоги
    required this.title, // заголовок тревоги
    required this.description, // описание тревоги
    required this.status, // статус тревоги
    this.sensorId, // id датчика, с которого пришла тревога
    this.severity    = AlarmSeverity.warning, // уровень критичности, по умолчанию warning
    this.alarmType, // тип тревоги, null по умолчанию
    this.timestamp, // время возникновения, null по умолчанию
    this.comment, // комментарий оператора, null по умолчанию
    this.resolvedAt, // время закрытия, null по умолчанию
    this.resolvedById, // id пользователя, закрывшего тревогу, null по умолчанию
  });

  final int    id; // id тревоги
  final String title; // заголовок тревоги
  final String description; // описание тревоги
  final AlarmStatus status; // статус тревоги

  // ID датчика, с которого пришла тревога
  final int? sensorId;

  // Уровень критичности: "warning" | "critical"
  final AlarmSeverity severity;

  // Тип тревоги: "temperature" | "humidity" | "connection_lost" | "low_battery"
  final String? alarmType;

  // Время возникновения
  final String? timestamp;

  // Комментарий оператора
  final String? comment;

  // Время закрытия
  final String? resolvedAt;

  // ID пользователя, закрывшего тревогу
  final int? resolvedById;
}