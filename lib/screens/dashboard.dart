import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/supabase_service.dart';
import '../ui/enjoily_style.dart';
import 'cost_calculator.dart';
import 'driver_panel.dart';
import 'passenger_home.dart';

/// Tampilan utama seperti prototipe: header logo, isi tab, dan nav bawah
/// "Penumpang" / "Driver" / "Hitung biaya". Akun driver/admin dibuka di tab Driver.
class DashboardShell extends StatefulWidget {
  const DashboardShell({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends State<DashboardShell> {
  static const _tabs = ['Penumpang', 'Driver', 'Hitung biaya'];

  late final SupabaseService _service = context.read<SupabaseService>();
  late final bool _isDemo = widget.profile['is_demo'] == true;
  late int _tab = _isDemo || widget.profile['role'] == 'passenger' ? 0 : 1;

  /// Titik merah di tab Driver saat ada order baru untuk unit driver ini.
  late final Stream<bool> _hasPendingOrder = widget.profile['role'] != 'passenger'
      ? _service.watchDriverOrders().map((orders) => orders.any((o) => o['status'] == 'pending'))
      : const Stream.empty();

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: _PhoneFrame(
          child: Column(
            children: [
              _Header(
                role: widget.profile['role'] as String?,
                onSignOut: _isDemo ? null : _service.signOut,
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    PassengerHome(profile: widget.profile),
                    DriverPanel(profile: widget.profile),
                    const CostCalculator(),
                  ],
                ),
              ),
              StreamBuilder<bool>(
                stream: _hasPendingOrder,
                initialData: false,
                builder: (context, snapshot) => _NavBar(
                  labels: _tabs,
                  index: _tab,
                  dotIndex: snapshot.data == true ? 1 : null,
                  onTap: (i) => setState(() => _tab = i),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lebar maks 430. Di layar ≥ 500 px tampil sebagai bingkai ponsel (.phone).
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 500) {
          return Center(
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: child),
          );
        }
        return Center(
          child: Container(
            width: 430,
            height: box.maxHeight > 920 ? 900 : box.maxHeight - 20,
            decoration: BoxDecoration(
              color: c.bg,
              border: Border.all(color: c.ink, width: 8),
              borderRadius: BorderRadius.circular(36),
            ),
            child: ClipRRect(borderRadius: BorderRadius.circular(28), child: child),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.role, required this.onSignOut});

  static const _roleLabels = {'admin': 'Admin', 'driver': 'Driver', 'passenger': 'Penumpang'};

  final String? role;

  /// null = mode demo: tidak ada sesi untuk diakhiri.
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: c.ink, borderRadius: BorderRadius.circular(20)),
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(text: 'En'),
                      const TextSpan(
                        text: 'joily',
                        style: TextStyle(color: EnjColors.sun),
                      ),
                      const TextSpan(text: ' Pangkalan'),
                    ],
                    style: TextStyle(color: c.bg, fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: c.card,
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onSignOut ??
                  () => ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Mode demo — tidak perlu keluar'))),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Text(
                  '${_roleLabels[role] ?? 'Akun'} · Keluar',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Nav bawah (.nav): tab aktif hijau dengan garis 3 px di atas.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.labels, required this.index, required this.onTap, this.dotIndex});

  final List<String> labels;
  final int index;
  final int? dotIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.line)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: i == index,
                button: true,
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: i == index ? EnjColors.brand : Colors.transparent, width: 3),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(4, 9, 4, 12),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        // Lebar penuh agar titik bisa diletakkan relatif ke tombol
                        const SizedBox(width: double.infinity),
                        Text(
                          labels[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: i == index ? c.accent : c.mute,
                          ),
                        ),
                        if (dotIndex == i)
                          Positioned(
                            top: -4,
                            right: 0,
                            left: 0,
                            child: Align(
                              alignment: const Alignment(0.44, 0),
                              child: Container(
                                width: 9,
                                height: 9,
                                decoration: const BoxDecoration(color: EnjColors.red, shape: BoxShape.circle),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
