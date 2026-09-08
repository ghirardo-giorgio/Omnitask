import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

/// Una ciambella: la quota di un intero, con il numero scritto in mezzo.
///
/// La usano i dischi ("quanto e' pieno") e la batteria dei telefoni. Sono i due
/// posti dove il dato *e'* una proporzione di un totale noto: una barra lunga
/// quanto la card lo direbbe altrettanto bene ma occuperebbe una riga intera,
/// e di dischi ce ne sono quattro.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.percent,
    required this.color,
    this.size = AppMetrics.donut,
    this.stroke = AppMetrics.donutStroke,
    this.child,
  });

  /// 0-100, oppure null quando la quota non si sa: allora resta il solo anello
  /// di fondo. Non e' un caso teorico — il ponte manda `pct: -1` per un disco
  /// di cui conosce la dimensione ma non l'occupazione, e un anello vuoto
  /// disegnato come uno zero direbbe "disco libero", che e' un'altra cosa.
  final double? percent;
  final Color color;
  final double size;
  final double stroke;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DonutPainter(
          percent: percent,
          color: color,
          stroke: stroke,
        ),
        child: child == null ? null : Center(child: child),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.percent, required this.color, required this.stroke});

  final double? percent;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.surfaceHover;
    canvas.drawCircle(center, radius, track);

    final value = percent;
    if (value == null || value <= 0) return;

    final sweep = (value.clamp(0, 100) / 100) * 2 * math.pi;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      // Da mezzogiorno in senso orario: e' il verso in cui si legge un
      // quadrante, e la dashboard di la' disegna DiskGauge allo stesso modo.
      -math.pi / 2,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.percent != percent || old.color != color || old.stroke != stroke;
}

/// Una cella: ciambella, nome sotto, e una riga piccola per il dettaglio.
class DonutTile extends StatelessWidget {
  const DonutTile({
    super.key,
    required this.percent,
    required this.color,
    required this.label,
    this.center,
    this.sublabel,
    this.detail,
    this.size = AppMetrics.donut,
  });

  final double? percent;
  final Color color;
  final String label;

  /// Cosa va dentro l'anello. Di norma la percentuale; per un telefono in
  /// carica ci sta anche il fulmine.
  final Widget? center;
  final String? sublabel;
  final String? detail;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        DonutChart(
          percent: percent,
          color: color,
          size: size,
          child: center ??
              Text(
                percent == null ? '—' : '${percent!.toStringAsFixed(0)}%',
                style: TextStyle(
                  color: percent == null ? AppColors.disabled : AppColors.foreground,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
        ),
        const SizedBox(height: AppMetrics.gapSmall),
        Text(
          label,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.foreground,
            fontSize: AppMetrics.statValue,
            fontWeight: FontWeight.w600,
            height: 1.2,
          ),
        ),
        if (sublabel != null)
          Text(
            sublabel!,
            maxLines: 1,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.faint, fontSize: 11),
          ),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(top: AppMetrics.gapTiny),
            child: Text(
              detail!,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
      ],
    );
  }
}
