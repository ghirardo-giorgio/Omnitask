import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/module_card.dart';
import '../widgets/sparkline.dart';

/// Battito e braccialetto.
///
/// Il battito non e' campionato come il resto: un punto al minuto, e con dei
/// buchi dove il braccialetto non ha mandato niente. I buchi restano buchi —
/// la linea si spezza — perche' uno zero al loro posto disegnerebbe un
/// arresto cardiaco ogni volta che l'orologio e' sul comodino.
Widget heartModule(Snapshot snapshot) {
  final series = snapshot.series('heart');
  if (series == null) {
    return const ModuleCard(title: 'Battito', child: ModulePlaceholder());
  }
  final latest = series.latest;
  if (series.isEmpty) {
    return const ModuleCard(
      title: 'Battito',
      child: ModulePlaceholder(message: 'nessuna lettura dal braccialetto'),
    );
  }
  final known = series.values.whereType<double>().toList();
  final min = known.reduce((a, b) => a < b ? a : b);
  final max = known.reduce((a, b) => a > b ? a : b);
  return ModuleCard(
    title: 'Battito',
    subtitle: '${min.toStringAsFixed(0)}–${max.toStringAsFixed(0)} bpm',
    value: latest == null ? '—' : latest.toStringAsFixed(0),
    valueColor: AppColors.urgent,
    child: Sparkline(
      series: series,
      height: AppMetrics.sparklineHeight,
      slots: series.values.length,
      fallbackColor: AppColors.urgent,
    ),
  );
}

Widget inspireModule(Snapshot snapshot) {
  final entities = snapshot['home_assistant']?['entities'] as List?;
  if (entities == null) {
    return const ModuleCard(title: 'Inspire 3', child: ModulePlaceholder());
  }
  Map? find(String id) {
    for (final entity in entities.whereType<Map>()) {
      if (entity['entity_id'] == id) return entity;
    }
    return null;
  }

  final battery = find('sensor.inspire_3_battery');
  final sync = find('sensor.inspire_3_last_sync_time');
  final level = double.tryParse(battery?['state']?.toString() ?? '');
  return ModuleCard(
    title: 'Inspire 3',
    value: level == null ? '—' : '${level.toStringAsFixed(0)}%',
    valueColor: level == null
        ? null
        : (level < 20 ? AppColors.urgent : (level < 40 ? AppColors.warning : AppColors.ok)),
    child: Column(
      children: [
        StatBar(
          label: 'Batteria',
          percent: level ?? 0,
          value: level == null ? '—' : '${level.toStringAsFixed(0)}%',
          color: level == null
              ? AppColors.faint
              : (level < 20 ? AppColors.urgent : AppColors.ok),
        ),
        ValueRow(
          name: 'Ultima sincronizzazione',
          value: sync?['state']?.toString().split('T').last.split('.').first ?? '—',
        ),
      ],
    ),
  );
}

// --- quanto occupano -------------------------------------------------------

double heartHeight(Snapshot snapshot) {
  final series = snapshot.series('heart');
  if (series == null || series.isEmpty) return AppMetrics.cardWithChart();
  return AppMetrics.cardWithChart(subtitle: true);
}

double inspireHeight(Snapshot snapshot) {
  if (snapshot['home_assistant']?['entities'] == null) {
    return AppMetrics.cardWithChart();
  }
  // Una barra per la batteria e una riga per l'ultima sincronizzazione.
  return AppMetrics.card(AppMetrics.statBarRow + AppMetrics.rowHeight);
}
