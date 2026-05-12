import 'dart:async'; // асинхронные операции, Future, Stream, etc.
import 'dart:convert'; // конвертер данных, JSON, XML, HTML, CSV, etc.
import 'dart:io'; // IO для Flutter, файловая система
import 'dart:typed_data'; // типы данных, Uint8List, etc.
import 'package:flutter/foundation.dart'; // Foundation для Flutter, основные классы и функции
import 'package:http/http.dart' as http; // HTTP клиент, HTTP запросы
import 'package:http_parser/http_parser.dart'; // парсер HTTP, парсинг HTTP запросов, Content-Type, etc.

import '../models/alarm_model.dart'; // модель аларма
import '../models/audit_entry.dart'; // модель аудита
import '../models/location_details.dart'; // модель деталей локации
import '../models/location_model.dart'; // модель локации
import '../models/sensor_model.dart'; // модель датчика
import '../models/user_role.dart'; // модель роли пользователя
import '../models/user_model.dart'; // модель пользователя

part 'app_repository/common.dart';
part 'app_repository/auth_profile.dart';
part 'app_repository/loaders.dart';
part 'app_repository/websocket.dart';
part 'app_repository/alarms_sensors.dart';
part 'app_repository/control_units.dart';
part 'app_repository/locations_reports.dart';
part 'app_repository/users_audit.dart';
part 'app_repository/parsing.dart';
part 'app_repository/http_helpers.dart';

const _kTimeout = Duration(seconds: 12);

class AppRepository {
  // класс для работы с данными
  String baseUrl = 'http://157.90.127.202:8000/api/v1'; // базовый URL
  String? token; // токен авторизации
  String? currentUser; // текущий пользователь
  String? currentUserFullName; // полное имя текущего пользователя
  String? currentUserEmail; // email текущего пользователя
  int? currentUserId; // id текущего пользователя
  int? currentLocationId; // id текущей локации
  UserRole role = UserRole.viewer; // роль текущего пользователя

  List<SensorModel> sensors = []; // список датчиков
  List<AlarmModel> alarms = []; // список алармов
  List<AuditEntry> audit = []; // список аудитов
  List<LocationModel> locations = []; // список локаций
  List<UserModel> subordinateUsers = []; // список подчиненных пользователей
  List<Map<String, dynamic>> controlUnits = []; // список ЦБУ

  WebSocket? _wsChannel; // активное WS-соединение
  void Function(int sensorId, double temp, double hum, bool isAlarm)?
  _wsCallback;
  void Function(int sensorId, double posX, double posY, int? groupId)?
  _wsPosCallback;
  bool _wsReconnecting = false;

  Timer? _heartbeatTimer; // handle периодического таймера
}
