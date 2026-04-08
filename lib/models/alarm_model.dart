enum AlarmStatus { newAlarm, acknowledged, resolved }

class AlarmModel {
  AlarmModel({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
  });

  final int id;
  final String title;
  final String description;
  final AlarmStatus status;
}
