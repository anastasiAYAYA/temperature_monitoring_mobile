import 'package:flutter/material.dart';
import 'app.dart';

export 'app.dart';

void main() {
  runApp(const TemperaturaApp());
}
/*
import 'package:flutter/material.dart';
import 'app.dart';

export 'app.dart';

void main() {
  runApp(const TemperaturaApp());
}
import 'package:flutter/material.dart';
import 'app.dart';

export 'app.dart';

void main() {
  runApp(const TemperaturaApp());
}
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const TemperaturaApp());

enum UserRole { admin, editor, viewer }
enum SensorState { normal, warning, critical }
enum AlarmStatus { newAlarm, acknowledged, resolved }

class AppColors {
  static const background = Color(0xFF0A0A0A);
  static const card = Color(0xFF121316);
  static const primary = Color(0xFFFFD550);
  static const accentBrown = Color(0xFF312C1C);
  static const danger = Color(0xFFFF5252);
  static const success = Color(0xFF01E676);
  static const info = Color(0xFF07BCD4);
}

class TemperaturaApp extends StatelessWidget {
  const TemperaturaApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TEMPERATURA.KZ',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: const ColorScheme.dark(primary: AppColors.primary, surface: AppColors.card),
      ),
      home: const RootPage(),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  final repo = AppRepository();
  int tab = 0;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => showLoginDialog());
  }

  Future<void> showLoginDialog() async {
    final login = TextEditingController();
    final pass = TextEditingController();
    String? localError;
    bool inProgress = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Авторизация'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: login, decoration: const InputDecoration(labelText: 'Логин')),
                TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль')),
                if (localError != null) ...[
                  const SizedBox(height: 8),
                  Text(localError!, style: const TextStyle(color: AppColors.danger)),
                ],
              ],
            ),
            actions: [
              FilledButton(
                onPressed: inProgress
                    ? null
                    : () async {
                        setDialogState(() => inProgress = true);
                        final err = await repo.login(login.text.trim(), pass.text);
                        if (err != null) {
                          setDialogState(() {
                            localError = err;
                            inProgress = false;
                          });
                          return;
                        }
                        if (!mounted || !ctx.mounted) return;
                        Navigator.pop(ctx);
                        await reload();
                      },
                child: const Text('Войти'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> reload() async {
    setState(() {
      loading = true;
      error = null;
    });
    final err = await repo.loadAll();
    if (!mounted) return;
    setState(() {
      loading = false;
      error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(repo: repo),
      SensorsScreen(repo: repo),
      ReportsScreen(repo: repo),
      NotificationsScreen(repo: repo, onRefresh: reload),
      SettingsScreen(repo: repo, onRefresh: reload),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('TEMPERATURA.KZ'),
        actions: [
          IconButton(onPressed: loading ? null : reload, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: loading
                ? null
                : () async {
                    repo.logout();
                    await showLoginDialog();
                  },
            icon: const Icon(Icons.logout),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Center(child: Text(repo.role.name, style: const TextStyle(color: AppColors.primary))),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : repo.token == null
              ? Center(
                  child: FilledButton(onPressed: showLoginDialog, child: const Text('Авторизоваться')),
                )
              : Column(
                  children: [
                    if (error != null)
                      Container(
                        width: double.infinity,
                        color: AppColors.danger.withValues(alpha: 0.2),
                        padding: const EdgeInsets.all(8),
                        child: Text(error!, style: const TextStyle(color: AppColors.danger)),
                      ),
                    Expanded(child: screens[tab]),
                  ],
                ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: 'Главная'),
          NavigationDestination(icon: Icon(Icons.sensors), label: 'Датчики'),
          NavigationDestination(icon: Icon(Icons.file_open), label: 'Отчеты'),
          NavigationDestination(icon: Icon(Icons.notifications), label: 'Увед.'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Настройки'),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.repo});
  final AppRepository repo;
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Система мониторинга помещений', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          color: AppColors.card,
          child: SizedBox(
            height: 190,
            child: Stack(
              children: [
                Positioned.fill(child: Container(margin: const EdgeInsets.all(8), color: Colors.black)),
                ...repo.sensors.map((s) => Positioned(left: s.x, top: s.y, child: _SensorDot(state: s.state))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...repo.sensors.take(3).map((s) => ListTile(title: Text(s.name), subtitle: Text('${s.temperature}°C / ${s.humidity}%'))),
      ],
    );
  }
}

class SensorsScreen extends StatefulWidget {
  const SensorsScreen({super.key, required this.repo});
  final AppRepository repo;
  @override
  State<SensorsScreen> createState() => _SensorsScreenState();
}

class _SensorsScreenState extends State<SensorsScreen> {
  String location = 'Все';
  String period = 'День';
  SensorModel? selected;
  bool loadingHistory = false;

  @override
  Widget build(BuildContext context) {
    final allLocations = ['Все', ...widget.repo.locations];
    final sensors = location == 'Все' ? widget.repo.sensors : widget.repo.sensors.where((e) => e.location == location).toList();
    final active = selected ?? (sensors.isEmpty ? null : sensors.first);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        DropdownButtonFormField<String>(
          initialValue: location,
          items: allLocations.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() => location = v ?? location),
        ),
        ...sensors.map((s) => ListTile(
              title: Text(s.name),
              subtitle: Text('${s.location} • ${s.temperature.toStringAsFixed(1)}°C'),
              onTap: () async {
                setState(() {
                  selected = s;
                  loadingHistory = true;
                });
                await widget.repo.loadHistory(s.id, period);
                if (mounted) setState(() => loadingHistory = false);
              },
            )),
        if (active != null) ...[
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'День', label: Text('День')),
              ButtonSegment(value: 'Неделя', label: Text('Неделя')),
              ButtonSegment(value: 'Месяц', label: Text('Месяц')),
            ],
            selected: {period},
            onSelectionChanged: (v) async {
              setState(() => period = v.first);
              await widget.repo.loadHistory(active.id, period);
              if (mounted) setState(() {});
            },
          ),
          Card(
            color: AppColors.card,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: loadingHistory
                  ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
                  : _LineChart(points: active.points),
            ),
          )
        ]
      ],
    );
  }
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.repo});
  final AppRepository repo;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  String format = 'xlsx';
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: AppColors.card,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: _LineChart(points: widget.repo.sensors.expand((e) => e.points.take(4)).toList(), color: AppColors.info),
          ),
        ),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'xlsx', label: Text('CSV/XLSX')),
            ButtonSegment(value: 'pdf', label: Text('PDF')),
          ],
          selected: {format},
          onSelectionChanged: (v) => setState(() => format = v.first),
        ),
        FilledButton(
          onPressed: widget.repo.sensors.isEmpty
              ? null
              : () async {
                  final bytes = await widget.repo.downloadReport(widget.repo.sensors.first.id, format);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(bytes == null ? 'Ошибка загрузки отчета' : 'Отчет получен (${bytes.length} байт)')),
                  );
                },
          child: const Text('Скачать отчет'),
        ),
      ],
    );
  }
}

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.repo, required this.onRefresh});
  final AppRepository repo;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: repo.alarms
          .map(
            (a) => Card(
              color: AppColors.card,
              child: ListTile(
                title: Text(a.title),
                subtitle: Text(a.description),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    TextButton(
                      onPressed: repo.role == UserRole.viewer
                          ? null
                          : () async {
                              final err = await repo.updateAlarm(a.id, 'acknowledged', 'Взято в работу');
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'OK')));
                              await onRefresh();
                            },
                      child: const Text('В работу'),
                    ),
                    TextButton(
                      onPressed: repo.role == UserRole.viewer
                          ? null
                          : () async {
                              final err = await repo.updateAlarm(a.id, 'resolved', 'Решено оператором');
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'OK')));
                              await onRefresh();
                            },
                      child: const Text('Решено'),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.repo, required this.onRefresh});
  final AppRepository repo;
  final Future<void> Function() onRefresh;
  @override
  Widget build(BuildContext context) {
    final urlCtrl = TextEditingController(text: repo.baseUrl);
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        ListTile(title: Text(repo.currentUser ?? '-'), subtitle: Text('Роль: ${repo.role.name}')),
        TextField(controller: urlCtrl, decoration: const InputDecoration(labelText: 'Base URL API')),
        FilledButton(
          onPressed: () async {
            repo.baseUrl = urlCtrl.text.trim();
            await onRefresh();
          },
          child: const Text('Применить'),
        ),
        const SizedBox(height: 8),
        ...repo.audit.map((e) => ListTile(title: Text(e.action), subtitle: Text('${e.user} • ${e.time}'))),
      ],
    );
  }
}

class _SensorDot extends StatelessWidget {
  const _SensorDot({required this.state});
  final SensorState state;
  @override
  Widget build(BuildContext context) {
    final color = state == SensorState.critical
        ? AppColors.danger
        : state == SensorState.warning
            ? AppColors.primary
            : AppColors.success;
    return Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle));
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.points, this.color = AppColors.primary});
  final List<double> points;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 120, child: CustomPaint(painter: _LinePainter(points, color)));
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.points, this.color);
  final List<double> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final minV = points.reduce(min);
    final maxV = points.reduce(max);
    final span = max(maxV - minV, 0.001);
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = i * size.width / max(1, points.length - 1);
      final y = size.height - ((points[i] - minV) / span) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _LinePainter oldDelegate) => oldDelegate.points != points || oldDelegate.color != color;
}

class SensorModel {
  SensorModel({
    required this.id,
    required this.name,
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
  final String location;
  final double temperature;
  final double humidity;
  final SensorState state;
  final double x;
  final double y;
  List<double> points;
}

class AlarmModel {
  AlarmModel({required this.id, required this.title, required this.description, required this.status});
  final int id;
  final String title;
  final String description;
  final AlarmStatus status;
}

class AuditEntry {
  AuditEntry({required this.user, required this.action, required this.time});
  final String user;
  final String action;
  final String time;
}

class AppRepository {
  String baseUrl = 'http://localhost:8000/api/v1';
  String? token;
  String? currentUser;
  UserRole role = UserRole.viewer;
  List<SensorModel> sensors = [];
  List<String> locations = [];
  List<AlarmModel> alarms = [];
  List<AuditEntry> audit = [];

  Future<String?> login(String username, String password) async {
    try {
      final r = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': username, 'password': password},
      );
      if (r.statusCode != 200) return parseError(r.body) ?? 'Ошибка входа';
      token = (jsonDecode(r.body) as Map<String, dynamic>)['access_token'] as String?;
      final me = await get('/users/me');
      if (me.statusCode == 200) {
        final data = jsonDecode(me.body) as Map<String, dynamic>;
        currentUser = data['username'] as String?;
        role = parseRole((data['role'] as String?) ?? 'viewer');
      }
      return null;
    } catch (e) {
      return 'Сервер недоступен: $e';
    }
  }

  Future<String?> loadAll() async {
    if (token == null) return 'Нет токена';
    try {
      final s = await get('/sensors/');
      if (s.statusCode != 200) return parseError(s.body) ?? 'Не удалось получить датчики';
      final sensorsJson = jsonDecode(s.body) as List<dynamic>;
      sensors = sensorsJson.map((e) => sensorFromJson(e as Map<String, dynamic>)).toList();
      locations = sensors.map((e) => e.location).toSet().toList();

      final a = await get('/alarms/');
      if (a.statusCode == 200) {
        alarms = (jsonDecode(a.body) as List<dynamic>).map((e) => alarmFromJson(e as Map<String, dynamic>)).toList();
      }

      final l = await get('/users/audit-logs?skip=0&limit=20');
      if (l.statusCode == 200) {
        audit = (jsonDecode(l.body) as List<dynamic>)
            .map(
              (e) => AuditEntry(
                user: 'ID ${(e as Map<String, dynamic>)['user_id']}',
                action: e['action'] as String? ?? '',
                time: (e['timestamp'] as String? ?? '').replaceFirst('T', ' '),
              ),
            )
            .toList();
      }
      return null;
    } catch (e) {
      return '$e';
    }
  }

  Future<void> loadHistory(int sensorId, String period) async {
    final endpoint = period == 'День'
        ? '/telemetry/$sensorId/last-24h'
        : '/telemetry/$sensorId/history?limit=${period == 'Неделя' ? 120 : 240}';
    final r = await get(endpoint);
    if (r.statusCode != 200) return;
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final points = ((data['measurements'] as List<dynamic>?) ?? [])
        .map((e) => ((e as Map<String, dynamic>)['temperature'] as num?)?.toDouble())
        .whereType<double>()
        .toList();
    final i = sensors.indexWhere((e) => e.id == sensorId);
    if (i >= 0 && points.isNotEmpty) sensors[i].points = points;
  }

  Future<String?> updateAlarm(int alarmId, String status, String comment) async {
    final r = await patch('/alarms/$alarmId', {'status': status, 'comment': comment});
    if (r.statusCode == 200) return null;
    return parseError(r.body) ?? 'Ошибка изменения';
  }

  Future<List<int>?> downloadReport(int sensorId, String format) async {
    final r = await get('/reports/download/$sensorId?format=$format');
    return r.statusCode == 200 ? r.bodyBytes : null;
  }

  void logout() {
    token = null;
    currentUser = null;
    sensors = [];
    alarms = [];
    audit = [];
    role = UserRole.viewer;
  }

  SensorModel sensorFromJson(Map<String, dynamic> j) {
    final id = (j['id'] as num?)?.toInt() ?? 0;
    final temp = 19 + Random(id + 1).nextDouble() * 10;
    final hum = 22 + Random(id + 2).nextDouble() * 15;
    final state = (j['is_online'] == false)
        ? SensorState.critical
        : (((j['battery_level'] as num?)?.toInt() ?? 100) < 25 ? SensorState.warning : SensorState.normal);
    return SensorModel(
      id: id,
      name: (j['name'] as String?) ?? 'Датчик',
      location: 'Локация #${(j['group_id'] as num?)?.toInt() ?? 0}',
      temperature: temp,
      humidity: hum,
      state: state,
      x: ((j['pos_x'] as num?)?.toDouble() ?? Random().nextDouble() * 210).clamp(4, 220),
      y: ((j['pos_y'] as num?)?.toDouble() ?? Random().nextDouble() * 130).clamp(4, 150),
      points: [temp - 1, temp - 0.5, temp, temp + 0.3, temp + 0.1],
    );
  }

  AlarmModel alarmFromJson(Map<String, dynamic> j) {
    final st = switch (j['status']) {
      'acknowledged' => AlarmStatus.acknowledged,
      'resolved' => AlarmStatus.resolved,
      _ => AlarmStatus.newAlarm
    };
    return AlarmModel(
      id: (j['id'] as num?)?.toInt() ?? 0,
      title: (j['alarm_type'] as String?) ?? 'Событие',
      description: (j['description'] as String?) ?? '',
      status: st,
    );
  }

  UserRole parseRole(String value) {
    switch (value) {
      case 'admin':
        return UserRole.admin;
      case 'editor':
        return UserRole.editor;
      default:
        return UserRole.viewer;
    }
  }

  String? parseError(String body) {
    try {
      final d = jsonDecode(body) as Map<String, dynamic>;
      return d['detail'] as String?;
    } catch (_) {
      return null;
    }
  }

  Future<http.Response> get(String path) =>
      http.get(Uri.parse('$baseUrl$path'), headers: {'Authorization': 'Bearer $token'});

  Future<http.Response> patch(String path, Map<String, dynamic> body) => http.patch(
        Uri.parse('$baseUrl$path'),
        headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
}
*/
