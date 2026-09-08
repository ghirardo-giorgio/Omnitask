import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/donut.dart';
import '../widgets/format.dart';
import '../widgets/module_card.dart';
import '../widgets/sparkline.dart';

/// La sezione Salute: le cose che si rompono in silenzio. Tutte da `health`,
/// che si interroga ogni trenta secondi perche' sotto c'e' SMART, che si
/// aggiorna ogni cinque minuti.

Widget tempsModule(Snapshot snapshot) {
  final rows = snapshot['health']?['temperatures_celsius'] as List?;
  if (rows == null) {
    return const ModuleCard(title: 'Temperature', child: ModulePlaceholder());
  }
  final sensors = rows.whereType<Map>().toList();
  if (sensors.isEmpty) {
    return const ModuleCard(
      title: 'Temperature',
      child: ModulePlaceholder(message: 'nessun sensore leggibile'),
    );
  }
  return ModuleCard(
    title: 'Temperature',
    subtitle: 'i più caldi',
    // Prima era una barra di riempimento per sensore. Di una temperatura pero'
    // si guarda il numero, non quanto e' "piena": tre colonne di numeri stanno
    // in un terzo dell'altezza e si leggono tutte in un colpo d'occhio.
    child: moduleGrid(
      [for (final row in sensors) _TempTile(row: row)],
      columns: 3,
    ),
  );
}

class _TempTile extends StatelessWidget {
  const _TempTile({required this.row});

  final Map row;

  @override
  Widget build(BuildContext context) {
    final celsius = (row['celsius'] as num?)?.toDouble() ?? 0;
    // Il fondoscala e' il punto critico di quel sensore, non cento: una CPU a
    // 80 gradi e' vicina al limite, un disco a 80 e' oltre.
    final limit = (row['critical_at'] as num?)?.toDouble() ?? 90;
    final name = row['disk']?.toString().isNotEmpty == true
        ? '${row['disk']} · ${row['sensor']}'
        : row['sensor']?.toString() ?? '';
    return Column(
      children: [
        Text(
          name,
          maxLines: 2,
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: AppMetrics.tempLabel,
            height: 1.2,
          ),
        ),
        const SizedBox(height: AppMetrics.gapTiny),
        Text(
          formatCelsius(celsius),
          style: TextStyle(
            color: AppColors.forPercent(celsius / limit * 100),
            fontSize: AppMetrics.tempValue,
            fontWeight: FontWeight.w700,
            height: 1,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

Widget disksModule(Snapshot snapshot) {
  final health = snapshot['health'];
  final disks = health?['disks'] as List?;
  if (disks == null) {
    return const ModuleCard(title: 'Dischi', child: ModulePlaceholder());
  }
  final rows = disks.whereType<Map>().toList();
  if (rows.isEmpty) {
    return const ModuleCard(
      title: 'Dischi',
      child: ModulePlaceholder(message: 'nessun disco fisico rilevato'),
    );
  }
  final failing = (health?['disks_failing'] as List?) ?? const [];
  final warning = (health?['disks_needing_attention'] as List?) ?? const [];
  return ModuleCard(
    title: 'Dischi',
    subtitle: failing.isNotEmpty
        ? 'in avaria: ${failing.join(', ')}'
        : (warning.isNotEmpty ? 'da tenere d\'occhio: ${warning.join(', ')}' : null),
    // "Quanto e' pieno" e' una quota di un totale, ed e' la cosa che una torta
    // dice meglio di qualunque barra: il pieno e il vuoto si vedono insieme.
    child: moduleGrid(
      [for (final disk in rows) _DiskTile(disk: disk)],
      columns: 2,
    ),
  );
}

class _DiskTile extends StatelessWidget {
  const _DiskTile({required this.disk});

  final Map disk;

  @override
  Widget build(BuildContext context) {
    final percent = (disk['used_percent'] as num?)?.toDouble() ?? -1;
    final verdict = (disk['health'] as Map?)?['verdict']?.toString();
    final device = disk['name']?.toString() ?? '';
    final model = disk['model']?.toString() ?? '';
    // `nvme0n1` non dice quale disco sia; il modello si'. Il device resta
    // sotto in piccolo, perche' e' il nome con cui compare ovunque altro —
    // nei verdetti SMART qui sopra, in `lsblk`, nei messaggi del kernel.
    final label = model.isNotEmpty ? model : device;
    final sublabel = model.isNotEmpty && device.isNotEmpty ? device : null;

    // -1 vuol dire "so quanto e' grande, non quanto e' pieno": lo dice la
    // dashboard e va detto anche qui, invece di disegnare un anello vuoto che
    // sembra un disco libero.
    final known = percent >= 0;
    final color = verdict == 'failing'
        ? AppColors.urgent
        : (verdict == 'warning'
            ? AppColors.warning
            : (known ? AppColors.forPercent(percent) : AppColors.faint));

    return DonutTile(
      percent: known ? percent : null,
      color: color,
      label: label,
      sublabel: sublabel,
      detail: known
          ? '${formatBytes(disk['used_bytes'])} / ${formatBytes(disk['total_bytes'])}'
          : formatBytes(disk['total_bytes'] as num?),
    );
  }
}

Widget healthModule(Snapshot snapshot) {
  final health = snapshot['health'];
  if (health == null) {
    return const ModuleCard(title: 'Stato sistema', child: ModulePlaceholder());
  }
  final oom = health['oom_kills_since_boot'] as num?;
  final smart = health['smart_access']?.toString() ?? '';
  final errors = health['network_errors'] as Map?;
  final netErrors = errors == null
      ? 0
      : errors.values.whereType<num>().fold<num>(0, (sum, v) => sum + v);
  return ModuleCard(
    title: 'Stato sistema',
    value: formatDuration(health['uptime_seconds'] as num?),
    child: Column(
      children: [
        ValueRow(
          name: 'Processi uccisi per memoria',
          value: oom == null ? '—' : oom.toString(),
          valueColor: (oom ?? 0) > 0 ? AppColors.warning : null,
          dot: (oom ?? 0) > 0 ? AppColors.warning : AppColors.ok,
        ),
        ValueRow(
          name: 'Errori di rete',
          value: netErrors.toString(),
          valueColor: netErrors > 0 ? AppColors.warning : null,
          dot: netErrors > 0 ? AppColors.warning : AppColors.ok,
        ),
        ValueRow(
          name: 'Lettura SMART',
          value: smart.isEmpty ? 'ok' : 'non disponibile',
          valueColor: smart.isEmpty ? null : AppColors.warning,
          dot: smart.isEmpty ? AppColors.ok : AppColors.warning,
        ),
      ],
    ),
  );
}

Widget pressureModule(Snapshot snapshot) {
  final pressure = snapshot['pressure'];
  final waiting = pressure?['waiting'] as Map?;
  if (waiting == null) {
    return const ModuleCard(title: 'Pressione', child: ModulePlaceholder());
  }
  final holders = (pressure?['holders'] as List?) ?? const [];
  return ModuleCard(
    title: 'Pressione',
    subtitle: 'quanto si aspetta invece di lavorare',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Sparkline(
          series: snapshot.series('psi_cpu'),
          second: snapshot.series('psi_mem'),
          height: AppMetrics.sparklineHeight,
          fallbackColor: AppColors.ok,
        ),
        const SizedBox(height: AppMetrics.gapSmall),
        StatBar(
          label: 'CPU',
          percent: (waiting['cpu'] as num?)?.toDouble() ?? 0,
          value: formatPercent(waiting['cpu'] as num?),
        ),
        StatBar(
          label: 'Disco',
          percent: (waiting['io'] as num?)?.toDouble() ?? 0,
          value: formatPercent(waiting['io'] as num?),
        ),
        StatBar(
          label: 'Memoria',
          percent: (waiting['memory'] as num?)?.toDouble() ?? 0,
          value: formatPercent(waiting['memory'] as num?),
        ),
        if (holders.isNotEmpty) ...[
          const SizedBox(height: AppMetrics.gapSmall),
          const Text(
            'CHI TIENE LA MEMORIA',
            style: TextStyle(color: AppColors.faint, fontSize: 10, letterSpacing: 1),
          ),
          // Chi aspetta e chi ha preso la memoria sono due elenchi diversi, e
          // confonderli e' l'errore che questo modulo esiste per evitare: in
          // cima a chi aspetta ci sono le vittime, non i colpevoli.
          for (final holder in holders.whereType<Map>().take(4))
            ValueRow(
              name: holder['name']?.toString() ?? '',
              value: formatBytes(holder['memory_bytes'] as num?),
            ),
        ],
      ],
    ),
  );
}

// --- quanto occupano -------------------------------------------------------
// Le stime che la vista dinamica usa per decidere quanti riquadri stanno in
// una pagina. Sono le stesse formule del `build` qui sopra, lette al
// contrario: se si aggiunge una riga la' va aggiunta qui, e
// `test/module_height_test.dart` se ne accorge se non succede.

double tempsHeight(Snapshot snapshot) {
  final rows = snapshot['health']?['temperatures_celsius'] as List?;
  if (rows == null || rows.isEmpty) return AppMetrics.cardWithChart();
  return AppMetrics.cardWithGrid(rows.length, 3, AppMetrics.tempTile);
}

double disksHeight(Snapshot snapshot) {
  final health = snapshot['health'];
  final disks = health?['disks'] as List?;
  if (disks == null || disks.isEmpty) return AppMetrics.cardWithChart();
  final hasSubtitle = ((health?['disks_failing'] as List?) ?? const []).isNotEmpty ||
      ((health?['disks_needing_attention'] as List?) ?? const []).isNotEmpty;
  return AppMetrics.cardWithGrid(
    disks.length,
    2,
    AppMetrics.donutTile,
    subtitle: hasSubtitle,
  );
}

double healthHeight(Snapshot snapshot) =>
    snapshot['health'] == null
        ? AppMetrics.cardWithChart()
        // Uptime, processi uccisi, errori di rete, lettura SMART.
        : AppMetrics.cardWithRows(3);

double pressureHeight(Snapshot snapshot) {
  final pressure = snapshot['pressure'];
  if (pressure?['waiting'] == null) return AppMetrics.cardWithChart();
  final holders = (pressure?['holders'] as List?) ?? const [];
  final shown = holders.length > 4 ? 4 : holders.length;
  return AppMetrics.card(
    AppMetrics.sparklineHeight +
        AppMetrics.gapSmall +
        AppMetrics.statBarRow * 3 +
        (shown > 0
            ? AppMetrics.gapSmall + AppMetrics.tempLabel + shown * AppMetrics.rowHeight
            : 0),
    subtitle: true,
  );
}
