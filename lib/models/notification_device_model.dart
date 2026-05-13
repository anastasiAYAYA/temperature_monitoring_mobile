class NotificationDeviceModel {
  const NotificationDeviceModel({
    required this.id,
    required this.token,
    required this.provider,
    required this.platform,
    required this.enabled,
    this.deviceName,
    this.lastSuccessAt,
    this.lastError,
  });

  final int id;
  final String token;
  final String provider;
  final String platform;
  final bool enabled;
  final String? deviceName;
  final String? lastSuccessAt;
  final String? lastError;
}
