import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/supabase_service.dart';

/// Penumpang: daftar/masuk email atau Google. Driver/admin: email + password
/// yang dibuat admin (Edge Function admin-create-driver).
/// Login WhatsApp OTP butuh provider SMS di Supabase Auth; belum dipasang di sini.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isSignUp = false;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on EnjoilyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final service = context.read<SupabaseService>();
    final messenger = ScaffoldMessenger.of(context);
    await _run(() async {
      if (_isSignUp) {
        await service.signUpPassenger(_email.text.trim(), _password.text, _name.text.trim());
        if (service.client.auth.currentSession == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Cek email untuk konfirmasi akun, lalu masuk.')),
          );
        }
      } else {
        await service.signInWithPassword(_email.text.trim(), _password.text);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.two_wheeler, size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 8),
                  Text('Enjoily Pangkalan',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text(_isSignUp ? 'Daftar sebagai penumpang' : 'Masuk ke akunmu',
                      textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 24),
                  if (_isSignUp) ...[
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Nama'),
                      validator: (v) => (v ?? '').trim().isEmpty ? 'Nama wajib diisi' : null,
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Email'),
                    validator: (v) => (v ?? '').contains('@') ? null : 'Email tidak valid',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Password'),
                    validator: (v) => (v ?? '').length < 6 ? 'Minimal 6 karakter' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Text(_isSignUp ? 'Daftar' : 'Masuk'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() => context.read<SupabaseService>().signInWithGoogle()),
                    icon: const Icon(Icons.g_mobiledata),
                    label: const Text('Lanjut dengan Google'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(_isSignUp ? 'Sudah punya akun? Masuk' : 'Penumpang baru? Daftar'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
