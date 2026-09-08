import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/format.dart';
import '../widgets/module_card.dart';
import '../widgets/sparkline.dart';

Widget netModule(Snapshot snapshot) {
  final net = snapshot['overview']?['network'] as Map<String, dynamic>?;
  if (net == null) {
    return const ModuleCard(title: 'Rete', child: ModulePlaceholder());
  }
  final rx = net['rx_bytes_per_second'] as num?;
  final tx = net['tx_bytes_per_second'] as num?;
  return ModuleCard(
    title: 'Rete',
    subtitle: net['interface']?.toString(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _traffic('↓', formatBytes(rx, perSecond: true), AppColors.accent),
            const SizedBox(width: AppMetrics.gap),
            _traffic('↑', formatBytes(tx, perSecond: true), AppColors.busy),
          ],
        ),
        const SizedBox(height: AppMetrics.gapSmall),
        // Le due direzioni condividono il fondoscala, come sul desktop:
        // scalarle a parte farebbe sembrare uguali un upload di due kilobyte
        // e un download di venti megabyte.
        Sparkline(
          series: snapshot.series('net_rx'),
          second: snapshot.series('net_tx'),
          height: AppMetrics.sparklineHeight,
        ),
      ],
    ),
  );
}

Widget _traffic(String arrow, String value, Color color) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(arrow, style: TextStyle(color: color, fontSize: 15)),
      const SizedBox(width: AppMetrics.gapTiny),
      Text(
        value,
        style: const TextStyle(
          color: AppColors.foreground,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

Widget connectionsModule(Snapshot snapshot) {
  final connections = snapshot['connections'];
  if (connections == null) {
    return const ModuleCard(title: 'Connessioni', child: ModulePlaceholder());
  }
  final peers = (connections['peers'] as List?) ?? const [];
  final countries = (connections['countries'] as List?) ?? const [];
  final lan = connections['lan_peers'] as num? ?? 0;
  final loopback = connections['loopback_peers'] as num? ?? 0;

  return ModuleCard(
    title: 'Connessioni',
    subtitle: countries.isEmpty
        ? null
        : countries
            .whereType<Map>()
            .take(3)
            .map((c) => '${c['iso']} ${c['peers']}')
            .join(' · '),
    value: peers.length.toString(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final peer in peers.whereType<Map>().take(8))
          ValueRow(
            name: '${peer['process']} → ${_where(peer)}',
            // Un indirizzo pubblico che il database non sa collocare non e'
            // la stessa cosa di uno che non ha risposto: qui si dice quale
            // dei due, invece di lasciare una riga vuota.
            value: peer['country']?.toString().isNotEmpty == true
                ? peer['country'].toString()
                : 'senza luogo',
            valueColor: peer['approximate'] == true ? AppColors.faint : null,
          ),
        if (lan > 0 || loopback > 0)
          Padding(
            padding: const EdgeInsets.only(top: AppMetrics.gapSmall),
            child: Text(
              'più $lan in rete locale e $loopback interne',
              style: const TextStyle(color: AppColors.faint, fontSize: 10),
            ),
          ),
      ],
    ),
  );
}

String _where(Map peer) {
  final hostname = peer['hostname']?.toString() ?? '';
  return hostname.isNotEmpty ? hostname : (peer['ip']?.toString() ?? '');
}

// --- quanto occupano -------------------------------------------------------

double netHeight(Snapshot snapshot) {
  if (snapshot['overview']?['network'] == null) {
    return AppMetrics.cardWithChart();
  }
  // Le due frecce col traffico, poi il grafico.
  return AppMetrics.card(
    AppMetrics.rowText + AppMetrics.gapSmall + AppMetrics.sparklineHeight,
    subtitle: true,
  );
}

double connectionsHeight(Snapshot snapshot) {
  final connections = snapshot['connections'];
  if (connections == null) return AppMetrics.cardWithChart();
  final peers = (connections['peers'] as List?) ?? const [];
  final shown = peers.length > 8 ? 8 : peers.length;
  final lan = connections['lan_peers'] as num? ?? 0;
  final loopback = connections['loopback_peers'] as num? ?? 0;
  return AppMetrics.cardWithRows(shown, subtitle: true) +
      (lan > 0 || loopback > 0 ? AppMetrics.gapSmall + AppMetrics.tempLabel : 0);
}
