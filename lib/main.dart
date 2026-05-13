import 'package:flutter/material.dart';
import 'app.dart';
import 'services/push_notification_service.dart';

export 'app.dart';

Future<void> main() async {
  // функция для запуска приложения
  WidgetsFlutterBinding.ensureInitialized();
  await PushNotificationService.initialize();
  runApp(const TemperaturaApp()); // запуск приложения
}
