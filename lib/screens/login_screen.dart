import 'package:flutter/material.dart';

import '../services/app_repository.dart';
import '../theme/app_colors.dart';

/// Экран аутентификации: `AppRepository.login` (OAuth2 password flow на стороне API),
/// затем [onSuccess] — типично загрузка `loadAll()` и переход к Shell.
///
/// На code review: проверка `mounted` после async; ошибки сервера через `String?` из репозитория.
class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.repo,
    required this.onSuccess,
  });

  final AppRepository repo;
  final Future<void> Function() onSuccess;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _loginCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final err = await widget.repo.login(
      _loginCtrl.text.trim(),
      _passCtrl.text,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _loading = false;
        _error = err;
      });
      return;
    }
    await widget.onSuccess();
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isDark = c.isDark;

    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: c.accent.withOpacity(0.12),
                    shape: BoxShape.circle,
                    border: Border.all(color: c.accent.withOpacity(0.4), width: 1.5),
                  ),
                  child: Icon(Icons.thermostat_outlined, color: c.accent, size: 32),
                ),
                const SizedBox(height: 16),
                Text(
                  'TEMPERATURA.KZ',
                  style: TextStyle(
                    color: c.accent,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Система мониторинга',
                  style: TextStyle(color: c.textDim, fontSize: 13),
                ),
                const SizedBox(height: 32),
                Container(
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border),
                    boxShadow: isDark
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.07),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                  ),
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Вход в систему',
                        style: TextStyle(
                          color: c.textMain,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Field(
                        ctrl: _loginCtrl,
                        label: 'Логин',
                        icon: Icons.person_outline,
                        c: c,
                        onSubmit: _submit,
                      ),
                      const SizedBox(height: 12),
                      _Field(
                        ctrl: _passCtrl,
                        label: 'Пароль',
                        icon: Icons.lock_outline,
                        c: c,
                        obscure: _obscure,
                        onSubmit: _submit,
                        suffix: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            size: 18,
                            color: c.textDim,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: kRed.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: kRed.withOpacity(0.3)),
                          ),
                          child: Text(_error!, style: const TextStyle(color: kRed, fontSize: 13)),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: kCyan,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _loading ? null : _submit,
                          child: _loading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('Войти', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Общее поле входа: `onSubmitted` связан с `_submit` для UX на десктопе (Enter).
class _Field extends StatelessWidget {
  const _Field({
    required this.ctrl,
    required this.label,
    required this.icon,
    required this.c,
    this.obscure = false,
    this.suffix,
    this.onSubmit,
  });

  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final dynamic c;
  final bool obscure;
  final Widget? suffix;
  final VoidCallback? onSubmit;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      obscureText: obscure,
      style: TextStyle(color: c.textMain, fontSize: 14),
      onSubmitted: (_) => onSubmit?.call(),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: c.textDim, fontSize: 13),
        prefixIcon: Icon(icon, color: c.textDim, size: 18),
        suffixIcon: suffix,
        filled: true,
        fillColor: c.card2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kCyan, width: 1.5),
        ),
      ),
    );
  }
}
