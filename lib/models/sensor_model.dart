enum SensorState { normal, warning, critical }

class SensorModel {
  SensorModel({
    required this.id,
    required this.name,
    required this.groupId,
    required this.location,
    required this.temperature,
    required this.humidity,
    required this.state,
    required this.x,
    required this.y,
    required this.points,
  });

  final int id;
  final String name;
  final int groupId;
  final String location;
  final double temperature;
  final double humidity;
  final SensorState state;
  final double x;
  final double y;
  List<double> points;
  double? warningMinTemp;
  double? warningMaxTemp;
  double? alarmMinTemp;
  double? alarmMaxTemp;
}
