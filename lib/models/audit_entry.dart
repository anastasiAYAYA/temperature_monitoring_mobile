class AuditEntry {
  AuditEntry({
    required this.user,
    required this.action,
    required this.time,
  });

  final String user;
  final String action;
  final String time;
}
