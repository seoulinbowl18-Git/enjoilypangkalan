import 'dart:async';

import '../utils/fare.dart';
import 'supabase_service.dart';

/// Mode demo: semua data di memori, tanpa login dan tanpa menyentuh database.
/// Alurnya seperti prototipe: pesan di tab Penumpang → Terima di tab Driver →
/// Sampai → Mulai → Selesai; top up dan QRIS/VA dianggap lunas setelah 2 detik.
class DemoService extends SupabaseService {
  // Semua method yang dipakai UI di-override, jadi klien Supabase tidak pernah dipakai.
  DemoService() {
    _units.addAll([
      _unit('unit_1', 'Budi', 'Wuling Air ev', 'AD 1234 EV', 'pk_pasar', online: true, status: 'ready'),
      _unit('unit_2', 'Sari', 'Wuling Air ev', 'AD 2345 EV', 'pk_pasar', online: false, status: 'rest'),
      _unit('unit_3', 'Joko', 'BYD Dolphin', 'AD 3456 EV', 'pk_stasiun', online: true, status: 'ready'),
    ]);
  }

  static const _uid = 'demo-user';
  static const _payDelay = Duration(seconds: 2);

  final _changes = StreamController<void>.broadcast();
  var _nextId = 1;

  final Map<String, dynamic> _profile = {
    'id': _uid,
    'display_name': 'Demo',
    'role': 'admin',
    'is_demo': true,
    'ewallet_balance': 25000,
  };

  final List<Map<String, dynamic>> _pangkalan = [
    {
      'id': 'pk_pasar',
      'name': 'Pangkalan Pasar',
      'lat': -7.5665,
      'lng': 110.8270,
      'is_active': true,
      'destinations': [
        {'name': 'Stasiun', 'distance_km': 2.8, 'free_pay': false},
        {'name': 'Mal', 'distance_km': 5.0, 'free_pay': false},
        {'name': 'Kampus', 'distance_km': 8.0, 'free_pay': false},
        {'name': 'Rumah Sakit', 'distance_km': 3.5, 'free_pay': false},
      ],
    },
    {
      'id': 'pk_stasiun',
      'name': 'Pangkalan Stasiun',
      'lat': -7.5568,
      'lng': 110.8210,
      'is_active': true,
      'destinations': [
        {'name': 'Pasar', 'distance_km': 2.8, 'free_pay': false},
        {'name': 'Mal', 'distance_km': 4.0, 'free_pay': false},
        {'name': 'Kampus', 'distance_km': 6.0, 'free_pay': false},
        {'name': 'Rumah Sakit', 'distance_km': 2.0, 'free_pay': false},
      ],
    },
  ];

  final List<Map<String, dynamic>> _units = [];
  final List<Map<String, dynamic>> _orders = [];

  static Map<String, dynamic> _unit(
    String id,
    String driver,
    String model,
    String plate,
    String pangkalan, {
    required bool online,
    required String status,
  }) =>
      {
        'id': id,
        'driver_uid': 'driver-$id',
        'driver_name': driver,
        'vehicle_model': model,
        'license_plate': plate,
        'current_pangkalan': pangkalan,
        'is_online': online,
        'status': status,
        'verification_status': 'approved',
        'total_trips_today': 0,
        'earnings_today': 0,
      };

  void _notify() => _changes.add(null);

  /// Nilai sekarang, lalu nilai baru tiap ada perubahan (meniru realtime).
  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    yield* _changes.stream.map((_) => read());
  }

  Map<String, dynamic> _find(List<Map<String, dynamic>> rows, String id, String what) =>
      rows.firstWhere((r) => r['id'] == id,
          orElse: () => throw EnjoilyException('NOT_FOUND', '$what tidak ditemukan'));

  Map<String, dynamic> _order(String id) => _find(_orders, id, 'Pesanan');

  Map<String, dynamic> _unitById(String id) => _find(_units, id, 'Unit');

  Iterable<Map<String, dynamic>> get _active =>
      _orders.where((o) => SupabaseService.activeOrderStatuses.contains(o['status']));

  Map<String, dynamic> _copy(Map<String, dynamic> row) => Map<String, dynamic>.of(row);

  Future<Map<String, dynamic>> _step(String orderId, String from, String to) async {
    final order = _order(orderId);
    if (order['status'] != from) {
      throw EnjoilyException('INVALID_STATUS', 'Status pesanan sudah berubah');
    }
    order['status'] = to;
    _notify();
    return _copy(order);
  }

  // ---------------------------------------------------------------------
  // Auth & profil
  // ---------------------------------------------------------------------

  @override
  String? get uid => _uid;

  @override
  Future<void> signOut() async {}

  @override
  Stream<Map<String, dynamic>?> watchMyProfile() => _watch(() => _copy(_profile));

  @override
  Future<Map<String, dynamic>?> fetchMyProfile() async => _copy(_profile);

  @override
  Future<void> updatePhone(String phone) async {
    _profile['phone'] = phone;
    _notify();
  }

  // ---------------------------------------------------------------------
  // Penumpang
  // ---------------------------------------------------------------------

  @override
  Future<List<Map<String, dynamic>>> fetchPangkalan() async => _pangkalan.map(_copy).toList();

  @override
  Stream<List<Map<String, dynamic>>> watchUnitsAtPangkalan(String pangkalanId) => _watch(
      () => _units.where((u) => u['current_pangkalan'] == pangkalanId).map(_copy).toList());

  @override
  Stream<List<Map<String, dynamic>>> watchAllUnits() => _watch(() => _units.map(_copy).toList());

  @override
  Stream<Map<String, dynamic>?> watchMyActiveOrder() =>
      _watch(() => _active.isEmpty ? null : _copy(_active.last));

  @override
  Future<Map<String, dynamic>> createOrder({
    required String pangkalanId,
    required String driverUnitId,
    required String paymentMethod,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    String? destinationName,
    String? destinationAddress,
    double? distanceKm,
    int? offeredFare,
  }) async {
    final unit = _unitById(driverUnitId);
    if (!SupabaseService.isBookable(unit)) {
      throw EnjoilyException('UNIT_UNAVAILABLE', '${unitLabel(driverUnitId)} sedang tidak siap');
    }
    final pangkalan = _find(_pangkalan, pangkalanId, 'Pangkalan');
    final destination = destinationName == null
        ? null
        : (pangkalan['destinations'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((d) => d['name'] == destinationName);
    final km = destination != null ? (destination['distance_km'] as num).toDouble() : distanceKm ?? 0;
    final freePay = isFreePay(km, destination?['free_pay'] == true);
    final fare = calculateFare(km, offeredFare ?? 0, freePay: freePay);
    if (paymentMethod == 'saldo' && (_profile['ewallet_balance'] as int) < fare) {
      throw EnjoilyException('INSUFFICIENT_BALANCE', 'Saldo tidak cukup');
    }
    final order = {
      'id': 'demo-order-${_nextId++}',
      'passenger_uid': _uid,
      'driver_unit_id': driverUnitId,
      'driver_auth_uid': unit['driver_uid'],
      'pangkalan': pangkalanId,
      'pickup_address': pickupAddress,
      'destination_address': destinationName ?? destinationAddress,
      'distance_km': km,
      'is_free_pay': freePay,
      'offered_fare': offeredFare,
      'total_fare': fare,
      'status': 'pending',
      'payment_method': paymentMethod,
      'payment_status': 'unpaid',
      'created_at': DateTime.now().toIso8601String(),
    };
    _orders.add(order);
    _notify();
    return _copy(order);
  }

  @override
  Future<Map<String, dynamic>> cancelOrder(String orderId, {String? reason}) async {
    final order = _order(orderId);
    order['status'] = 'cancelled';
    final unit = _unitById(order['driver_unit_id'] as String);
    if (unit['status'] == 'on_trip') unit['status'] = 'ready';
    _notify();
    return _copy(order);
  }

  @override
  Future<Map<String, dynamic>> rateOrder(String orderId, int rating, {String? comment}) async =>
      _copy(_order(orderId));

  @override
  Future<Map<String, dynamic>> getOrderContacts(String orderId) async {
    final unit = _unitById(_order(orderId)['driver_unit_id'] as String);
    return {
      'driver_name': unit['driver_name'],
      'vehicle_model': unit['vehicle_model'],
      'license_plate': unit['license_plate'],
      'driver_phone': '0812-0000-0000',
      'passenger_name': _profile['display_name'],
      'passenger_phone': '0813-0000-0000',
    };
  }

  // ---------------------------------------------------------------------
  // Pembayaran (dianggap lunas setelah [_payDelay])
  // ---------------------------------------------------------------------

  Map<String, dynamic> _fakeGateway(String method, String? bank) => {
        'qr_string': method == 'qr' ? '00020101021226DEMO-QRIS-ENJOILY' : null,
        'va_number': method == 'va' ? '8808 0000 1234 5678' : null,
        'bank': bank,
        'expires_at': 'demo — otomatis lunas dalam 2 detik',
      };

  @override
  Future<Map<String, dynamic>> createTopup(int amount, String method, {String? bank}) async {
    final bonus = amount >= 100000 ? 5000 : (amount >= 50000 ? 2500 : 0);
    Timer(_payDelay, () {
      _profile['ewallet_balance'] = (_profile['ewallet_balance'] as int) + amount + bonus;
      _notify();
    });
    return {'amount': amount, 'bonus': bonus, ..._fakeGateway(method, bank)};
  }

  @override
  Future<Map<String, dynamic>> createOrderPayment(String orderId, {String? bank}) async {
    final order = _order(orderId);
    Timer(_payDelay, () {
      order['payment_status'] = 'paid';
      _notify();
    });
    return _fakeGateway(order['payment_method'] as String, bank);
  }

  // ---------------------------------------------------------------------
  // Driver
  // ---------------------------------------------------------------------

  @override
  Stream<Map<String, dynamic>?> watchMyUnit() => _watch(() => _copy(_units.first));

  /// Demo login sebagai admin: semua order aktif tampil di tab Driver.
  @override
  Stream<List<Map<String, dynamic>>> watchDriverOrders() =>
      _watch(() => _active.toList().reversed.map(_copy).toList());

  @override
  Future<void> setUnitOnline(String unitId, bool online) async {
    _unitById(unitId)['is_online'] = online;
    _notify();
  }

  @override
  Future<void> setUnitStatus(String unitId, String status) async {
    _unitById(unitId)['status'] = status;
    _notify();
  }

  @override
  Future<void> setUnitPangkalan(String unitId, String pangkalanId) async {
    _unitById(unitId)['current_pangkalan'] = pangkalanId;
    _notify();
  }

  @override
  Future<void> updateUnitLocation(String unitId, double lat, double lng) async {}

  @override
  Future<Map<String, dynamic>> driverAcceptOrder(String orderId) async {
    final order = await _step(orderId, 'pending', 'accepted');
    _unitById(order['driver_unit_id'] as String)['status'] = 'on_trip';
    _notify();
    return order;
  }

  @override
  Future<Map<String, dynamic>> driverArrive(String orderId) => _step(orderId, 'accepted', 'arrived');

  @override
  Future<Map<String, dynamic>> driverStartTrip(String orderId) => _step(orderId, 'arrived', 'on_trip');

  @override
  Future<Map<String, dynamic>> completeOrder(String orderId, {bool cashReceived = false}) async {
    final order = _order(orderId);
    final fare = order['total_fare'] as int;
    if (order['payment_method'] == 'saldo') {
      final balance = _profile['ewallet_balance'] as int;
      if (balance < fare) throw EnjoilyException('INSUFFICIENT_BALANCE', 'Saldo penumpang kurang');
      _profile['ewallet_balance'] = balance - fare;
    }
    final unit = _unitById(order['driver_unit_id'] as String);
    unit['status'] = 'ready';
    unit['total_trips_today'] = (unit['total_trips_today'] as int) + 1;
    unit['earnings_today'] = (unit['earnings_today'] as int) + fare;
    order['status'] = 'completed';
    order['payment_status'] = 'paid';
    _notify();
    return _copy(order);
  }
}
