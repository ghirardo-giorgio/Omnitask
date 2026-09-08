import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask/models/connection_settings.dart';
import 'package:omnitask/services/activity_monitor.dart';
import 'package:omnitask/services/bridge_client.dart';

/// Prova la catena intera contro un ponte vero: app → TLS → phone_bridge.py →
/// `qs ipc` → dashboard.
///
/// Si salta da sola se il ponte non e' in ascolto, cosi' `flutter test` gira
/// anche su una macchina che non ha la dashboard davanti. Il token si legge
/// dove lo scrive il ponte.
void main() {
  const host = '127.0.0.1';
  const port = 8770;

  late String token;

  setUpAll(() {
    final config = File(
        '${Platform.environment['HOME']}/.config/quickshell/phone-bridge.json');
    token = config.existsSync()
        ? (jsonDecode(config.readAsStringSync())['token']?.toString() ?? '')
        : '';
  });

  Future<bool> bridgeIsUp() async {
    try {
      final socket = await Socket.connect(host, port,
          timeout: const Duration(milliseconds: 500));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  test('si collega, sottoscrive e riceve i dati che ha chiesto', () async {
    if (token.isEmpty || !await bridgeIsUp()) {
      markTestSkipped('il ponte non è in ascolto su $host:$port');
      return;
    }

    final client = BridgeClient();
    addTearDown(client.dispose);

    client.connect(const ConnectionSettings(host: host, port: port, token: '')
        .copyWith(token: token));

    // Autenticazione.
    await _until(() => client.connected, 'connessione');
    expect(client.connectionSecure, isTrue, reason: 'il ponte genera un certificato da solo');
    expect(client.peerFingerprint, isNotNull);
    expect(client.availableModules, contains('cpu'));
    expect(client.hostName, isNotNull);

    // Solo due moduli: quello che non si guarda non deve arrivare.
    client.subscribe({'cpu', 'ram'}, {'cpu', 'memory'});

    // Si aspetta la serie che si è chiesta, non una serie qualunque: con un
    // altro telefono collegato, «`series` è arrivato» era vero anche quando
    // dentro c'erano le metriche dell'altro.
    await _until(
      () => client.snapshot['overview'] != null && client.snapshot.series('cpu') != null,
      'primo dato',
    );

    final cpu = client.snapshot['overview']?['cpu'];
    expect(cpu?['busy_percent'], isA<num>());
    expect(cpu?['threads'], isA<num>());

    final series = client.snapshot.series('cpu');
    expect(series, isNotNull);
    expect(series!.values, isNotEmpty);
    expect(series.max, 100);
    expect(series.color, startsWith('#'));

    // La rete non era fra i moduli chiesti, quindi non deve essere arrivata.
    expect(client.snapshot.series('net_rx'), isNull);
    expect(client.snapshot['connections'], isNull);
    expect(client.snapshot['health'], isNull);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('cambiare sezione cambia quello che il ponte interroga', () async {
    if (token.isEmpty || !await bridgeIsUp()) {
      markTestSkipped('il ponte non è in ascolto su $host:$port');
      return;
    }

    final client = BridgeClient();
    addTearDown(client.dispose);
    client.connect(ConnectionSettings(host: host, port: port, token: token));
    await _until(() => client.connected, 'connessione');

    // Prima sezione: sistema.
    client.subscribe({'cpu'}, {'cpu'});
    await _until(() => client.snapshot['overview'] != null, 'sistema');
    expect(client.snapshot['health'], isNull);

    // Si passa alla salute: arriva quella, e lo snapshot riparte da capo —
    // quello che non si guarda piu' non resta a schermo come se fosse
    // ancora aggiornato.
    client.subscribe({'health', 'disks'}, {});
    await _until(() => client.snapshot['health'] != null, 'salute');
    final disks = client.snapshot['health']?['disks'];
    expect(disks, isA<List>());

    // Le entita' di Home Assistant si chiedono per nome, separate dalle
    // serie: l'Inspire 3 vuole due stati e nessun grafico.
    client.subscribe({'inspire'}, {},
        {'sensor.inspire_3_battery', 'sensor.inspire_3_last_sync_time'});
    await _until(() => client.snapshot['home_assistant'] != null, 'home assistant');
    final ha = client.snapshot['home_assistant'];
    expect(ha?['ok'], anyOf(isTrue, isFalse),
        reason: 'risponde comunque, anche se Home Assistant è spento');
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('la sorveglianza manda i punteggi anche senza moduli sottoscritti',
      () async {
    if (token.isEmpty || !await bridgeIsUp()) {
      markTestSkipped('il ponte non è in ascolto su $host:$port');
      return;
    }

    final client = BridgeClient();
    addTearDown(client.dispose);

    Map<String, double>? scores;
    client.onActivity = (fresh) => scores = fresh;

    client.connect(ConnectionSettings(host: host, port: port, token: token));
    await _until(() => client.connected, 'connessione');

    // Nessun modulo, nessuna serie: si guarda un'altra pagina. I punteggi
    // devono arrivare lo stesso, o la vista dinamica non saprebbe mai che
    // sta succedendo qualcosa mentre si guarda altrove.
    client.subscribe({}, {}, {}, true);
    await _until(() => scores != null, 'primi punteggi');

    expect(scores!['cpu'], isA<double>());
    expect(scores!['ram'], isA<double>());
    // Nessun dato di modulo: solo i punteggi.
    expect(client.snapshot['overview'], isNull);

    // I punteggi finiscono nel monitor come farebbe l'app.
    final monitor = ActivityMonitor();
    addTearDown(monitor.dispose);
    monitor.candidates = {'cpu', 'ram', 'net', 'disks', 'temps'};
    monitor.update(scores!);
    expect(monitor.active, isNotEmpty,
        reason: 'a riposo mostra comunque i più alti');
    expect(monitor.active.first.score,
        greaterThanOrEqualTo(monitor.active.last.score),
        reason: 'il più urgente è il primo');
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('un carico vero fa salire la CPU sopra la soglia', () async {
    if (token.isEmpty || !await bridgeIsUp()) {
      markTestSkipped('il ponte non è in ascolto su $host:$port');
      return;
    }

    final client = BridgeClient();
    addTearDown(client.dispose);
    final monitor = ActivityMonitor();
    addTearDown(monitor.dispose);
    monitor.candidates = {'cpu', 'topcpu'};

    client.onActivity = monitor.update;
    client.connect(ConnectionSettings(host: host, port: port, token: token));
    await _until(() => client.connected, 'connessione');
    client.subscribe({}, {}, {}, true);
    await _until(() => monitor.scores.isNotEmpty, 'primi punteggi');

    // Tutti i thread al massimo, con la priorità più bassa possibile.
    final threads = Platform.numberOfProcessors;
    final load = <Process>[];
    for (var i = 0; i < threads; i++) {
      load.add(await Process.start('nice', ['-n', '19', 'yes'],
          mode: ProcessStartMode.detached));
    }
    addTearDown(() {
      for (final process in load) {
        process.kill();
      }
    });

    try {
      await _until(
        () => monitor.active.any((m) => m.id == 'cpu' && !m.calm),
        'la CPU entra in attività',
      );
      // La classifica segue il suo modulo: quando la CPU è al massimo la
      // domanda dopo è sempre «chi».
      expect(monitor.active.map((m) => m.id), contains('topcpu'));
      expect(monitor.active.first.id, anyOf('cpu', 'topcpu'));
    } finally {
      for (final process in load) {
        process.kill();
      }
    }

    // Spento il carico, resta dentro: è la permanenza minima, non un
    // ritardo.
    await Future<void>.delayed(const Duration(seconds: 6));
    expect(monitor.active.map((m) => m.id), contains('cpu'),
        reason: 'venti secondi di permanenza minima non sono ancora passati');
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('un token sbagliato viene rifiutato senza riprovare', () async {
    if (!await bridgeIsUp()) {
      markTestSkipped('il ponte non è in ascolto');
      return;
    }
    final client = BridgeClient();
    addTearDown(client.dispose);
    client.connect(const ConnectionSettings(host: host, port: port, token: '00000'));

    await _until(() => client.lastFailureReason != null, 'rifiuto');
    expect(client.connected, isFalse);
    expect(client.lastFailureReason, contains('token'));
  }, timeout: const Timeout(Duration(seconds: 20)));
}

/// Aspetta che una condizione diventi vera, o fallisce dicendo cosa aspettava.
Future<void> _until(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    if (done()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('ho aspettato invano: $what');
}
