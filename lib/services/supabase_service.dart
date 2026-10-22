import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error dari RPC / Edge Function. Pesan server diawali kode, mis.
/// "INSUFFICIENT_BALANCE: Saldo tidak cukup", dipecah jadi [code] + [message].
class EnjoilyException implements Exception {
  EnjoilyException(this.code, this.message);

  factory EnjoilyException.from(Object error) {
    String raw;
    if (error is PostgrestException) {
      raw = error.message;
    } else if (error is FunctionException) {
      final details = error.details;
      raw = details is Map
          ? '${details['code'] ?? 'ERROR'}: ${details['message'] ?? details['error'] ?? error.reasonPhrase}'
          : '${error.reasonPhrase ?? details}';
    } else if (error is AuthException) {
      raw = 'AUTH: ${error.message}';
    } else {
      raw = error.toString();
    }
    final match = RegExp(r'^([A-Z_]+):\s*(.*)$', dotAll: true).firstMatch(raw);
    if (match == null) return EnjoilyException('UNKNOWN', raw);
    return EnjoilyException(match.group(1)!, match.group(2)!);
  }

  final String code;
  final String message;

  @override
  String toString() => message;
}

class SupabaseService {
  SupabaseService([this._clientOverride]);

  final SupabaseClient? _clientOverride;

  // Diambil saat dipakai, agar DemoService tidak butuh Supabase.initialize.
  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  static const activeOrderStatuses = ['pending', 'accepted', 'arrived', 'on_trip'];

  SupabaseClient get client => _client;
  String? get uid => _client.auth.currentUser?.id;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (e) {
      throw EnjoilyException.from(e);
    }
  }

  Future<Map<String, dynamic>> _rpc(String fn, Map<String, dynamic> params) {
    return _guard(() async {
      final result = await _client.rpc(fn, params: params);
      return Map<String, dynamic>.from(result as Map);
    });
  }

  // ---------------------------------------------------------------------
  // Auth & profil
  // ---------------------------------------------------------------------

  Future<void> signInWithPassword(String email, String password) =>
      _guard(() => _client.auth.signInWithPassword(email: email, password: password));

  Future<void> signUpPassenger(String email, String password, String name) => _guard(
      () => _client.auth.signUp(email: email, password: password, data: {'full_name': name}));

  /// Deep link kembali ke aplikasi setelah login Google di Android/iOS. Harus juga
  /// didaftarkan di Supabase → Authentication → URL Configuration → Redirect URLs.
  /// Di web cukup kembali ke halaman yang sama (null).
  static const oauthRedirect = 'io.supabase.enjoilypangkalan://login-callback/';

  Future<void> signInWithGoogle() => _guard(() => _client.auth
      .signInWithOAuth(OAuthProvider.google, redirectTo: kIsWeb ? null : oauthRedirect));

  /// "0812…" / "812…" / "+62812…" → "+62812…" (format E.164 yang diminta Supabase).
  static String normalizePhone(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('62')) return '+$digits';
    if (digits.startsWith('0')) return '+62${digits.substring(1)}';
    return '+62$digits';
  }

  /// Kirim kode OTP lewat WhatsApp. Butuh Phone provider (Twilio / WhatsApp)
  /// aktif di Supabase → Authentication → Providers.
  Future<void> sendWhatsAppOtp(String phone) => _guard(() => _client.auth
      .signInWithOtp(phone: normalizePhone(phone), channel: OtpChannel.whatsapp));

  Future<void> verifyPhoneOtp(String phone, String token) => _guard(() => _client.auth
      .verifyOTP(phone: normalizePhone(phone), token: token, type: OtpType.sms));

  Future<void> signOut() => _client.auth.signOut();

  /// Baris public.users milik user login (dibuat otomatis oleh trigger).
  Stream<Map<String, dynamic>?> watchMyProfile() {
    return _client
        .from('users')
        .stream(primaryKey: ['id'])
        .eq('id', uid!)
        .map((rows) => rows.isEmpty ? null : rows.first);
  }

  Future<Map<String, dynamic>?> fetchMyProfile() =>
      _guard(() => _client.from('users').select().eq('id', uid!).maybeSingle());

  Future<void> updatePhone(String phone) =>
      _guard(() => _client.from('users').update({'phone': phone}).eq('id', uid!));

  // ---------------------------------------------------------------------
  // Data penumpang
  // ---------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> fetchPangkalan() => _guard(() => _client
      .from('pangkalan')
      .select()
      .eq('is_active', true)
      .order('name'));

  /// Status tampilan 3 keadaan seperti prototipe: unit 'ready' yang Offline
  /// tidak bisa dipesan, jadi ditampilkan sebagai 'rest'.
  static String displayStatus(Map<String, dynamic> unit) {
    final status = unit['status'] as String? ?? 'rest';
    if (status == 'ready' && unit['is_online'] != true) return 'rest';
    return status;
  }

  static bool isBookable(Map<String, dynamic> unit) =>
      displayStatus(unit) == 'ready' && unit['verification_status'] == 'approved';

  /// Unit terverifikasi di pangkalan ini (real-time), urut id. Unit yang belum
  /// siap tetap ikut agar tampil nonaktif; cek dengan [isBookable].
  Stream<List<Map<String, dynamic>>> watchUnitsAtPangkalan(String pangkalanId) {
    return _client
        .from('drivers_units')
        .stream(primaryKey: ['id'])
        .eq('current_pangkalan', pangkalanId)
        .order('id', ascending: true)
        .map((rows) => rows.where((u) => u['verification_status'] == 'approved').toList());
  }

  /// Semua unit (tab Driver), urut id.
  Stream<List<Map<String, dynamic>>> watchAllUnits() {
    return _client.from('drivers_units').stream(primaryKey: ['id']).order('id', ascending: true);
  }

  /// Order aktif penumpang (null bila tidak ada).
  Stream<Map<String, dynamic>?> watchMyActiveOrder() {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('passenger_uid', uid!)
        .order('created_at')
        .map((rows) {
          final active = rows.where((o) => activeOrderStatuses.contains(o['status']));
          return active.isEmpty ? null : active.last;
        });
  }

  // ---------------------------------------------------------------------
  // RPC penumpang
  // ---------------------------------------------------------------------

  /// Isi [destinationName] (tujuan dari pangkalan.destinations), ATAU
  /// [destinationAddress] + [distanceKm].
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
  }) {
    return _rpc('create_order', {
      'p_pangkalan_id': pangkalanId,
      'p_driver_unit_id': driverUnitId,
      'p_payment_method': paymentMethod,
      'p_pickup_address': pickupAddress,
      'p_pickup_lat': pickupLat,
      'p_pickup_lng': pickupLng,
      'p_destination_name': destinationName,
      'p_destination_address': destinationAddress,
      'p_distance_km': distanceKm,
      'p_offered_fare': offeredFare,
    });
  }

  Future<Map<String, dynamic>> cancelOrder(String orderId, {String? reason}) =>
      _rpc('cancel_order', {'p_order_id': orderId, 'p_reason': reason});

  Future<Map<String, dynamic>> rateOrder(String orderId, int rating, {String? comment}) =>
      _rpc('rate_order', {'p_order_id': orderId, 'p_rating': rating, 'p_comment': comment});

  Future<Map<String, dynamic>> getOrderContacts(String orderId) =>
      _rpc('get_order_contacts', {'p_order_id': orderId});

  // ---------------------------------------------------------------------
  // Edge Function (payment gateway)
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> _invoke(String fn, Map<String, dynamic> body) {
    return _guard(() async {
      final res = await _client.functions.invoke(fn, body: body);
      return Map<String, dynamic>.from(res.data as Map);
    });
  }

  /// [method] 'qr' | 'va'; [bank] wajib untuk VA: bca, bni, bri, permata.
  Future<Map<String, dynamic>> createTopup(int amount, String method, {String? bank}) =>
      _invoke('create-topup', {'amount': amount, 'method': method, 'bank': ?bank});

  /// QRIS / VA untuk order > 3 km yang dibayar via QR/VA.
  Future<Map<String, dynamic>> createOrderPayment(String orderId, {String? bank}) =>
      _invoke('create-order-payment', {'order_id': orderId, 'bank': ?bank});

  // ---------------------------------------------------------------------
  // Driver
  // ---------------------------------------------------------------------

  /// Unit milik driver yang login (null bila akun belum dihubungkan ke unit).
  Stream<Map<String, dynamic>?> watchMyUnit() {
    return _client
        .from('drivers_units')
        .stream(primaryKey: ['id'])
        .eq('driver_uid', uid!)
        .map((rows) => rows.isEmpty ? null : rows.first);
  }

  /// Order aktif untuk unit driver (real-time), terbaru di atas.
  Stream<List<Map<String, dynamic>>> watchDriverOrders() {
    return _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('driver_auth_uid', uid!)
        .order('created_at', ascending: false)
        .map((rows) => rows.where((o) => activeOrderStatuses.contains(o['status'])).toList());
  }

  Future<void> setUnitOnline(String unitId, bool online) =>
      _guard(() => _client.from('drivers_units').update({'is_online': online}).eq('id', unitId));

  /// Hanya 'ready' atau 'rest' (dibatasi trigger guard_drivers_units_update).
  Future<void> setUnitStatus(String unitId, String status) =>
      _guard(() => _client.from('drivers_units').update({'status': status}).eq('id', unitId));

  /// Pindah pangkalan setelah mengantar.
  Future<void> setUnitPangkalan(String unitId, String pangkalanId) => _guard(() =>
      _client.from('drivers_units').update({'current_pangkalan': pangkalanId}).eq('id', unitId));

  Future<void> updateUnitLocation(String unitId, double lat, double lng) => _guard(() => _client
      .from('drivers_units')
      .update({'current_lat': lat, 'current_lng': lng}).eq('id', unitId));

  Future<Map<String, dynamic>> driverAcceptOrder(String orderId) =>
      _rpc('driver_accept_order', {'p_order_id': orderId});

  Future<Map<String, dynamic>> driverArrive(String orderId) =>
      _rpc('driver_arrive', {'p_order_id': orderId});

  Future<Map<String, dynamic>> driverStartTrip(String orderId) =>
      _rpc('driver_start_trip', {'p_order_id': orderId});

  /// [cashReceived] wajib true untuk order tunai.
  Future<Map<String, dynamic>> completeOrder(String orderId, {bool cashReceived = false}) =>
      _rpc('complete_order', {'p_order_id': orderId, 'p_cash_received': cashReceived});
}
