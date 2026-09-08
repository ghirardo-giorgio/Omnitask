import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../theme/app_colors.dart';

/// Il grafico della dashboard, rifatto qui.
///
/// Ricalca `Sparkline.qml`: linea piu' area sfumata sotto, i valori recenti a
/// destra, nessun autoscale (il fondoscala arriva col dato). Una seconda
/// serie si disegna sopra la prima — download e upload, lettura e scrittura.
///
/// L'ancoraggio a destra e' la parte che conta e l'unica non ovvia: la
/// larghezza di un campione si calcola su quanti ne entrano in tutto, non su
/// quanti ce ne sono adesso, cosi' una serie appena nata resta incollata al
/// bordo destro e cresce verso sinistra invece di allargarsi da sola come
/// una fisarmonica.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.series,
    this.second,
    this.slots = 60,
    this.height,
    this.fallbackColor = AppColors.accent,
    this.secondFallbackColor = AppColors.busy,
  });

  final Series? series;
  final Series? second;

  /// Quanti campioni entrano nel grafico a pieno carico: sessanta, come il
  /// buffer della dashboard.
  final int slots;
  final double? height;
  final Color fallbackColor;
  final Color secondFallbackColor;

  @override
  Widget build(BuildContext context) {
    final scale = _scale();
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          first: series,
          second: second,
          slots: slots,
          scale: scale,
          firstColor: AppColors.parse(series?.color, fallbackColor),
          secondColor: AppColors.parse(second?.color, secondFallbackColor),
        ),
      ),
    );
  }

  /// Un fondoscala per tutte e due le serie: scalarle una per una farebbe
  /// sembrare grande l'upload di una rete ferma quanto il download di una
  /// che scarica.
  double _scale() {
    var scale = series?.scaleFor() ?? 1;
    final other = second?.scaleFor();
    if (other != null && other > scale) scale = other;
    return scale > 0 ? scale : 1;
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.first,
    required this.second,
    required this.slots,
    required this.scale,
    required this.firstColor,
    required this.secondColor,
  });

  final Series? first;
  final Series? second;
  final int slots;
  final double scale;
  final Color firstColor;
  final Color secondColor;

  @override
  void paint(Canvas canvas, Size size) {
    _plot(canvas, size, second, secondColor);
    _plot(canvas, size, first, firstColor);
  }

  void _plot(Canvas canvas, Size size, Series? series, Color color) {
    if (series == null) return;
    final values = series.values;
    if (values.length < 2) return;

    final slot = size.width / (slots - 1);
    double xOf(int i) => size.width - (values.length - 1 - i) * slot;
    double yOf(double v) =>
        size.height - (v / scale).clamp(0.0, 1.0) * (size.height - 2) - 1;

    // Un buco spezza la linea invece di valere zero: e' un dato che non c'e',
    // non un dato uguale a niente.
    final segments = <List<Offset>>[];
    var current = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) {
        if (current.length > 1) segments.add(current);
        current = <Offset>[];
        continue;
      }
      current.add(Offset(xOf(i), yOf(v)));
    }
    if (current.length > 1) segments.add(current);
    if (segments.isEmpty) return;

    for (final points in segments) {
      final area = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        area.lineTo(point.dx, point.dy);
      }
      area
        ..lineTo(points.last.dx, size.height)
        ..lineTo(points.first.dx, size.height)
        ..close();

      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.0)],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
      );

      final line = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        line.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.first != first ||
      old.second != second ||
      old.scale != scale ||
      old.firstColor != firstColor ||
      old.secondColor != secondColor;
}
