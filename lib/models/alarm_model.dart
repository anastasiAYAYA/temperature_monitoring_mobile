enum AlarmStatus { newAlarm, acknowledged, resolved }

/// Уровень критичности тревоги
enum AlarmSeverity { warning, critical, info }

class AlarmModel {
  AlarmModel({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    this.sensorId,
    this.severity    = AlarmSeverity.warning,
    this.alarmType,
    this.timestamp,
    this.comment,
    this.resolvedAt,
    this.resolvedById,
  });

  final int    id;
  final String title;
  final String description;
  final AlarmStatus status;

  /// ID датчика, с которого пришла тревога (sensor_id)
  final int? sensorId;

  /// Уровень критичности (severity): "warning" | "critical"
  final AlarmSeverity severity;

  /// Тип тревоги (alarm_type): "temperature" | "humidity" | "connection_lost" | "low_battery"
  final String? alarmType;

  /// Время возникновения (timestamp)
  final String? timestamp;

  /// Комментарий оператора (user_comment)
  final String? comment;

  /// Время закрытия (resolved_at)
  final String? resolvedAt;

  /// ID пользователя, закрывшего тревогу (resolved_by_id)
  final int? resolvedById;
}