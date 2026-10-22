import 'package:flutter_test/flutter_test.dart';

import 'package:enjoily_mobile/utils/fare.dart';

void main() {
  test('suka-suka (≤ 3 km) minimal Rp5.000', () {
    expect(calculateFare(2, 3000), 5000);
    expect(calculateFare(3, 8000), 8000);
    expect(calculateFare(5, 0, freePay: true), 5000);
  });

  test('di atas 3 km Rp4.500/km dibulatkan ke Rp500', () {
    expect(calculateFare(5, 0), 22500);
    expect(calculateFare(3.3, 0), 15000); // 14.850 → 15.000
  });

  test('metode bayar & top up', () {
    expect(allowedPaymentMethods(true), ['saldo']);
    expect(allowedPaymentMethods(false), contains('cash'));
    expect(topUpShortfall(8000, 2000), 20000);
    expect(topUpShortfall(35000, 0), 40000);
    expect(rupiah(1250000), 'Rp1.250.000');
  });
}
