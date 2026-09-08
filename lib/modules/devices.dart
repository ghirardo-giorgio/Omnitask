import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/donut.dart';
import '../widgets/module_card.dart';

/// I telefoni visti da KDE Connect.
///
/// E' l'unico modulo che risponde anche a dashboard spenta: il ponte esegue
/// kdeconnect.py per conto suo, senza passare dall'IPC.
Widget phonesModule(Snapshot snapshot) {
  final phones = snapshot['phones'];
  if (phones == null) {
    return const ModuleCard(title: 'Telefoni', child: ModulePlaceholder());
  }
  if (phones['ok'] == false) {
    return ModuleCard(
      title: 'Telefoni',
      child: ModulePlaceholder(message: phones['error']?.toString() ?? 'KDE Connect non risponde'),
    );
  }
  final devices = (phones['devices'] as List?) ?? const [];
  final paired = devices.whereType<Map>().where((d) => d['paired'] == true).toList();
  if (paired.isEmpty) {
    return const ModuleCard(
      title: 'Telefoni',
      child: ModulePlaceholder(message: 'nessun dispositivo associato'),
    );
  }
  return ModuleCard(
    title: 'Telefoni',
    child: Column(
      children: [
        for (var i = 0; i < paired.length; i++) ...[
          if (i > 0) const SizedBox(height: AppMetrics.gapSmall),
          _PhoneTile(device: paired[i]),
        ],
      ],
    ),
  );
}

/// Un telefono: la carica come anello, il nome grande, lo stato sotto. Era una
/// riga nome/valore identica a quelle delle classifiche dei processi, e due
/// cose diverse che si somigliano si leggono male entrambe.
class _PhoneTile extends StatelessWidget {
  const _PhoneTile({required this.device});

  final Map device;

  @override
  Widget build(BuildContext context) {
    final battery = device['battery'] as Map?;
    final percent = (battery?['percent'] as num?)?.toDouble();
    final charging = battery?['charging'] == true;
    final online = device['reachable'] == true;
    final tint = online ? _batteryColor(percent, charging) : AppColors.faint;

    final status = !online
        ? 'assente'
        : (charging ? 'in carica' : (percent == null ? 'collegato' : 'a batteria'));

    return Container(
      padding: const EdgeInsets.all(AppMetrics.gapSmall),
      decoration: BoxDecoration(
        color: AppColors.surfaceHover,
        borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
      ),
      child: Row(
        children: [
          DonutChart(
            percent: percent,
            color: tint,
            size: 56,
            stroke: 7,
            child: Text(
              percent == null ? '—' : percent.toStringAsFixed(0),
              style: TextStyle(
                color: online ? AppColors.foreground : AppColors.disabled,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: AppMetrics.gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  device['name']?.toString() ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: online ? AppColors.foreground : AppColors.muted,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppMetrics.gapTiny),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: online ? AppColors.ok : AppColors.faint,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppMetrics.gapSmall),
                    Text(
                      status,
                      style: const TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    if (charging) ...[
                      const SizedBox(width: AppMetrics.gapTiny),
                      const Icon(Icons.bolt, size: 15, color: AppColors.ok),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Le soglie di una batteria sono rovesciate rispetto a `AppColors.forPercent`:
/// una CPU al novanta per cento e' un problema, un telefono al novanta e'
/// pieno. Sotto carica non c'e' allarme che tenga — sta gia' risalendo.
Color _batteryColor(double? percent, bool charging) {
  if (percent == null) return AppColors.faint;
  if (charging) return AppColors.ok;
  if (percent <= 15) return AppColors.urgent;
  if (percent <= 30) return AppColors.warning;
  return AppColors.ok;
}
