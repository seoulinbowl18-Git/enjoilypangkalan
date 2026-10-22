import 'package:flutter/material.dart';

import '../ui/enjoily_style.dart';
import '../utils/fare.dart';

/// Tab "Hitung biaya": biaya operasional per km vs tarif. Hanya hitungan lokal.
class CostCalculator extends StatefulWidget {
  const CostCalculator({super.key});

  @override
  State<CostCalculator> createState() => _CostCalculatorState();
}

class _CostCalculatorState extends State<CostCalculator> {
  final _kwhPerKm = TextEditingController(text: '0.15');
  final _rpPerKwh = TextEditingController(text: '2500');
  final _otherPerKm = TextEditingController(text: '800');

  @override
  void dispose() {
    _kwhPerKm.dispose();
    _rpPerKwh.dispose();
    _otherPerKm.dispose();
    super.dispose();
  }

  double _read(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    final costPerKm = _read(_kwhPerKm) * _read(_rpPerKwh) + _read(_otherPerKm);
    final profitPerKm = ratePerKm - costPerKm;
    final minTripProfit = minFare - costPerKm * freePayMaxKm;
    Color tone(num v) => v < 0 ? EnjColors.red : c.accent;
    void recalc(String _) => setState(() {});

    return EnjTabBody(
      children: [
        const EnjH2('Hitung biaya per km'),
        const EnjSub('Angka di bawah hanya contoh. Ganti dengan angka mobilmu.'),
        EnjCard(
          children: [
            EnjField(
                controller: _kwhPerKm, label: 'Konsumsi (kWh/km)', decimal: true, onChanged: recalc),
            EnjField(
                controller: _rpPerKwh, label: 'Tarif listrik (Rp/kWh)', numeric: true, onChanged: recalc),
            EnjField(
              controller: _otherPerKm,
              label: 'Penyusutan, servis, asuransi (Rp/km)',
              numeric: true,
              onChanged: recalc,
            ),
          ],
        ),
        EnjCard(
          children: [
            EnjKv('Biaya per km', rupiah(costPerKm)),
            EnjKv('Untung per km (tarif ${rupiah(ratePerKm)})', rupiah(profitPerKm),
                valueColor: tone(profitPerKm)),
            EnjKv('Trip 3 km bayar minimal ${rupiah(minFare)}', rupiah(minTripProfit),
                valueColor: tone(minTripProfit)),
            const EnjSub('Merah berarti rugi. Belum termasuk biaya jalan kosong menuju penumpang.'),
          ],
        ),
      ],
    );
  }
}
