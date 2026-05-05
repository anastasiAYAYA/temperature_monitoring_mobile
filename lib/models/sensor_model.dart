//final - неизменяемые значения, this. - ссылка на свойство класса, required - обязательное значение,
// null - значение по умолчанию, const - константа, enum - перечисление
enum SensorState { normal, warning, critical } // состояние датчика, список фиксированных значений

class SensorModel {
  SensorModel({ // конструктор модели датчика
    required this.id, // id датчика
    required this.name, // название датчика
    required this.groupId, // id группы датчиков
    required this.location, // название локации
    required this.temperature, // температура
    required this.humidity, // влажность
    required this.state, // состояние датчика
    required this.x, // x координата
    required this.y, // y координата
    required this.points, // точки истории температуры
    this.humidityPoints      = const [], // точки истории влажности
    this.timestamps          = const [], // временные метки для точек истории
    this.controlUnitId, // id блока управления
    this.internalId, // внутренний id датчика
    this.alarmDelaySeconds   = 0, // задержка тревоги, по умолчанию 0
    this.powerStatus, // статус питания
    this.batteryLevel, // уровень заряда батареи
    this.simBalance, // баланс SIM-карты
    this.gsmSignal, // уровень сигнала GSM
    this.isOnline            = true, // статус онлайн, по умолчанию true
    this.lastSeen, // время последнего обновления
  });

  final int    id; // id датчика
  final String name; // название датчика
  final int    groupId; // id группы датчиков
  final String location; // название локации
  final double temperature; // температура
  final double humidity; // влажность
  final SensorState state; // состояние датчика
  double x; // x координата
  double y; // y координата

  final int? controlUnitId; // id блока управления
  final String? internalId; // внутренний id датчика
  final int alarmDelaySeconds; // задержка тревоги

  // точки истории температуры (°C)
  List<double> points;

  // точки истории влажности (%)
  List<double> humidityPoints;

  // временные метки для точек истории
  List<DateTime> timestamps;

  double? warningMinTemp; // минимальная температура для предупреждения
  double? warningMaxTemp; // максимальная температура для предупреждения
  double? alarmMinTemp; // минимальная температура для тревоги
  double? alarmMaxTemp; // максимальная температура для тревоги

  double? warningMinHum; // минимальная влажность для предупреждения
  double? warningMaxHum; // максимальная влажность для предупреждения
  double? alarmMinHum; // минимальная влажность для тревоги
  double? alarmMaxHum; // максимальная влажность для тревоги

  final String? powerStatus; // статус питания
  final int? batteryLevel; // уровень заряда батареи
  final double? simBalance; // баланс SIM-карты
  final int? gsmSignal; // уровень сигнала GSM
  final bool isOnline; // статус онлайн
  final String? lastSeen; // время последнего обновления

  bool get isAcPowered => powerStatus == 'mains'; // статус питания, true если питание от сети, false если от батареи
  int get gsmBars => (gsmSignal ?? 0).clamp(0, 5); // уровень сигнала GSM, 0-5 баров

  String get gsmLabel => gsmSignal == null ? 'Нет данных' : switch (gsmBars) { // уровень сигнала GSM, 'Нет данных' если нет данных
    5 => 'Отличный', // 5 баров
    4 => 'Хороший', // 4 бара
    3 => 'Средний', // 3 бара
    2 => 'Слабый', // 2 бара
    1 => 'Очень слабый', // 1 бара
    _ => 'Нет сигнала', // нет данных
  }; // если не найдено, то 'Нет сигнала', _ - неиспользуемая переменная
}

class SensorLiveData { // модель данных для live-данных датчика
  final double temperature; // температура
  final double humidity; // влажность
  final DateTime timestamp; // время

  SensorLiveData({ // конструктор модели данных для live-данных датчика
    required this.temperature, // температура
    required this.humidity, // влажность
    required this.timestamp, // время
  });

  factory SensorLiveData.fromJson(Map<String, dynamic> j) => SensorLiveData( // фабричный метод для создания модели данных для live-данных датчика из JSON
    temperature: (j['temperature'] as num?)?.toDouble() ?? 0.0, // температура, если не найдено, то 0.0
    humidity:    (j['humidity']    as num?)?.toDouble() ?? 0.0, // влажность, если не найдено, то 0.0
    timestamp: j['timestamp'] != null // время, если не найдено, то текущее время, если найдено, то преобразование строки в DateTime
        ? DateTime.parse(j['timestamp'] as String) // преобразование строки в DateTime
        : DateTime.now(), // текущее время
  );
}