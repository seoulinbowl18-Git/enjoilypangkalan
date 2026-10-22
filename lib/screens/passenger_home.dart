import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../services/supabase_service.dart';
import '../ui/enjoily_style.dart';
import '../utils/fare.dart';

const _minSliderKm = 1.0;
const _maxSliderKm = 12.0;
const _quickFares = [5000, 8000, 10000, 15000];

/// Tab "Penumpang": banner, saldo, lalu form jemput → unit → pangkalan & tujuan
/// seperti prototipe. Saat ada order aktif, form diganti status order.
class PassengerHome extends StatefulWidget {
  const PassengerHome({super.key, required this.profile});

  /// Baris public.users (real-time dari AuthGate), termasuk ewallet_balance.
  final Map<String, dynamic> profile;

  @override
  State<PassengerHome> createState() => _PassengerHomeState();
}

class _PassengerHomeState extends State<PassengerHome> {
  late final SupabaseService _service = context.read<SupabaseService>();
  late final Stream<Map<String, dynamic>?> _activeOrder = _service.watchMyActiveOrder();

  final _pickupAddress = TextEditingController();
  final _customDestination = TextEditingController();
  final _offeredFare = TextEditingController(text: '8000');

  List<Map<String, dynamic>> _pangkalan = [];
  Map<String, dynamic>? _selectedPangkalan;
  // Disimpan di state, bukan StreamBuilder: daftar unit ada di ListView yang
  // bisa membangun ulang widget-nya, dan stream tidak boleh di-listen dua kali.
  StreamSubscription<List<Map<String, dynamic>>>? _unitSub;
  List<Map<String, dynamic>>? _units;
  Object? _unitsError;
  String? _selectedUnitId;

  /// Tujuan dari pangkalan.destinations. Bila null dan [_otherDestination],
  /// penumpang mengisi alamat + slider jarak.
  Map<String, dynamic>? _destination;
  bool _otherDestination = false;
  double _customKm = 3;
  String _paymentMethod = 'saldo';
  Position? _myPosition;

  bool _loading = true;
  bool _busy = false;
  String? _loadError;

  int get _balance => (widget.profile['ewallet_balance'] as num?)?.toInt() ?? 0;

  bool get _hasDestination => _destination != null || _otherDestination;

  double get _distanceKm =>
      _destination != null ? (_destination!['distance_km'] as num).toDouble() : _customKm;

  bool get _freePay => isFreePay(_distanceKm, _destination?['free_pay'] == true);

  int get _offered => int.tryParse(_offeredFare.text.replaceAll(RegExp(r'\D'), '')) ?? 0;

  int get _fare => calculateFare(_distanceKm, _offered, freePay: _freePay);

  bool get _balanceShort => _paymentMethod == 'saldo' && _balance < _fare;

  @override
  void initState() {
    super.initState();
    _loadPangkalan();
  }

  @override
  void dispose() {
    _unitSub?.cancel();
    _pickupAddress.dispose();
    _customDestination.dispose();
    _offeredFare.dispose();
    super.dispose();
  }

  Future<void> _loadPangkalan() async {
    try {
      final rows = await _service.fetchPangkalan();
      setState(() {
        _pangkalan = rows;
        _loading = false;
        if (rows.isNotEmpty) _selectPangkalan(rows.first);
      });
    } on EnjoilyException catch (e) {
      setState(() {
        _loading = false;
        _loadError = e.message;
      });
    }
  }

  void _selectPangkalan(Map<String, dynamic> p) {
    _selectedPangkalan = p;
    _unitSub?.cancel();
    _units = null;
    _unitsError = null;
    _unitSub = _service.watchUnitsAtPangkalan(p['id'] as String).listen(
          _onUnits,
          onError: (Object e) => setState(() => _unitsError = e),
        );
    _selectedUnitId = null;
    _destination = null;
    _otherDestination = false;
    _syncPaymentMethod();
  }

  void _onUnits(List<Map<String, dynamic>> units) {
    setState(() {
      _units = units;
      _unitsError = null;
      final selected = units.where((u) => u['id'] == _selectedUnitId);
      // Unit yang dipilih baru saja dipesan orang lain / istirahat
      if (selected.isEmpty || !SupabaseService.isBookable(selected.first)) _selectedUnitId = null;
    });
  }

  void _syncPaymentMethod() {
    if (!allowedPaymentMethods(_freePay).contains(_paymentMethod)) _paymentMethod = 'saldo';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // -------------------------------------------------------------------
  // Lokasi
  // -------------------------------------------------------------------

  Future<Position?> _locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('Layanan lokasi mati. Nyalakan GPS / izin lokasi browser.');
        return null;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _toast('Izin lokasi ditolak');
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      setState(() => _myPosition = pos);
      return pos;
    } catch (e) {
      _toast('Gagal mengambil lokasi: $e');
      return null;
    }
  }

  Future<void> _useMyLocation() async {
    final pos = await _locate();
    if (pos == null) return;
    if (_pickupAddress.text.trim().isEmpty) {
      _pickupAddress.text =
          'Lokasi saya (${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)})';
    }
  }

  Future<void> _selectNearestPangkalan() async {
    final pos = _myPosition ?? await _locate();
    if (pos == null || _pangkalan.isEmpty) return;
    double distanceTo(Map<String, dynamic> p) => Geolocator.distanceBetween(
        pos.latitude, pos.longitude, (p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());
    final nearest = _pangkalan.reduce((a, b) => distanceTo(a) <= distanceTo(b) ? a : b);
    setState(() => _selectPangkalan(nearest));
    _toast('${nearest['name']} — ${(distanceTo(nearest) / 1000).toStringAsFixed(1)} km dari kamu');
  }

  // -------------------------------------------------------------------
  // Pesan
  // -------------------------------------------------------------------

  Future<void> _order() async {
    final pangkalan = _selectedPangkalan;
    if (pangkalan == null || _selectedUnitId == null) {
      _toast('Pilih pangkalan dan unit dulu');
      return;
    }
    if (_pickupAddress.text.trim().isEmpty) {
      _toast('Isi lokasi jemput dulu');
      return;
    }
    if (_otherDestination && _customDestination.text.trim().isEmpty) {
      _toast('Isi alamat tujuan');
      return;
    }
    if (_freePay && _offered < minFare) {
      _toast('Minimal bayar ${rupiah(minFare)}');
      return;
    }
    if (_balanceShort) {
      _openTopUp(suggested: topUpShortfall(_fare, _balance));
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await _service.createOrder(
        pangkalanId: pangkalan['id'] as String,
        driverUnitId: _selectedUnitId!,
        paymentMethod: _paymentMethod,
        pickupAddress: _pickupAddress.text.trim(),
        // Tanpa GPS, titik jemput = lokasi pangkalan
        pickupLat: _myPosition?.latitude ?? (pangkalan['lat'] as num).toDouble(),
        pickupLng: _myPosition?.longitude ?? (pangkalan['lng'] as num).toDouble(),
        destinationName: _destination?['name'] as String?,
        destinationAddress: _destination == null ? _customDestination.text.trim() : null,
        distanceKm: _destination == null ? _customKm : null,
        offeredFare: _freePay ? _offered : null,
      );
      _toast('Pesanan terkirim ke ${unitLabel(_selectedUnitId)} · '
          '${rupiah(result['total_fare'] as num)}');
    } on EnjoilyException catch (e) {
      if (e.code == 'INSUFFICIENT_BALANCE') {
        _openTopUp(suggested: topUpShortfall(_fare, _balance));
      } else if (e.code == 'UNIT_UNAVAILABLE') {
        setState(() => _selectedUnitId = null);
      }
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openTopUp({int suggested = 20000}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TopUpSheet(service: _service, suggested: suggested),
    );
  }

  // -------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _activeOrder,
      builder: (context, snapshot) {
        final order = snapshot.data;
        return EnjTabBody(
          children: [
            if (order == null) ...[const _PromoBanner(), const _FeatureGrid()],
            _BalanceCard(balance: _balance, onTopUp: _openTopUp),
            if (order != null)
              _ActiveOrderView(order: order, service: _service)
            else
              ..._buildOrderForm(context),
          ],
        );
      },
    );
  }

  List<Widget> _buildOrderForm(BuildContext context) {
    if (_loading) return const [Center(child: CircularProgressIndicator())];
    if (_loadError != null) return [EnjSub('Gagal memuat pangkalan: $_loadError')];
    if (_pangkalan.isEmpty) return const [EnjSub('Belum ada pangkalan aktif.')];

    final destinations = ((_selectedPangkalan?['destinations'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();

    return [
      // --- Jemput ---
      const EnjH2('Mau dijemput di mana?'),
      EnjCard(
        children: [
          const Row(
            spacing: 10,
            children: [EnjAva('📍', size: 34, fontSize: 16), EnjB('Lokasi jemput')],
          ),
          EnjField(controller: _pickupAddress, hint: 'Tulis alamat atau patokan'),
          EnjChips(
            children: [
              EnjChip('Pakai lokasi saya', onTap: _useMyLocation),
              EnjChip('Pangkalan terdekat', onTap: _selectNearestPangkalan),
            ],
          ),
        ],
      ),

      // --- Unit ---
      const EnjH2('Pilih mobil di pangkalan'),
      const EnjSub('Pilih unit yang sedang siap. Kamu tahu mobil dan drivernya.'),
      if (_unitsError != null)
        EnjSub('Gagal memuat unit: $_unitsError')
      else if (_units == null)
        const LinearProgressIndicator()
      else if (_units!.isEmpty)
        const EnjSub('Belum ada unit di pangkalan ini.')
      else
        for (final u in _units!)
          _UnitTile(
            unit: u,
            selected: _selectedUnitId == u['id'],
            onTap: SupabaseService.isBookable(u)
                ? () => setState(() => _selectedUnitId = u['id'] as String)
                : null,
          ),

      // --- Pangkalan, tujuan & tarif ---
      EnjCard(
        children: [
          const EnjB('Pangkalan terdekat'),
          EnjChips(
            children: [
              for (final p in _pangkalan)
                EnjChip(
                  p['name'] as String,
                  selected: _selectedPangkalan?['id'] == p['id'],
                  onTap: () => setState(() => _selectPangkalan(p)),
                ),
            ],
          ),
          const EnjB('Tujuan'),
          EnjChips(
            children: [
              for (final d in destinations)
                EnjChip(
                  d['free_pay'] == true
                      ? '${d['name']} · suka-suka'
                      : '${d['name']} · ${d['distance_km']} km',
                  selected: _destination?['name'] == d['name'],
                  onTap: () => setState(() {
                    _destination = d;
                    _otherDestination = false;
                    _syncPaymentMethod();
                  }),
                ),
              EnjChip(
                'Tujuan lain',
                selected: _otherDestination,
                onTap: () => setState(() {
                  _destination = null;
                  _otherDestination = true;
                  _syncPaymentMethod();
                }),
              ),
            ],
          ),
          ..._buildFare(context),
        ],
      ),

      EnjButton(
        _selectedUnitId == null
            ? 'Pilih unit dulu'
            : !_hasDestination
                ? 'Pilih tujuan dulu'
                : _balanceShort
                    ? 'Saldo kurang — Top Up dulu'
                    : 'Pesan ${unitLabel(_selectedUnitId)}',
        onPressed: _busy || _selectedUnitId == null || !_hasDestination ? null : _order,
      ),
    ];
  }

  /// Isi bagian bawah kartu tujuan (#fa di prototipe).
  List<Widget> _buildFare(BuildContext context) {
    if (!_hasDestination) return const [EnjSub('Pilih tujuan dulu.')];
    final c = EnjColors.of(context);
    return [
      if (_otherDestination) ...[
        const EnjBadge('Tujuan lain'),
        EnjField(controller: _customDestination, hint: 'Tulis alamat tujuan'),
        EnjSub('Perkiraan jarak: ${_customKm.toStringAsFixed(1)} km'),
        Slider(
          value: _customKm,
          min: _minSliderKm,
          max: _maxSliderKm,
          divisions: ((_maxSliderKm - _minSliderKm) * 2).round(),
          label: '${_customKm.toStringAsFixed(1)} km',
          onChanged: (v) => setState(() {
            _customKm = v;
            _syncPaymentMethod();
          }),
        ),
      ],
      if (_freePay) ...[
        EnjBadge(_distanceKm <= freePayMaxKm ? '1–3 km: bayar suka-suka' : 'Bayar suka-suka'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: EnjColors.brand, width: 2),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            spacing: 6,
            children: [
              Text('Rp', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.mute)),
              Expanded(
                child: TextField(
                  controller: _offeredFare,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.ink),
                  decoration: const InputDecoration.collapsed(hintText: ''),
                ),
              ),
            ],
          ),
        ),
        EnjChips(
          children: [
            for (final v in _quickFares)
              EnjChip(
                rupiah(v),
                selected: _offered == v,
                onTap: () => setState(() => _offeredFare.text = '$v'),
              ),
          ],
        ),
        EnjSub('Minimal ${rupiah(minFare)} · dibayar dari saldo'),
      ] else ...[
        const EnjBadge('Di atas 3 km: tarif tetap', muted: true),
        Text(rupiah(_fare),
            style: TextStyle(
                fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: c.ink)),
        EnjSub('${rupiah(ratePerKm)} × ${_distanceKm.toStringAsFixed(1)} km'),
        const EnjB('Bayar pakai'),
        EnjChips(
          children: [
            for (final m in allowedPaymentMethods(false))
              EnjChip(
                paymentMethodLabels[m]!,
                selected: _paymentMethod == m,
                onTap: () => setState(() => _paymentMethod = m),
              ),
          ],
        ),
      ],
      if (_balanceShort)
        EnjSub(
          'Saldo kurang ${rupiah(_fare - _balance)}. '
          'Top up minimal ${rupiah(topUpShortfall(_fare, _balance))}.',
          color: EnjColors.red,
        ),
    ];
  }
}

/// Banner foto mobil (assets/images/banner_mobil.jpg). Tanpa foto, latar
/// diganti gradasi hijau tua → kuning dengan ikon mobil seperti prototipe.
class _PromoBanner extends StatelessWidget {
  const _PromoBanner();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 188),
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/images/banner_mobil.jpg',
                fit: BoxFit.cover,
                alignment: Alignment.centerRight,
                errorBuilder: (_, _, _) => const _BannerFallback(),
              ),
            ),
            // Gelap di kiri agar teks putih terbaca
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xE60E2A24), Color(0x990E2A24), Color(0x000E2A24)],
                    stops: [0, 0.55, 0.9],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
              child: Row(
                children: [
                  Expanded(
                    flex: 66,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EnjBadge('Enjoily Pangkalan'),
                        const SizedBox(height: 10),
                        const Text('Naik mobil listrik, bayar suka-suka',
                            style: TextStyle(
                                fontSize: 21, fontWeight: FontWeight.w800, color: Colors.white, height: 1.2)),
                        const SizedBox(height: 6),
                        Text('Jarak 1–3 km sesukamu. Senyap, AC dingin, driver dikenal.',
                            style: TextStyle(
                                fontSize: 13, height: 1.35, color: Colors.white.withValues(alpha: 0.92))),
                      ],
                    ),
                  ),
                  const Spacer(flex: 34),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BannerFallback extends StatelessWidget {
  const _BannerFallback();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [Color(0xFF1E3A2E), Color(0xFF6B6A1E), Color(0xFFD9B91A)],
          stops: [0.2, 0.6, 1],
        ),
      ),
      child: Align(
        alignment: const Alignment(1.15, 0.55),
        child: Icon(Icons.electric_car, size: 120, color: Colors.white.withValues(alpha: 0.85)),
      ),
    );
  }
}

/// Empat kartu keunggulan 2 × 2 di bawah banner.
class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid();

  static const _features = [
    ('🔇', 'Aman, senyap dan AC dingin'),
    ('💸', 'Bayar suka-suka 1–3 km'),
    ('🛡️', 'Driver, plat, dan tombol darurat'),
    ('📱', 'Bayar QR, VA Bank, atau Cash'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    Widget tile((String, String) f) => Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 8,
              children: [
                Text(f.$1, style: const TextStyle(fontSize: 18)),
                Text(f.$2,
                    style: TextStyle(fontSize: 13, height: 1.3, fontWeight: FontWeight.w700, color: c.ink)),
              ],
            ),
          ),
        );
    return Column(
      spacing: 10,
      children: [
        for (var i = 0; i < _features.length; i += 2)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 10,
              children: [tile(_features[i]), tile(_features[i + 1])],
            ),
          ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.onTopUp});

  final int balance;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18)),
      child: Row(
        spacing: 12,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 2,
              children: [
                const EnjSub('Saldo Enjoily'),
                Text(rupiah(balance),
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.ink)),
              ],
            ),
          ),
          EnjButton('Top up', onPressed: onTopUp, small: true),
        ],
      ),
    );
  }
}

/// Tombol unit (.unit): nonaktif bila unit tidak siap dipesan.
class _UnitTile extends StatelessWidget {
  const _UnitTile({required this.unit, required this.selected, required this.onTap});

  final Map<String, dynamic> unit;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: selected ? EnjColors.brand : c.line, width: 2),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              spacing: 12,
              children: [
                const EnjAva('EV'),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EnjB(unitLabel(unit['id'] as String)),
                      EnjSub('Driver: ${unit['driver_name']} · ${unit['vehicle_model']}'
                          ' · ${unit['license_plate']}'),
                    ],
                  ),
                ),
                EnjStatusTag(SupabaseService.displayStatus(unit)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Order aktif penumpang: menunggu (pulse) → driver menuju → sampai → jalan.
class _ActiveOrderView extends StatefulWidget {
  const _ActiveOrderView({required this.order, required this.service});

  final Map<String, dynamic> order;
  final SupabaseService service;

  @override
  State<_ActiveOrderView> createState() => _ActiveOrderViewState();
}

class _ActiveOrderViewState extends State<_ActiveOrderView> {
  bool _busy = false;
  Map<String, dynamic>? _contacts;
  Map<String, dynamic>? _payment;

  Map<String, dynamic> get _order => widget.order;
  String get _id => _order['id'] as String;

  @override
  void didUpdateWidget(_ActiveOrderView old) {
    super.didUpdateWidget(old);
    if (old.order['id'] != _id) {
      _contacts = null;
      _payment = null;
    }
    // Kontak baru tersedia setelah driver menerima order
    if (_contacts == null && old.order['status'] == 'pending' && _order['status'] != 'pending') {
      _loadContacts();
    }
  }

  @override
  void initState() {
    super.initState();
    if (_order['status'] != 'pending') _loadContacts();
  }

  Future<void> _loadContacts() async {
    try {
      final c = await widget.service.getOrderContacts(_id);
      if (mounted) setState(() => _contacts = c);
    } on EnjoilyException {
      // Kontak opsional; abaikan bila belum tersedia
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } on EnjoilyException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan pesanan?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Tidak')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Batalkan')),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => widget.service.cancelOrder(_id, reason: 'Dibatalkan penumpang'));
    }
  }

  Future<void> _pay() async {
    String? bank;
    if (_order['payment_method'] == 'va') {
      bank = await _pickBank(context);
      if (bank == null) return;
    }
    await _run(() async {
      final p = await widget.service.createOrderPayment(_id, bank: bank);
      setState(() => _payment = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _order['status'] as String;
    final method = _order['payment_method'] as String;
    final paid = _order['payment_status'] == 'paid';
    final needsGatewayPayment = (method == 'qr' || method == 'va') && !paid;
    final unit = unitLabel(_order['driver_unit_id'] as String?);
    final summary = '${(_order['distance_km'] as num).toStringAsFixed(1)} km · '
        '${rupiah(_order['total_fare'] as num)} · ${paymentMethodLabels[method]}'
        '${paid ? ' · lunas' : ''}';

    if (status == 'pending') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          EnjH2('Menunggu $unit menerima…', center: true),
          const EnjPulse(),
          EnjSub(
            'Pesanan: $summary\n'
            'Jemput di: ${_order['pickup_address']}\n'
            'Tujuan: ${_order['destination_address']}',
            center: true,
          ),
          EnjButton('Batalkan', onPressed: _busy ? null : _cancel, kind: EnjButtonKind.ghost),
        ],
      );
    }

    final title = switch (status) {
      'accepted' => '$unit menuju lokasimu',
      'arrived' => '$unit sudah sampai',
      _ => 'Sedang jalan bersama $unit',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 12,
      children: [
        EnjH2(title),
        EnjCard(
          children: [
            Row(
              spacing: 12,
              children: [
                const EnjAva('EV'),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EnjB('Driver: ${_contacts?['driver_name'] ?? '…'}'),
                      EnjSub(_contacts == null
                          ? 'Mobil listrik'
                          : 'Mobil listrik · ${_contacts!['vehicle_model']} · '
                              'Plat ${_contacts!['license_plate']}'),
                    ],
                  ),
                ),
              ],
            ),
            if (_contacts?['driver_phone'] != null)
              SelectableText('WhatsApp: ${_contacts!['driver_phone']}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
        EnjSub.rich([
          const TextSpan(text: 'Dijemput di: '),
          enjBold('${_order['pickup_address']}'),
          const TextSpan(text: '. Tujuan: '),
          enjBold('${_order['destination_address']}'),
          TextSpan(text: '.\n$summary'),
        ]),
        if (_payment != null) EnjCard(children: [_GatewayPaymentInfo(_payment!)]),
        if (needsGatewayPayment)
          EnjButton(
            method == 'qr' ? 'Tampilkan QRIS' : 'Buat nomor VA',
            onPressed: _busy ? null : _pay,
          ),
        if (status != 'on_trip')
          EnjButton('Batalkan pesanan', onPressed: _busy ? null : _cancel, kind: EnjButtonKind.ghost),
      ],
    );
  }
}

/// QRIS / nomor VA dari Edge Function create-topup atau create-order-payment.
class _GatewayPaymentInfo extends StatelessWidget {
  const _GatewayPaymentInfo(this.data);

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qrImage = data['qr_image_url'] as String?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data['va_number'] != null)
          SelectableText(
            'VA ${(data['bank'] as String?)?.toUpperCase() ?? ''}: ${data['va_number']}',
            style: theme.textTheme.titleMedium,
          )
        else if (qrImage != null)
          Center(child: Image.network(qrImage, width: 220, height: 220))
        else if (data['qr_string'] != null)
          SelectableText('QRIS: ${data['qr_string']}'),
        if (data['expires_at'] != null) Text('Berlaku sampai ${data['expires_at']}'),
      ],
    );
  }
}

Future<String?> _pickBank(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Pilih bank VA'),
      children: [
        for (final b in const ['bca', 'bni', 'bri', 'permata'])
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, b),
            child: Text(b.toUpperCase()),
          ),
      ],
    ),
  );
}

/// Top up saldo lewat Edge Function create-topup (QR / VA saja, tanpa tunai).
/// Saldo bertambah otomatis setelah webhook gateway; kartu saldo ikut real-time.
class _TopUpSheet extends StatefulWidget {
  const _TopUpSheet({required this.service, required this.suggested});

  final SupabaseService service;
  final int suggested;

  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  late final _amount = TextEditingController(text: '${widget.suggested}');
  String _method = 'qr';
  bool _busy = false;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    if (amount < 20000) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Minimal top up Rp20.000')));
      return;
    }
    String? bank;
    if (_method == 'va') {
      bank = await _pickBank(context);
      if (bank == null) return;
    }
    setState(() => _busy = true);
    try {
      final r = await widget.service.createTopup(amount, _method, bank: bank);
      setState(() => _result = r);
    } on EnjoilyException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Top Up Saldo', style: theme.textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_result == null) ...[
            Wrap(
              spacing: 8,
              children: [
                for (final v in const [20000, 50000, 100000])
                  ActionChip(
                    label: Text(rupiah(v)),
                    onPressed: () => setState(() => _amount.text = '$v'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Nominal', prefixText: 'Rp '),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final m in const ['qr', 'va'])
                  ChoiceChip(
                    label: Text(paymentMethodLabels[m]!),
                    selected: _method == m,
                    onSelected: (_) => setState(() => _method = m),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: const Text('Lanjut bayar'),
            ),
          ] else ...[
            Text('Nominal ${rupiah(_result!['amount'] as num? ?? 0)}'
                '${(_result!['bonus'] as num? ?? 0) > 0 ? ' + bonus ${rupiah(_result!['bonus'] as num)}' : ''}'),
            const SizedBox(height: 8),
            _GatewayPaymentInfo(_result!),
            const SizedBox(height: 8),
            const Text('Saldo akan bertambah otomatis setelah pembayaran diterima.'),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup')),
          ],
        ],
      ),
    );
  }
}
