import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/format.dart';
import '../widgets/module_card.dart';
import '../widgets/sparkline.dart';

/// I moduli della sezione Sistema: quello che la macchina sta facendo
/// adesso. Tutti leggono `overview`, che e' una chiamata sola per tutti e
/// nove.

Widget cpuModule(Snapshot snapshot) {
  final cpu = snapshot['overview']?['cpu'] as Map<String, dynamic>?;
  final busy = (cpu?['busy_percent'] as num?)?.toDouble();
  return ModuleCard(
    title: 'CPU',
    subtitle: cpu?['model']?.toString(),
    value: formatPercent(busy),
    valueColor: busy == null ? null : AppColors.forPercent(busy),
    child: cpu == null
        ? const ModulePlaceholder()
        : Sparkline(
            series: snapshot.series('cpu'),
            height: AppMetrics.sparklineHeight,
            fallbackColor: AppColors.ok,
          ),
  );
}

Widget ramModule(Snapshot snapshot) {
  final memory = snapshot['overview']?['memory'] as Map<String, dynamic>?;
  final used = (memory?['used_percent'] as num?)?.toDouble();
  final swap = memory?['swap_used_bytes'] as num?;
  return ModuleCard(
    title: 'RAM',
    subtitle: memory == null
        ? null
        : '${formatBytes(memory['used_bytes'])} di ${formatBytes(memory['total_bytes'])}'
            '${swap != null && swap > 0 ? ' · swap ${formatBytes(swap)}' : ''}',
    value: formatPercent(used),
    valueColor: used == null ? null : AppColors.forPercent(used),
    child: memory == null
        ? const ModulePlaceholder()
        : Sparkline(
            series: snapshot.series('memory'),
            height: AppMetrics.sparklineHeight,
          ),
  );
}

Widget gpuModule(Snapshot snapshot) {
  final gpu = snapshot['overview']?['gpu'] as Map<String, dynamic>?;
  if (snapshot['overview'] != null && gpu == null) {
    return const ModuleCard(
      title: 'GPU',
      child: ModulePlaceholder(message: 'nessuna GPU rilevata su questa macchina'),
    );
  }
  final busy = (gpu?['busy_percent'] as num?)?.toDouble();
  final celsius = gpu?['celsius'] as num?;
  return ModuleCard(
    title: 'GPU',
    subtitle: gpu?['model']?.toString(),
    value: formatPercent(busy, digits: 0),
    valueColor: busy == null ? null : AppColors.forPercent(busy),
    trailing: celsius == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(right: AppMetrics.gapSmall),
            child: Text(
              formatCelsius(celsius),
              style: TextStyle(color: AppColors.forPercent(celsius / 90 * 100), fontSize: AppMetrics.cardTitle),
            ),
          ),
    child: gpu == null
        ? const ModulePlaceholder()
        : Sparkline(
            series: snapshot.series('gpu'),
            height: AppMetrics.sparklineHeight,
            fallbackColor: AppColors.violet,
          ),
  );
}

Widget vramModule(Snapshot snapshot) {
  final gpu = snapshot['overview']?['gpu'] as Map<String, dynamic>?;
  final used = gpu?['vram_used_bytes'] as num?;
  final total = gpu?['vram_total_bytes'] as num?;
  final percent = (used != null && total != null && total > 0) ? used / total * 100 : null;
  return ModuleCard(
    title: 'VRAM',
    subtitle: used == null ? null : '${formatBytes(used)} di ${formatBytes(total)}',
    value: formatPercent(percent, digits: 0),
    valueColor: percent == null ? null : AppColors.forPercent(percent),
    child: gpu == null
        ? const ModulePlaceholder()
        : Sparkline(
            series: snapshot.series('vram'),
            height: AppMetrics.sparklineHeight,
            fallbackColor: AppColors.violet,
          ),
  );
}

Widget powerModule(Snapshot snapshot) {
  final watts = snapshot['overview']?['power_watts'] as num?;
  final cpu = snapshot.series('power_cpu');
  final gpu = snapshot.series('power_gpu');
  if (snapshot['overview'] != null && watts == null) {
    return const ModuleCard(
      title: 'Consumo',
      child: ModulePlaceholder(message: 'i watt non sono leggibili su questa macchina'),
    );
  }
  return ModuleCard(
    title: 'Consumo',
    subtitle: 'CPU e GPU insieme',
    value: formatWatts(watts),
    child: cpu == null && gpu == null
        ? const ModulePlaceholder()
        // Il grafico del desktop impila i due consumi; qui restano due linee
        // sovrapposte, che su uno schermo stretto si distinguono meglio di
        // due aree una dentro l'altra.
        : Sparkline(
            series: gpu,
            second: cpu,
            height: AppMetrics.sparklineHeight,
            fallbackColor: AppColors.violet,
            secondFallbackColor: AppColors.ok,
          ),
  );
}

Widget freqModule(Snapshot snapshot) {
  final series = snapshot.series('freq');
  final latest = series?.latest;
  return ModuleCard(
    title: 'Frequenza',
    value: latest == null ? '—' : '${(latest / 1000).toStringAsFixed(2)} GHz',
    child: series == null
        ? const ModulePlaceholder()
        : Sparkline(series: series, height: AppMetrics.sparklineHeight),
  );
}

/// Le classifiche. `overview` porta i primi tre per CPU e memoria; la
/// classifica GPU viene da `top`, che e' l'unica a saperne i pid.
Widget topCpuModule(Snapshot snapshot) {
  final rows = snapshot['overview']?['busiest']?['cpu'] as List?;
  return _ranking(
    title: 'Classifica CPU',
    rows: rows,
    label: (row) => row['name']?.toString() ?? '',
    value: (row) => formatPercent(row['percent_of_all_threads'] as num?),
  );
}

Widget topRamModule(Snapshot snapshot) {
  final rows = snapshot['overview']?['busiest']?['memory'] as List?;
  return _ranking(
    title: 'Classifica RAM',
    rows: rows,
    label: (row) => row['name']?.toString() ?? '',
    value: (row) => formatBytes(row['resident_bytes'] as num?),
  );
}

Widget topGpuModule(Snapshot snapshot) {
  final top = snapshot['top_gpu'];
  final rows = top?['processes'] as List?;
  final refused = top != null && top['ok'] == false;
  return _ranking(
    title: 'Classifica GPU',
    rows: rows,
    label: (row) => row['name']?.toString() ?? '',
    value: (row) => formatPercent(row['value'] as num?, digits: 0),
    empty: refused
        ? top['error']?.toString()
        : 'nessun processo sta usando la GPU',
  );
}

Widget _ranking({
  required String title,
  required List? rows,
  required String Function(Map row) label,
  required String Function(Map row) value,
  String? empty,
}) {
  if (rows == null) {
    return ModuleCard(title: title, child: const ModulePlaceholder());
  }
  if (rows.isEmpty) {
    return ModuleCard(
      title: title,
      child: ModulePlaceholder(message: empty ?? 'nessuno'),
    );
  }
  return ModuleCard(
    title: title,
    child: Column(
      children: [
        for (final row in rows.whereType<Map>())
          ValueRow(name: label(row), value: value(row)),
      ],
    ),
  );
}

// --- quanto occupano -------------------------------------------------------

/// Le classifiche: una riga per voce, e quante voci le decide il PC
/// (`topCount` nelle opzioni della dashboard, di solito due o tre).
double rankingHeight(Snapshot snapshot, List? rows) {
  if (rows == null) return AppMetrics.cardWithChart();
  return AppMetrics.cardWithRows(rows.isEmpty ? 1 : rows.length);
}

double topCpuHeight(Snapshot snapshot) =>
    rankingHeight(snapshot, snapshot['overview']?['busiest']?['cpu'] as List?);

double topRamHeight(Snapshot snapshot) =>
    rankingHeight(snapshot, snapshot['overview']?['busiest']?['memory'] as List?);

double topGpuHeight(Snapshot snapshot) =>
    rankingHeight(snapshot, snapshot['top_gpu']?['processes'] as List?);

/// I moduli a grafico portano il sottotitolo col modello o con la misura.
double chartWithSubtitleHeight(Snapshot snapshot) =>
    AppMetrics.cardWithChart(subtitle: true);
