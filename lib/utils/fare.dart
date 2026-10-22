// Aturan tarif — cerminan Custom Functions di spesifikasi dan
// public.calculate_fare di Supabase. Nilai di sini hanya untuk estimasi
// tampilan; tarif final selalu dihitung ulang oleh RPC create_order.

const double freePayMaxKm = 3.0;
const int minFare = 5000;
const int ratePerKm = 4500;

bool isFreePay(double distanceInKm, bool isFreePayDestination) {
  return isFreePayDestination || distanceInKm <= freePayMaxKm;
}

int calculateFare(double distanceInKm, int offeredAmount, {bool freePay = false}) {
  if (freePay || distanceInKm <= freePayMaxKm) {
    // Suka-suka: pakai nominal penumpang, minimal Rp5.000
    return offeredAmount < minFare ? minFare : offeredAmount;
  }
  // Di atas 3 km: tarif tetap, dibulatkan ke Rp500 terdekat
  final raw = distanceInKm * ratePerKm;
  return (raw / 500).round() * 500;
}

List<String> allowedPaymentMethods(bool freePay) {
  // Suka-suka wajib dari saldo; di atas 3 km bebas
  if (freePay) return const ['saldo'];
  return const ['saldo', 'qr', 'va', 'cash'];
}

int topUpShortfall(int fare, int balance) {
  final need = fare - balance;
  if (need <= 0) return 0;
  final rounded = (need / 10000).ceil() * 10000;
  return rounded < 20000 ? 20000 : rounded;
}

/// Rp12500 → "Rp12.500"
String rupiah(num value) {
  final digits = value.round().abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return '${value < 0 ? '-' : ''}Rp$buffer';
}

const paymentMethodLabels = {
  'saldo': 'Saldo',
  'qr': 'QRIS',
  'va': 'Virtual Account',
  'cash': 'Tunai',
};

const orderStatusLabels = {
  'pending': 'Menunggu driver',
  'accepted': 'Driver menuju lokasi',
  'arrived': 'Driver sudah sampai',
  'on_trip': 'Sedang jalan',
  'completed': 'Selesai',
  'cancelled': 'Dibatalkan',
};

/// 'unit_1' → 'Unit 1'; id lain ditampilkan apa adanya.
String unitLabel(String? id) {
  if (id == null) return 'Unit';
  final match = RegExp(r'^unit_(\d+)$').firstMatch(id);
  return match == null ? id : 'Unit ${match.group(1)}';
}

const unitStatusLabels = {
  'ready': 'Siap',
  'rest': 'Istirahat',
  'on_trip': 'Sedang jalan',
};
