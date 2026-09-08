import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

/// La cornice di ogni modulo: titolo a sinistra, valore grosso a destra,
/// contenuto sotto. Sul desktop ogni pannello se la disegna da se'; qui sono
/// tutti dentro una lista sola, e una cornice comune e' cio' che li fa
/// sembrare una dashboard invece di venti riquadri diversi.
class ModuleCard extends StatelessWidget {
  const ModuleCard({
    super.key,
    required this.title,
    this.value,
    this.valueColor,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? value;
  final Color? valueColor;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppMetrics.gap),
      padding: const EdgeInsets.all(AppMetrics.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Titolo e valore sulla prima riga, sottotitolo sulla seconda. Stavano
          // tutti e tre sulla stessa baseline, e con il valore a 28 punti un
          // modello lungo come "AMD Ryzen 9 5900X 12-Core Processor" si
          // riduceva a tre lettere e un ellissi.
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.foreground,
                    fontSize: AppMetrics.cardTitle,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ?trailing,
              if (value != null)
                Padding(
                  padding: const EdgeInsets.only(left: AppMetrics.gapSmall),
                  child: Text(
                    value!,
                    style: TextStyle(
                      color: valueColor ?? AppColors.foreground,
                      fontSize: AppMetrics.cardValue,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: AppMetrics.gapTiny),
              child: Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.info,
                  fontSize: AppMetrics.cardSubtitle,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(height: AppMetrics.gapSmall),
          child,
        ],
      ),
    );
  }
}

/// Dispone delle celle su piu' colonne, riempiendo di vuoto i buchi dell'ultima
/// riga. Serve alle temperature (tre colonne) e ai dischi (due): senza, le
/// celle dell'ultima riga si allargherebbero per occupare tutto e sarebbero
/// piu' grandi delle altre.
Widget moduleGrid(List<Widget> tiles, {required int columns}) {
  final rows = <Widget>[];
  for (var start = 0; start < tiles.length; start += columns) {
    final slice = tiles.sublist(
      start,
      start + columns > tiles.length ? tiles.length : start + columns,
    );
    rows.add(Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var column = 0; column < columns; column++) ...[
          if (column > 0) const SizedBox(width: AppMetrics.gapSmall),
          Expanded(
            child: column < slice.length ? slice[column] : const SizedBox.shrink(),
          ),
        ],
      ],
    ));
  }
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) const SizedBox(height: AppMetrics.gap),
        rows[i],
      ],
    ],
  );
}

/// Il posto di un modulo che non ha ancora ricevuto niente. Non e' un
/// dettaglio estetico: senza, un modulo appena acceso sembra rotto per i due
/// secondi che passano prima del primo dato.
class ModulePlaceholder extends StatelessWidget {
  const ModulePlaceholder({super.key, this.message = 'in attesa del primo dato…'});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppMetrics.sparklineHeight,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.faint, fontSize: AppMetrics.statValue),
        ),
      ),
    );
  }
}

/// Una riga etichetta / barra / valore, come StatBar.qml.
class StatBar extends StatelessWidget {
  const StatBar({
    super.key,
    required this.label,
    required this.percent,
    this.value,
    this.color,
    this.sublabel,
  });

  final String label;

  /// 0-100. Sopra il 90 diventa rossa da sola, come sul desktop.
  final double percent;
  final String? value;
  final Color? color;
  final String? sublabel;

  @override
  Widget build(BuildContext context) {
    final filled = percent.clamp(0, 100) / 100;
    final tint = color ?? AppColors.forPercent(percent);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppMetrics.gapTiny),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.foreground,
                fontSize: AppMetrics.statLabel,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Container(
                height: AppMetrics.statBarHeight,
                color: AppColors.surfaceHover,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: filled.toDouble(),
                  child: Container(color: tint),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 84,
            child: Text(
              value ?? '${percent.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: AppMetrics.statValue,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Una riga nome / valore, il mattone di ogni elenco: classifiche, sensori,
/// entita' di Home Assistant. Ricalca EntityRow.qml.
class ValueRow extends StatelessWidget {
  const ValueRow({
    super.key,
    required this.name,
    required this.value,
    this.dot,
    this.valueColor,
  });

  final String name;
  final String value;
  final Color? dot;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppMetrics.rowHeight,
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppMetrics.gapSmall),
          ],
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.foreground,
                fontSize: AppMetrics.rowText,
              ),
            ),
          ),
          const SizedBox(width: AppMetrics.gapSmall),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? AppColors.muted,
              fontSize: AppMetrics.rowText,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
