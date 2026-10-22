import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/dashboard.dart';
import 'screens/login_screen.dart';
import 'services/demo_service.dart';
import 'services/supabase_service.dart';
import 'ui/enjoily_style.dart';

// Supabase Dashboard → Project Settings → API.
// Anon key aman ada di aplikasi (dibatasi RLS). JANGAN taruh service_role key di sini.
// Bisa juga diisi saat run:
//   flutter run -d chrome --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://tbjcfdwkqdrwsnzzbhpo.supabase.co',
);
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRiamNmZHdrcWRyd3NuenpiaHBvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTA4MjU2OTQsImV4cCI6MjEwNjQwMTY5NH0.EhGjCLDpRPqXBikylSOW5tonJ1Az1D97tkgxhetK7do',
);

// Mode demo (SEMENTARA): tanpa halaman login, langsung ke Dashboard dengan data
// contoh di memori (lib/services/demo_service.dart). Untuk login & Supabase asli:
//   flutter run -d chrome --dart-define=DEMO=false
const demoMode = bool.fromEnvironment('DEMO', defaultValue: true);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Anon key (JWT lama) maupun publishable key (sb_publishable_...) sama-sama diterima.
  if (!demoMode) {
    await Supabase.initialize(url: supabaseUrl, publishableKey: supabaseAnonKey);
  }
  runApp(
    Provider<SupabaseService>(
      create: (_) => demoMode ? DemoService() : SupabaseService(),
      child: const EnjoilyApp(),
    ),
  );
}

class EnjoilyApp extends StatelessWidget {
  const EnjoilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Dibundel di pubspec.yaml agar semua ketebalan (400–800) ikut terpakai.
    const font = 'PlusJakartaSans';
    return MaterialApp(
      title: 'Enjoily Pangkalan',
      debugShowCheckedModeBanner: false,
      theme: enjoilyTheme(Brightness.light, font),
      darkTheme: enjoilyTheme(Brightness.dark, font),
      home: demoMode ? const _RoleRouter() : const AuthGate(),
    );
  }
}

/// Belum login → LoginScreen. Sudah login → halaman sesuai users.role.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.read<SupabaseService>();
    return StreamBuilder<AuthState>(
      stream: service.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = service.client.auth.currentSession;
        if (session == null) return const LoginScreen();
        return _RoleRouter(key: ValueKey(session.user.id));
      },
    );
  }
}

class _RoleRouter extends StatelessWidget {
  const _RoleRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final service = context.read<SupabaseService>();
    return StreamBuilder<Map<String, dynamic>?>(
      stream: service.watchMyProfile(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _CenteredMessage(
            'Gagal memuat profil: ${snapshot.error}',
            action: TextButton(onPressed: service.signOut, child: const Text('Keluar')),
          );
        }
        final profile = snapshot.data;
        if (profile == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return DashboardShell(profile: profile);
      },
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.message, {this.action});

  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [Text(message, textAlign: TextAlign.center), ?action],
          ),
        ),
      ),
    );
  }
}
