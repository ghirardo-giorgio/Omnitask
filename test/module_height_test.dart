import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask/models/snapshot.dart';
import 'package:omnitask/modules/registry.dart';
import 'package:omnitask/theme/app_colors.dart';

/// Le stime di altezza dei moduli contro la loro altezza vera.
///
/// La vista dinamica decide quanti riquadri mettere in pagina **prima** di
/// costruirli, chiedendo a ogni modulo quanto occuperà. Sono stime scritte a
/// mano, quindi si disallineano appena qualcuno cambia un'imbottitura o
/// aggiunge una riga — e si disallineano in silenzio: il sintomo è una card
/// che sborda dal fondo dello schermo, che nessuno collega alla riga di
/// codice che l'ha causato.
///
/// Qui ogni modulo viene renderizzato con dati veri quanto basta e misurato.
/// Sottostimare è il difetto che conta (la pagina trabocca), sovrastimare
/// spreca solo un po' di spazio: le due tolleranze sono diverse apposta.
void main() {
  const width = 400.0; // un iPhone 11 in punti logici

  /// Una macchina con tutto acceso: il caso peggiore per le altezze.
  Snapshot fullSnapshot() {
    final snapshot = Snapshot();
    snapshot.absorb({
      'overview': {
        'cpu': {
          'busy_percent': 94.2,
          'threads': 16,
          'model': 'AMD Ryzen 9 5900X 12-Core Processor',
        },
        'memory': {
          'used_percent': 55.5,
          'used_bytes': 18000000000,
          'total_bytes': 32000000000,
          'swap_used_bytes': 400000000,
        },
        'gpu': {
          'busy_percent': 62,
          'vram_used_bytes': 6000000000,
          'vram_total_bytes': 12000000000,
          'celsius': 64,
          'model': 'NVIDIA GeForce RTX 3080',
        },
        'network': {
          'interface': 'eno1',
          'rx_bytes_per_second': 18118211,
          'tx_bytes_per_second': 233619,
        },
        'power_watts': 210,
        'busiest': {
          'cpu': [
            {'name': 'code', 'percent_of_all_threads': 41.2},
            {'name': 'brave', 'percent_of_all_threads': 22.0},
            {'name': 'python3', 'percent_of_all_threads': 8.4},
          ],
          'memory': [
            {'name': 'brave', 'resident_bytes': 4200000000},
            {'name': 'code', 'resident_bytes': 2100000000},
            {'name': 'gnome-shell', 'resident_bytes': 900000000},
          ],
        },
      },
      'top_gpu': {
        'ok': true,
        'resource': 'gpu',
        'unit': 'percent',
        'processes': [
          {'name': 'code', 'pid': 1, 'user': 'oberon', 'value': 22},
          {'name': 'brave', 'pid': 2, 'user': 'oberon', 'value': 8},
        ],
      },
      'health': {
        'uptime_seconds': 260000,
        'oom_kills_since_boot': 0,
        'oom_kills_since_dashboard_started': 0,
        'network_errors': {'rxErrors': 0, 'rxDropped': 2},
        'smart_access': 'ok',
        'disks_failing': ['nvme0n1 (Fanxiang S770 2TB)'],
        'disks_needing_attention': ['sdc (CT1000BX500SSD1)'],
        'temperatures_celsius': [
          for (var i = 0; i < 8; i++)
            {'sensor': 'Composite $i', 'chip': 'nvme', 'disk': 'nvme$i',
             'celsius': 60 + i, 'critical_at': 90},
        ],
        'disks': [
          for (var i = 0; i < 6; i++)
            {'name': 'disk$i', 'model': 'Un modello lungo $i',
             'total_bytes': 2000000000000, 'used_bytes': 900000000000,
             'used_percent': 45 + i, 'rotational': false,
             'health': {'verdict': i == 0 ? 'failing' : 'ok'}},
        ],
      },
      'pressure': {
        'waiting': {'cpu': 3.1, 'io': 22.0, 'memory': 0},
        'memory': {'swap_in_bytes_per_s': 0},
        'holders': [
          for (var i = 0; i < 5; i++)
            {'name': 'cgroup$i', 'memory_bytes': 4000000000, 'shmem_bytes': 1000000},
        ],
      },
      'connections': {
        'ok': true,
        'peers': [
          for (var i = 0; i < 9; i++)
            {'process': 'brave', 'pid': i, 'ip': '1.2.3.$i', 'hostname': '',
             'port': 443, 'country': 'The Netherlands', 'approximate': false},
        ],
        'countries': [
          {'name': 'The Netherlands', 'iso': 'NL', 'peers': 5},
        ],
        'lan_peers': 3,
        'loopback_peers': 2,
      },
      'phones': {
        'ok': true,
        'devices': [
          {'name': 'moto g24', 'reachable': true, 'paired': true,
           'battery': {'percent': 8, 'charging': false}},
          {'name': 'OPG02', 'reachable': true, 'paired': true,
           'battery': {'percent': 74, 'charging': true}},
        ],
      },
      'home_assistant': {
        'ok': true,
        'entities_total': 214,
        'chosen': [
          'sensor.solare_usb_potenza',
          'sensor.ac_camera_mia_temperature',
          'sensor.co2_monitor_co2',
          'sensor.igrometro_umidita',
          'sensor.inspire_3_battery',
        ],
        'chosen_without_chart': [],
        'entities': [
          {'entity_id': 'sensor.solare_usb_potenza', 'name': 'Potenza', 'state': '2.021', 'unit': 'W'},
          {'entity_id': 'sensor.igrometro_umidita', 'name': 'Umidità', 'state': '78', 'unit': '%'},
          {'entity_id': 'sensor.inspire_3_battery', 'name': 'Batteria', 'state': '14', 'unit': '%'},
          {'entity_id': 'sensor.inspire_3_last_sync_time', 'name': 'Sync', 'state': '2026-09-08T11:00:00', 'unit': ''},
          {'entity_id': 'weather.casa', 'name': 'Casa', 'state': 'sunny', 'unit': ''},
        ],
      },
      'series': {
        'series': {
          for (final metric in [
            'cpu', 'memory', 'gpu', 'vram', 'net_rx', 'net_tx',
            'power_cpu', 'power_gpu', 'psi_cpu', 'psi_io', 'psi_mem', 'freq',
            'heart', 'ha:sensor.solare_usb_potenza', 'ha:sensor.igrometro_umidita',
            'ha:sensor.ac_camera_mia_temperature', 'ha:sensor.co2_monitor_co2',
            'ha:sensor.inspire_3_battery',
          ])
            metric: {
              'values': [for (var i = 0; i < 60; i++) 40 + i % 20],
              'unit': 'percent',
              'max': 100,
              'color': '#58a6ff',
            },
        },
      },
    });
    return snapshot;
  }

  for (final entry in moduleRegistry.entries) {
    testWidgets('la stima di ${entry.key} regge il confronto col vero',
        (tester) async {
      final snapshot = fullSnapshot();
      final key = GlobalKey();

      await tester.pumpWidget(MaterialApp(
        theme: AppColors.theme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: width,
              child: KeyedSubtree(
                key: key,
                child: Builder(
                  builder: (context) => entry.value.build(context, snapshot),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();

      final real = tester.getSize(find.byKey(key)).height;
      final guess = entry.value.height(snapshot);

      // Sottostimare fa sbordare la pagina: è il difetto che conta, e ha la
      // tolleranza stretta.
      expect(guess, greaterThan(real * 0.80),
          reason: '${entry.key}: stimati ${guess.round()} pt, ne occupa '
              '${real.round()} — la pagina sborderà');
      // Sovrastimare costa solo un posto sprecato in pagina.
      expect(guess, lessThan(real * 1.60),
          reason: '${entry.key}: stimati ${guess.round()} pt, ne occupa '
              '${real.round()} — si perde un posto per niente');
    });
  }
}
