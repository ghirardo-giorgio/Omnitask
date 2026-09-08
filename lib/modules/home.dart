import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/module_card.dart';
import '../widgets/sparkline.dart';

/// La sezione Casa: Home Assistant e quello che ci passa dentro. Un solo
/// interrogatorio ogni quindici secondi per tutta la sezione — e' un
/// servizio che risponde per HTTP, e chiederglielo due volte al secondo
/// sarebbe scortese oltre che inutile.

Map<String, dynamic>? _entity(Snapshot snapshot, String id) {
  final entities = snapshot['home_assistant']?['entities'] as List?;
  if (entities == null) return null;
  for (final entity in entities.whereType<Map>()) {
    if (entity['entity_id'] == id) return Map<String, dynamic>.from(entity);
  }
  return null;
}

String _stateOf(Map<String, dynamic>? entity) {
  if (entity == null) return '—';
  final unit = entity['unit']?.toString() ?? '';
  final state = entity['state']?.toString() ?? '—';
  final number = double.tryParse(state);
  final shown = number == null ? state : number.toStringAsFixed(number.abs() < 10 ? 2 : 1);
  return unit.isEmpty ? shown : '$shown $unit';
}

Widget homeAssistantModule(Snapshot snapshot) {
  final ha = snapshot['home_assistant'];
  if (ha == null) {
    return const ModuleCard(title: 'Home Assistant', child: ModulePlaceholder());
  }
  if (ha['ok'] == false) {
    return ModuleCard(
      title: 'Home Assistant',
      child: ModulePlaceholder(message: ha['error']?.toString() ?? 'non raggiungibile'),
    );
  }
  // Le entita' sono quelle scelte nelle opzioni del desktop: la scelta e'
  // gia' stata fatta una volta, e rifarla qui vorrebbe dire tenerne due che
  // divergono.
  final chosen = (ha['chosen'] as List?)?.map((e) => e.toString()).toList() ?? const [];
  final noChart = (ha['chosen_without_chart'] as List?)?.map((e) => e.toString()).toSet() ?? {};

  return ModuleCard(
    title: 'Home Assistant',
    subtitle: '${ha['entities_total']} entità',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (chosen.isEmpty)
          const ModulePlaceholder(message: 'nessuna entità scelta nelle opzioni del desktop'),
        for (final id in chosen)
          Builder(builder: (context) {
            final entity = _entity(snapshot, id);
            final series = noChart.contains(id) ? null : snapshot.series('ha:$id');
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ValueRow(
                  name: entity?['name']?.toString() ?? id,
                  value: _stateOf(entity),
                  dot: entity == null ? AppColors.faint : AppColors.ok,
                ),
                if (series != null && !series.isEmpty)
                  Sparkline(series: series, height: 34, slots: series.values.length),
              ],
            );
          }),
      ],
    ),
  );
}

/// Il power bank solare. Sul desktop e' una batteria orizzontale; qui e' la
/// stessa cosa senza il disegno, che su un telefono ruberebbe l'altezza di
/// due moduli.
Widget solarModule(Snapshot snapshot) {
  final power = _entity(snapshot, 'sensor.solare_usb_potenza');
  final charge = _entity(snapshot, 'sensor.solare_usb_carica');
  final voltage = _entity(snapshot, 'sensor.solare_usb_tensione');
  if (snapshot['home_assistant'] == null) {
    return const ModuleCard(title: 'Solare', child: ModulePlaceholder());
  }
  final series = snapshot.series('ha:sensor.solare_usb_potenza');
  return ModuleCard(
    title: 'Solare',
    value: _stateOf(power),
    valueColor: AppColors.warning,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (series != null && !series.isEmpty)
          Sparkline(
            series: series,
            height: AppMetrics.sparklineHeight,
            slots: series.values.length,
            fallbackColor: AppColors.warning,
          ),
        ValueRow(name: 'Carica accumulata', value: _stateOf(charge)),
        ValueRow(name: 'Tensione', value: _stateOf(voltage)),
      ],
    ),
  );
}

Widget igrometroModule(Snapshot snapshot) {
  final humidity = _entity(snapshot, 'sensor.igrometro_umidita');
  if (snapshot['home_assistant'] == null) {
    return const ModuleCard(title: 'Igrometro', child: ModulePlaceholder());
  }
  final value = double.tryParse(humidity?['state']?.toString() ?? '');
  return ModuleCard(
    title: 'Igrometro',
    value: _stateOf(humidity),
    // Le soglie del comfort sono quelle del pannello desktop: sotto 30 o
    // sopra 70 e' rosso, fra 40 e 60 e' verde.
    valueColor: value == null
        ? null
        : (value < 30 || value > 70
            ? AppColors.urgent
            : (value >= 40 && value <= 60 ? AppColors.ok : AppColors.warning)),
    child: Builder(builder: (context) {
      final series = snapshot.series('ha:sensor.igrometro_umidita');
      if (series == null || series.isEmpty) {
        return const ModulePlaceholder(message: 'nessuna lettura');
      }
      return Sparkline(
        series: series,
        height: AppMetrics.sparklineHeight,
        slots: series.values.length,
      );
    }),
  );
}

Widget weatherModule(Snapshot snapshot) {
  final ha = snapshot['home_assistant'];
  if (ha == null) {
    return const ModuleCard(title: 'Meteo', child: ModulePlaceholder());
  }
  final entities = (ha['entities'] as List?) ?? const [];
  final weather = entities
      .whereType<Map>()
      .where((e) => e['entity_id'].toString().startsWith('weather.'))
      .toList();
  if (weather.isEmpty) {
    return const ModuleCard(
      title: 'Meteo',
      // Le previsioni vere richiedono una chiamata di servizio a Home
      // Assistant che passa solo dal desktop: qui c'e' la condizione
      // corrente, che e' quello che si guarda da un telefono.
      child: ModulePlaceholder(message: 'nessuna entità meteo fra quelle scelte'),
    );
  }
  return ModuleCard(
    title: 'Meteo',
    child: Column(
      children: [
        for (final entity in weather)
          ValueRow(
            name: entity['name']?.toString() ?? '',
            value: entity['state']?.toString() ?? '—',
          ),
      ],
    ),
  );
}

// --- quanto occupano -------------------------------------------------------

double homeAssistantHeight(Snapshot snapshot) {
  final ha = snapshot['home_assistant'];
  if (ha == null || ha['ok'] == false) return AppMetrics.cardWithChart();
  final chosen = (ha['chosen'] as List?) ?? const [];
  if (chosen.isEmpty) return AppMetrics.cardWithChart(subtitle: true);
  final noChart = (ha['chosen_without_chart'] as List?)?.map((e) => e.toString()).toSet() ?? {};
  var content = 0.0;
  for (final id in chosen) {
    content += AppMetrics.rowHeight;
    // Le entita' col grafico ne portano uno piccolo sotto la riga.
    final series = snapshot.series('ha:$id');
    if (!noChart.contains(id.toString()) && series != null && !series.isEmpty) {
      content += 34;
    }
  }
  return AppMetrics.card(content, subtitle: true);
}

double solarHeight(Snapshot snapshot) {
  if (snapshot['home_assistant'] == null) return AppMetrics.cardWithChart();
  final series = snapshot.series('ha:sensor.solare_usb_potenza');
  final chart = series != null && !series.isEmpty ? AppMetrics.sparklineHeight : 0.0;
  return AppMetrics.card(chart + AppMetrics.rowHeight * 2);
}

double igrometroHeight(Snapshot snapshot) => AppMetrics.cardWithChart();

double weatherHeight(Snapshot snapshot) {
  final ha = snapshot['home_assistant'];
  if (ha == null) return AppMetrics.cardWithChart();
  final entities = (ha['entities'] as List?) ?? const [];
  final weather = entities
      .whereType<Map>()
      .where((e) => e['entity_id'].toString().startsWith('weather.'))
      .length;
  if (weather == 0) return AppMetrics.cardWithChart();
  return AppMetrics.cardWithRows(weather);
}
