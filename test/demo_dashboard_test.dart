import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:enjoily_mobile/screens/dashboard.dart';
import 'package:enjoily_mobile/services/demo_service.dart';
import 'package:enjoily_mobile/services/supabase_service.dart';
import 'package:enjoily_mobile/ui/enjoily_style.dart';

void main() {
  testWidgets('mode demo: 3 tab, pesan → terima → selesai', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final demo = DemoService();
    // Sama seperti _RoleRouter di main.dart: profil (saldo) real-time
    await tester.pumpWidget(Provider<SupabaseService>.value(
      value: demo,
      child: MaterialApp(
        theme: enjoilyTheme(Brightness.light, null),
        home: StreamBuilder<Map<String, dynamic>?>(
          stream: demo.watchMyProfile(),
          builder: (context, snapshot) => snapshot.data == null
              ? const SizedBox()
              : DashboardShell(profile: snapshot.data!),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tab Penumpang
    expect(find.text('Naik mobil listrik, bayar suka-suka'), findsOneWidget);
    expect(find.text('Rp25.000'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'Depan pasar');

    Future<void> tapVisible(String text) async {
      await tester.scrollUntilVisible(find.text(text), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text(text));
      await tester.pump();
    }

    await tester.scrollUntilVisible(find.text('Unit 2'), 100,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Istirahat'), findsOneWidget); // Unit 2 tampil nonaktif
    await tapVisible('Unit 1');
    await tapVisible('Stasiun · 2.8 km');
    await tapVisible('Pesan Unit 1');
    await tester.pump();
    expect(find.text('Pesanan terkirim ke Unit 1 · Rp8.000'), findsOneWidget);
    // List masih tergulir ke bawah, judul ada di atas
    expect(find.text('Menunggu Unit 1 menerima…', skipOffstage: false), findsOneWidget);

    // Tab Driver: ketiga unit + order masuk
    await tester.tap(find.text('Driver'));
    await tester.pump();
    expect(find.text('Unit 3 · Joko'), findsOneWidget);
    expect(find.text('Pesanan masuk'), findsOneWidget);
    for (final step in ['Terima', 'Sampai di lokasi', 'Mulai trip', 'Selesai trip']) {
      await tester.tap(find.text(step));
      await tester.pump();
    }
    expect(find.text('Rp8.000'), findsWidgets); // pendapatan hari ini

    // Tab Hitung biaya
    await tester.tap(find.text('Hitung biaya'));
    await tester.pump();
    expect(find.text('Biaya per km'), findsOneWidget);
    expect(find.text('Rp1.175'), findsOneWidget); // 0,15 × 2.500 + 800

    // Saldo terpotong Rp8.000
    await tester.tap(find.text('Penumpang'));
    await tester.pumpAndSettle();
    expect((await demo.fetchMyProfile())!['ewallet_balance'], 17000);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
    await tester.pumpAndSettle();
    expect(find.text('Rp17.000'), findsOneWidget);

    // Habiskan timer snackbar agar test bersih
    await tester.pump(const Duration(seconds: 10));
  });
}
