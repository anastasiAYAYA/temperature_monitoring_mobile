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
    this.humidityPoints      = const [],
    this.timestamps          = const [],
    this.controlUnitId,
    this.internalId,
    this.alarmDelaySeconds   = 0,
    this.powerStatus,
    this.batteryLevel,
    this.simBalance,
    this.gsmSignal,
    this.isOnline            = true,
    this.lastSeen,
  });

  final int    id;
  final String name;
  final int    groupId;
  final String location;
  final double temperature;
  final double humidity;
  final SensorState state;
  double x;
  double y;

  final int? controlUnitId;
  final String? internalId;
  final int alarmDelaySeconds;

  /// Точки истории температуры (°C)
  List<double> points;

  /// Точки истории влажности (%)
  List<double> humidityPoints;

  /// Временные метки для точек истории
  List<DateTime> timestamps;

  double? warningMinTemp;
  double? warningMaxTemp;
  double? alarmMinTemp;
  double? alarmMaxTemp;

  double? warningMinHum;
  double? warningMaxHum;
  double? alarmMinHum;
  double? alarmMaxHum;

  final String? powerStatus;
  final int? batteryLevel;
  final double? simBalance;
  final int? gsmSignal;
  final bool isOnline;
  final String? lastSeen;

  bool get isAcPowered => powerStatus == 'mains';
  int get gsmBars => (gsmSignal ?? 0).clamp(0, 5);

  String get gsmLabel {
    if (gsmSignal == null) return 'Нет данных';
    return switch (gsmBars) {
      5 => 'Отличный',
      4 => 'Хороший',
      3 => 'Средний',
      2 => 'Слабый',
      1 => 'Очень слабый',
      _ => 'Нет сигнала',
    };
  }
}

class SensorLiveData {
  final double temperature;
  final double humidity;
  final DateTime timestamp;

  SensorLiveData({
    required this.temperature,
    required this.humidity,
    required this.timestamp,
  });

  factory SensorLiveData.fromJson(Map<String, dynamic> j) => SensorLiveData(
        temperature: (j['temperature'] as num?)?.toDouble() ?? 0.0,
        humidity:    (j['humidity']    as num?)?.toDouble() ?? 0.0,
        timestamp: j['timestamp'] != null
            ? DateTime.parse(j['timestamp'] as String)
            : DateTime.now(),
      );
}