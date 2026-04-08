import 'package:flutter/material.dart';

import '../services/app_repository.dart';
import '../theme/app_colors.dart';

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
  final loginCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  String? error;
  bool loading = false;

  @override
  void dispose() {
    loginCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Colors.black,
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Card(
              color: AppColors.card,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('TEMPERATURA.KZ', style: TextStyle(color: AppColors.primary, fontSize: 24)),
                    const SizedBox(height: 20),
                    TextField(controller: loginCtrl, decoration: const InputDecoration(labelText: 'Логин')),
                    const SizedBox(height: 10),
                    TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Пароль')),
                    if (error != null) ...[
                      const SizedBox(height: 10),
                      Text(error!, style: const TextStyle(color: AppColors.danger)),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: loading
                            ? null
                            : () async {
                                setState(() {
                                  loading = true;
                                  error = null;
                                });
                                final err = await widget.repo.login(loginCtrl.text.trim(), passCtrl.text);
                                if (err != null) {
                                  setState(() {
                                    loading = false;
                                    error = err;
                                  });
                                  return;
                                }
                                await widget.onSuccess();
                                if (!mounted) return;
                                setState(() => loading = false);
                              },
                        child: Text(loading ? 'Вход...' : 'Войти'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
