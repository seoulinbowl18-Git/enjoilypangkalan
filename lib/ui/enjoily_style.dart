import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/fare.dart';

// Token & komponen dari prototipe "Enjoily Pangkalan.html" (.card, .chip, .btn,
// .unit, .tag, .badge, .f, .kv, .pulse). Ubah di sini agar semua tab ikut.

class EnjColors {
  const EnjColors._({
    required this.bg,
    required this.card,
    required this.ink,
    required this.mute,
    required this.line,
    required this.accent,
  });

  static const brand = Color(0xFF12A594);
  static const brand2 = Color(0xFF0C7A6E);
  static const sun = Color(0xFFFFC93C);
  static const red = Color(0xFFE5484D);
  static const sunInk = Color(0xFF12312E);

  static const light = EnjColors._(
    bg: Color(0xFFEEF3F0),
    card: Colors.white,
    ink: Color(0xFF12312E),
    mute: Color(0xFF5E7571),
    line: Color(0xFFDCE6E2),
    accent: brand2,
  );

  static const dark = EnjColors._(
    bg: Color(0xFF0E1A18),
    card: Color(0xFF162825),
    ink: Color(0xFFE8F3F0),
    mute: Color(0xFF8FA8A3),
    line: Color(0xFF243936),
    // brand2 terlalu gelap di atas kartu gelap
    accent: brand,
  );

  final Color bg;
  final Color card;
  final Color ink;
  final Color mute;
  final Color line;

  /// Teks hijau (tab aktif, untung, label "⚡ Mobil listrik").
  final Color accent;

  static EnjColors of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

ThemeData enjoilyTheme(Brightness brightness, String? fontFamily) {
  final c = brightness == Brightness.dark ? EnjColors.dark : EnjColors.light;
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: fontFamily,
    colorScheme: ColorScheme.fromSeed(seedColor: EnjColors.brand, brightness: brightness)
        .copyWith(primary: EnjColors.brand, surface: c.card, onSurface: c.ink, error: EnjColors.red),
    scaffoldBackgroundColor: c.bg,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.ink,
      contentTextStyle: TextStyle(
          color: c.bg, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: fontFamily),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

/// Isi tab: kolom bergulir dengan jarak 12 antar blok (.body).
class EnjTabBody extends StatelessWidget {
  const EnjTabBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          children[i],
        ],
      ],
    );
  }
}

class EnjH2 extends StatelessWidget {
  const EnjH2(this.text, {super.key, this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        textAlign: center ? TextAlign.center : null,
        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: EnjColors.of(context).ink));
  }
}

/// Teks abu-abu kecil (.sub). Pakai [EnjSub.rich] untuk bagian tebal.
class EnjSub extends StatelessWidget {
  const EnjSub(String this.text, {super.key, this.center = false, this.color}) : spans = null;

  const EnjSub.rich(List<InlineSpan> this.spans, {super.key, this.center = false, this.color})
      : text = null;

  final String? text;
  final List<InlineSpan>? spans;
  final bool center;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    return Text.rich(
      TextSpan(text: text, children: spans),
      textAlign: center ? TextAlign.center : null,
      style: TextStyle(fontSize: 13, height: 1.4, color: color ?? c.mute),
    );
  }
}

/// Teks tebal (<b>).
class EnjB extends StatelessWidget {
  const EnjB(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: EnjColors.of(context).ink));
  }
}

TextSpan enjBold(String text) => TextSpan(text: text, style: const TextStyle(fontWeight: FontWeight.w700));

class EnjCard extends StatelessWidget {
  const EnjCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EnjColors.of(context).card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: children),
    );
  }
}

enum EnjButtonKind { primary, alt, ghost }

class EnjButton extends StatelessWidget {
  const EnjButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.kind = EnjButtonKind.primary,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final EnjButtonKind kind;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    final (bg, fg) = switch (kind) {
      EnjButtonKind.primary => (EnjColors.brand, Colors.white),
      EnjButtonKind.alt => (EnjColors.sun, EnjColors.sunInk),
      EnjButtonKind.ghost => (c.bg, c.ink),
    };
    final button = FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: fg,
        disabledBackgroundColor: bg,
        disabledForegroundColor: fg,
        elevation: 0,
        // Web/desktop default-nya compact dan memangkas padding
        visualDensity: VisualDensity.standard,
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: small ? const EdgeInsets.symmetric(horizontal: 14, vertical: 9) : const EdgeInsets.all(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(small ? 12 : 16)),
        textStyle: TextStyle(
          fontSize: small ? 13 : 15,
          fontWeight: FontWeight.w800,
          fontFamily: Theme.of(context).textTheme.labelLarge?.fontFamily,
        ),
      ),
      child: Text(label),
    );
    return Opacity(opacity: onPressed == null ? 0.4 : 1, child: button);
  }
}

class EnjChip extends StatelessWidget {
  const EnjChip(this.label, {super.key, this.selected = false, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    return Material(
      color: selected ? EnjColors.brand : Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: selected ? EnjColors.brand : c.line, width: 1.5)),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(label,
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: selected ? Colors.white : c.ink)),
        ),
      ),
    );
  }
}

class EnjChips extends StatelessWidget {
  const EnjChips({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: children);
}

/// Lingkaran hijau berisi "EV" / emoji (.ava).
class EnjAva extends StatelessWidget {
  const EnjAva(this.text, {super.key, this.size = 44, this.fontSize = 14});

  final String text;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: EnjColors.brand, shape: BoxShape.circle),
      child: Text(text,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: fontSize)),
    );
  }
}

/// Status unit seperti di prototipe: ready = s1, on_trip = s2, rest = abu-abu.
class EnjStatusTag extends StatelessWidget {
  const EnjStatusTag(this.status, {super.key});

  final String status;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    final (bg, fg) = switch (status) {
      'ready' => (const Color(0xFFD4F3EC), EnjColors.brand2),
      'on_trip' => (EnjColors.sun, EnjColors.sunInk),
      _ => (c.bg, c.mute),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Text(unitStatusLabels[status] ?? status,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}

class EnjBadge extends StatelessWidget {
  const EnjBadge(this.text, {super.key, this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: muted ? c.bg : EnjColors.sun, borderRadius: BorderRadius.circular(12)),
        child: Text(text,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: muted ? c.mute : EnjColors.sunInk)),
      ),
    );
  }
}

/// Kotak input bergaris (.f). Tanpa [label], input memenuhi lebar dan rata kiri.
class EnjField extends StatelessWidget {
  const EnjField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.numeric = false,
    this.decimal = false,
    this.obscure = false,
    this.keyboardType,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? label;
  final String? hint;
  final bool numeric;
  final bool decimal;
  final bool obscure;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    final input = TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      obscureText: obscure,
      textAlign: label == null ? TextAlign.start : TextAlign.end,
      keyboardType:
          keyboardType ?? (numeric || decimal ? TextInputType.numberWithOptions(decimal: decimal) : null),
      inputFormatters: numeric && !decimal ? [FilteringTextInputFormatter.digitsOnly] : null,
      style: TextStyle(
          fontSize: label == null ? 14 : 15,
          fontWeight: label == null ? FontWeight.w600 : FontWeight.w800,
          color: c.ink),
      decoration: InputDecoration.collapsed(hintText: hint, hintStyle: TextStyle(color: c.mute)),
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: c.line, width: 1.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: label == null
          ? input
          : Row(
              spacing: 8,
              children: [
                Expanded(
                  child: Text(label!,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
                ),
                SizedBox(width: 90, child: input),
              ],
            ),
    );
  }
}

/// Baris label–nilai bergaris bawah (.kv).
class EnjKv extends StatelessWidget {
  const EnjKv(this.label, this.value, {super.key, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final c = EnjColors.of(context);
    final style = TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(
        spacing: 8,
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style.copyWith(color: valueColor)),
        ],
      ),
    );
  }
}

/// Lingkaran berdenyut saat menunggu driver (.pulse).
class EnjPulse extends StatefulWidget {
  const EnjPulse({super.key});

  @override
  State<EnjPulse> createState() => _EnjPulseState();
}

class _EnjPulseState extends State<EnjPulse> with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value;
            return Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: EnjColors.brand,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: EnjColors.brand.withValues(alpha: 0.5 * (1 - t)),
                    spreadRadius: 30 * t,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
