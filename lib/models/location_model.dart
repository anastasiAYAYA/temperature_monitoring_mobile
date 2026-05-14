//final - неизменяемые значения, this. - ссылка на свойство класса, required - обязательное значение,
// null - значение по умолчанию, const - константа, enum - перечисление
class LocationModel {
  LocationModel({ // конструктор модели локации
    required this.id, // id локации
    required this.name, // название локации
    this.imageUrl, // URL изображения локации
    this.pushNotificationsEnabled = true, // push-уведомления включены по умолчанию (PATCH /notifications/location-preferences/{id})
    this.telegramNotificationsEnabled = true, // Telegram-уведомления включены по умолчанию (PATCH /notifications/location-preferences/{id})
  });

  final int id; // id локации
  final String name; // название локации
  final String? imageUrl; // URL изображения локации
  final bool pushNotificationsEnabled; // флаг push-уведомлений текущего пользователя по локации
  final bool telegramNotificationsEnabled; // флаг Telegram-уведомлений текущего пользователя по локации

  /// Удобный геттер: считается заглушённой если оба канала отключены
  bool get notificationsEnabled =>
      pushNotificationsEnabled || telegramNotificationsEnabled;
}