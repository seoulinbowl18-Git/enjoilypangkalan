import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/supabase_service.dart';
import '../ui/enjoily_style.dart';

/// Penumpang: masuk/daftar dengan Google atau kode OTP WhatsApp (akun baru
/// otomatis dibuat). Driver/admin: email + password yang dibuat admin
/// (Edge Function admin-create-driver).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final SupabaseService _service = context.read<SupabaseService>();

  final _phone = TextEditingController();
  final _otp = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _otpSent = false;
  bool _staffLogin = false;
  bool _busy = false;

  @override
  void dispose() {
    _phone.dispose();
    _otp.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Berhasil login → AuthGate di main.dart pindah ke dashboard sendiri.
  Future<bool> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      return true;
    } on EnjoilyException catch (e) {
      _toast(e.message);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendOtp() async {
    if (_phone.text.replaceAll(RegExp(r'\D'), '').length < 9) {
      _toast('Masukkan nomor WhatsApp yang valid');
      return;
    }
    if (await _run(() => _service.sendWhatsAppOtp(_phone.text))) {
      setState(() => _otpSent = true);
      _toast('Kode OTP dikirim ke WhatsApp ${SupabaseService.normalizePhone(_phone.text)}');
    }
  }

  Future<void> _verifyOtp() async {
    if (_otp.text.trim().length != 6) {
      _toast('Kode OTP terdiri dari 6 angka');
      return;
    }
    await _run(() => _service.verifyPhoneOtp(_phone.text, _otp.text.trim()));
  }

  Future<void> _staffSignIn() async {
    if (!_email.text.contains('@') || _password.text.isEmpty) {
      _toast('Isi email dan password');
      return;
    }
    await _run(() => _service.signInWithPassword(_email.text.trim(), _password.text));
  }

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 14,
              children: [
                Center(child: _Logo(c: c)),
                EnjH2(_staffLogin ? 'Masuk driver / admin' : 'Masuk atau daftar', center: true),
                EnjSub(
                  _staffLogin
                      ? 'Pakai email dan password dari admin pangkalan.'
                      : 'Akun penumpang baru otomatis dibuat saat pertama masuk.',
                  center: true,
                ),
                if (_staffLogin) _buildStaffCard() else ..._buildPassengerCards(c),
                TextButton(
                  onPressed: _busy ? null : () => setState(() => _staffLogin = !_staffLogin),
                  child: Text(
                    _staffLogin ? 'Penumpang? Masuk dengan Google / WhatsApp' : 'Driver atau admin? Masuk dengan email',
                    style: TextStyle(fontWeight: FontWeight.w700, color: c.accent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPassengerCards(EnjColors c) {
    return [
      EnjCard(
        children: [
          OutlinedButton.icon(
            onPressed: _busy ? null : () => _run(_service.signInWithGoogle),
            icon: const Text('G',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFFEA4335))),
            label: const Text('Lanjut dengan Google'),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.ink,
              side: BorderSide(color: c.line, width: 1.5),
              visualDensity: VisualDensity.standard,
              padding: const EdgeInsets.all(14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              textStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                fontFamily: Theme.of(context).textTheme.labelLarge?.fontFamily,
              ),
            ),
          ),
          Row(
            spacing: 8,
            children: [
              Expanded(child: Divider(color: c.line)),
              EnjSub('ATAU'),
              Expanded(child: Divider(color: c.line)),
            ],
          ),
          const Row(
            spacing: 10,
            children: [EnjAva('💬', size: 34, fontSize: 16), EnjB('WhatsApp OTP')],
          ),
          if (!_otpSent) ...[
            EnjField(
              controller: _phone,
              hint: 'Nomor WhatsApp, mis. 0812 3456 7890',
              keyboardType: TextInputType.phone,
              onSubmitted: (_) => _sendOtp(),
            ),
            EnjButton(_busy ? 'Mengirim…' : 'Kirim kode OTP', onPressed: _busy ? null : _sendOtp),
          ] else ...[
            EnjSub.rich([
              const TextSpan(text: 'Kode 6 angka dikirim ke '),
              enjBold(SupabaseService.normalizePhone(_phone.text)),
            ]),
            EnjField(
              controller: _otp,
              hint: 'Masukkan 6 digit kode OTP',
              numeric: true,
              onSubmitted: (_) => _verifyOtp(),
            ),
            EnjButton(_busy ? 'Memeriksa…' : 'Verifikasi & masuk', onPressed: _busy ? null : _verifyOtp),
            EnjChips(
              children: [
                EnjChip('Ganti nomor', onTap: () => setState(() {
                      _otpSent = false;
                      _otp.clear();
                    })),
                EnjChip('Kirim ulang kode', onTap: () {
                  if (!_busy) _sendOtp();
                }),
              ],
            ),
          ],
        ],
      ),
    ];
  }

  Widget _buildStaffCard() {
    return EnjCard(
      children: [
        EnjField(controller: _email, hint: 'Email', keyboardType: TextInputType.emailAddress),
        EnjField(controller: _password, hint: 'Password', obscure: true, onSubmitted: (_) => _staffSignIn()),
        EnjButton(_busy ? 'Masuk…' : 'Masuk', onPressed: _busy ? null : _staffSignIn),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.c});

  final EnjColors c;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(22)),
      child: Text.rich(
        TextSpan(
          children: const [
            TextSpan(text: 'En'),
            TextSpan(text: 'joily', style: TextStyle(color: EnjColors.sun)),
            TextSpan(text: ' Pangkalan'),
          ],
          style: TextStyle(color: c.bg, fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
    );
  }
}
