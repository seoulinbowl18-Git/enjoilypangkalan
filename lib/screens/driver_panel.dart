import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../services/supabase_service.dart';
import '../ui/enjoily_style.dart';
import '../utils/fare.dart';

/// Tab "Driver": semua unit (Unit 1, Unit 2, …) dengan status. Tombol
/// Siap/Istirahat, order masuk, dan pendapatan hanya untuk unit milik akun
/// driver yang login, atau semua unit bila admin (sesuai RLS drivers_units).
class DriverPanel extends StatefulWidget {
  const DriverPanel({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<DriverPanel> createState() => _DriverPanelState();
}

class _DriverPanelState extends State<DriverPanel> {
  late final SupabaseService _service = context.read<SupabaseService>();
  late final Stream<List<Map<String, dynamic>>> _units = _service.watchAllUnits();
  late final bool _isAdmin = widget.profile['role'] == 'admin';
  late final bool _isDriver = widget.profile['role'] == 'driver';
  late final Stream<List<Map<String, dynamic>>> _orders =
      _isDriver || _isAdmin ? _service.watchDriverOrders() : const Stream.empty();

  Map<String, String> _pangkalanNames = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.fetchPangkalan().then((rows) {
      if (mounted) {
        setState(() => _pangkalanNames = {
              for (final p in rows) p['id'] as String: p['name'] as String,
            });
      }
    }, onError: (_) {});
  }

  bool _isMine(Map<String, dynamic> unit) => unit['driver_uid'] == _service.uid;

  bool _canManage(Map<String, dynamic> unit) => _isAdmin || _isMine(unit);

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (success != null) _toast(success);
    } on EnjoilyException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Siap = Online + status ready; Istirahat = status rest.
  Future<void> _setReady(Map<String, dynamic> unit, bool ready) async {
    final id = unit['id'] as String;
    await _run(() async {
      if (ready) {
        if (unit['is_online'] != true) await _service.setUnitOnline(id, true);
        await _service.setUnitStatus(id, 'ready');
      } else {
        await _service.setUnitStatus(id, 'rest');
      }
    }, success: '${unitLabel(id)} ${ready ? 'siap jalan' : 'istirahat'}');
    if (ready && _isMine(unit)) _sendLocation(id);
  }

  /// Kirim posisi sekali saat Siap (opsional; diabaikan bila izin ditolak).
  Future<void> _sendLocation(String unitId) async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      await _service.updateUnitLocation(unitId, pos.latitude, pos.longitude);
    } catch (_) {
      // Lokasi tidak wajib untuk menerima order
    }
  }

  // -------------------------------------------------------------------
  // Aksi order: pending → accepted → arrived → on_trip → completed
  // -------------------------------------------------------------------

  Future<void> _advance(Map<String, dynamic> order) async {
    final id = order['id'] as String;
    switch (order['status']) {
      case 'pending':
        await _run(() => _service.driverAcceptOrder(id), success: 'Order diterima');
      case 'accepted':
        await _run(() => _service.driverArrive(id));
      case 'arrived':
        await _run(() => _service.driverStartTrip(id));
      case 'on_trip':
        var cashReceived = false;
        if (order['payment_method'] == 'cash') {
          cashReceived = await _confirm(
                'Uang tunai diterima?',
                'Pastikan penumpang sudah membayar ${rupiah(order['total_fare'] as num)}.',
                'Sudah diterima',
              ) ??
              false;
          if (!cashReceived) return;
        }
        await _run(() => _service.completeOrder(id, cashReceived: cashReceived),
            success: 'Trip selesai');
    }
  }

  Future<void> _cancel(Map<String, dynamic> order) async {
    final ok = await _confirm('Tolak / batalkan order?', 'Penumpang akan diberi tahu.', 'Batalkan');
    if (ok == true) {
      await _run(() => _service.cancelOrder(order['id'] as String, reason: 'Dibatalkan driver'),
          success: 'Pesanan ditolak');
    }
  }

  Future<void> _showContacts(Map<String, dynamic> order) async {
    await _run(() async {
      final c = await _service.getOrderContacts(order['id'] as String);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(c['passenger_name'] as String? ?? 'Penumpang'),
          content: SelectableText('WhatsApp: ${c['passenger_phone'] ?? '-'}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
          ],
        ),
      );
    });
  }

  Future<bool?> _confirm(String title, String body, String okLabel) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Kembali')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(okLabel)),
        ],
      ),
    );
  }

  Future<void> _changePangkalan(Map<String, dynamic> unit) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pindah pangkalan'),
        children: [
          for (final e in _pangkalanNames.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, e.key),
              child: Text(e.value,
                  style: TextStyle(
                      fontWeight:
                          e.key == unit['current_pangkalan'] ? FontWeight.w700 : FontWeight.normal)),
            ),
        ],
      ),
    );
    if (picked != null && picked != unit['current_pangkalan']) {
      await _run(() => _service.setUnitPangkalan(unit['id'] as String, picked),
          success: 'Pindah ke ${_pangkalanNames[picked]}');
    }
  }

  // -------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _units,
      builder: (context, unitSnap) {
        if (unitSnap.hasError) {
          return EnjTabBody(children: [EnjSub('Gagal memuat unit: ${unitSnap.error}')]);
        }
        if (!unitSnap.hasData) return const Center(child: CircularProgressIndicator());
        final units = unitSnap.data!;
        final managed = units.where(_canManage).toList();

        return StreamBuilder<List<Map<String, dynamic>>>(
          stream: _orders,
          initialData: const [],
          builder: (context, orderSnap) {
            final orders = orderSnap.data ?? const [];
            final trips = managed.fold<num>(0, (s, u) => s + (u['total_trips_today'] as num? ?? 0));
            final earnings = managed.fold<num>(0, (s, u) => s + (u['earnings_today'] as num? ?? 0));
            return EnjTabBody(
              children: [
                const EnjH2('Panel driver'),
                if (managed.isEmpty)
                  EnjSub(_isDriver
                      ? 'Akun ini belum dihubungkan ke unit. Minta admin mengisi '
                          'drivers_units.driver_uid dengan akunmu.'
                      : 'Status unit di semua pangkalan. Status hanya bisa diubah oleh driver unit itu.'),
                if (units.isEmpty) const EnjSub('Belum ada unit terdaftar.'),
                for (final u in units)
                  _buildUnitCard(
                    context,
                    u,
                    orders.where((o) => o['driver_unit_id'] == u['id']).toList(),
                  ),
                if (managed.isNotEmpty)
                  EnjCard(
                    children: [
                      const EnjB('Pendapatan hari ini'),
                      Text(rupiah(earnings),
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: EnjColors.of(context).ink)),
                      EnjSub('$trips perjalanan'
                          '${managed.length > 1 ? ' dari semua unit' : ''}'),
                    ],
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildUnitCard(
      BuildContext context, Map<String, dynamic> unit, List<Map<String, dynamic>> orders) {
    final status = SupabaseService.displayStatus(unit);
    final canManage = _canManage(unit);
    final pangkalan = _pangkalanNames[unit['current_pangkalan']] ?? '—';
    return EnjCard(
      children: [
        Row(
          spacing: 12,
          children: [
            const EnjAva('EV'),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EnjB('${unitLabel(unit['id'] as String)} · ${unit['driver_name']}'),
                  EnjSub(canManage
                      ? '${unit['total_trips_today'] ?? 0} perjalanan · '
                          '${rupiah(unit['earnings_today'] as num? ?? 0)} · $pangkalan'
                      : '${unit['vehicle_model']} · $pangkalan'),
                ],
              ),
            ),
            EnjStatusTag(status),
          ],
        ),
        if (canManage)
          if (orders.isNotEmpty)
            for (final o in orders)
              _DriverOrderBox(
                order: o,
                busy: _busy,
                onAdvance: () => _advance(o),
                onCancel: () => _cancel(o),
                onContacts: () => _showContacts(o),
              )
          else if (status == 'on_trip')
            const EnjSub('Sedang mengantar penumpang…')
          else
            Row(
              spacing: 8,
              children: [
                status == 'ready'
                    ? EnjButton('Istirahat',
                        small: true,
                        kind: EnjButtonKind.ghost,
                        onPressed: _busy ? null : () => _setReady(unit, false))
                    : EnjButton('Siap jalan',
                        small: true, onPressed: _busy ? null : () => _setReady(unit, true)),
                if (_isMine(unit))
                  EnjButton('Pindah pangkalan',
                      small: true,
                      kind: EnjButtonKind.ghost,
                      onPressed: _busy ? null : () => _changePangkalan(unit)),
              ],
            ),
      ],
    );
  }
}

/// Order untuk unit ini (.ord): Terima/Tolak lalu langkah trip berikutnya.
class _DriverOrderBox extends StatelessWidget {
  const _DriverOrderBox({
    required this.order,
    required this.busy,
    required this.onAdvance,
    required this.onCancel,
    required this.onContacts,
  });

  final Map<String, dynamic> order;
  final bool busy;
  final VoidCallback onAdvance;
  final VoidCallback onCancel;
  final VoidCallback onContacts;

  static const _nextActionLabels = {
    'pending': 'Terima',
    'accepted': 'Sampai di lokasi',
    'arrived': 'Mulai trip',
    'on_trip': 'Selesai trip',
  };

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String;
    final method = order['payment_method'] as String;
    final paid = order['payment_status'] == 'paid';
    // QR/VA harus lunas (via webhook) sebelum trip bisa diselesaikan
    final waitingPayment = status == 'on_trip' && (method == 'qr' || method == 'va') && !paid;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: EnjColors.sun, width: 2),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          EnjB(status == 'pending' ? 'Pesanan masuk' : orderStatusLabels[status] ?? status),
          EnjSub('${(order['distance_km'] as num).toStringAsFixed(1)} km · '
              '${rupiah(order['total_fare'] as num)} · bayar ${paymentMethodLabels[method]}'
              '${order['is_free_pay'] == true ? ' · suka-suka' : ''}'
              '${paid ? ' · lunas' : ''}'),
          EnjSub.rich([
            const TextSpan(text: 'Jemput: '),
            enjBold('${order['pickup_address']}'),
            const TextSpan(text: ' · Tujuan: '),
            enjBold('${order['destination_address']}'),
          ]),
          if (waitingPayment)
            EnjSub('Menunggu penumpang membayar via ${paymentMethodLabels[method]}',
                color: EnjColors.red),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              EnjButton(_nextActionLabels[status] ?? 'Lanjut',
                  small: true, onPressed: busy || waitingPayment ? null : onAdvance),
              if (status != 'pending')
                EnjButton('Kontak',
                    small: true, kind: EnjButtonKind.ghost, onPressed: busy ? null : onContacts),
              if (status != 'on_trip')
                EnjButton(status == 'pending' ? 'Tolak' : 'Batalkan',
                    small: true, kind: EnjButtonKind.ghost, onPressed: busy ? null : onCancel),
            ],
          ),
        ],
      ),
    );
  }
}
