import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask/models/connection_settings.dart';
import 'package:omnitask/services/bridge_client.dart';

/// Il cartello «la dashboard non risponde» davanti a numeri che si muovono e'
/// peggio di nessun cartello: dice che quello che si vede e' vecchio proprio
/// mentre e' fresco. Qui si prova che non puo' restare appeso, con un ponte
/// finto che detta la sequenza dei messaggi.
void main() {
  late ServerSocket server;
  late List<Socket> clients;
  late String host;

  setUp(() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    host = server.address.address;
    clients = [];
    server.listen((socket) {
      var buffer = '';
      socket.listen((bytes) {
        // Questo ponte non ha certificato, e l'app prova sempre prima in
        // cifrato: al ClientHello (0x16) si chiude, che e' il rifiuto su cui
        // l'app ripiega in chiaro. Riconoscerla qui evita di aspettare gli
        // otto secondi di timeout.
        if (bytes.isNotEmpty && bytes.first == 0x16) {
          socket.destroy();
          return;
        }
        if (!clients.contains(socket)) clients.add(socket);
        buffer += utf8.decode(bytes);
        while (buffer.contains('\n')) {
          final cut = buffer.indexOf('\n');
          final line = buffer.substring(0, cut);
          buffer = buffer.substring(cut + 1);
          final message = jsonDecode(line) as Map<String, dynamic>;
          // Il ponte risponde all'auth e poi tace: il resto lo dettano i test.
          if (message['cmd'] == 'auth') {
            _write(socket, {
              'type': 'auth',
              'ok': true,
              'host': 'finto',
              'modules': ['cpu'],
            });
          }
        }
      }, onError: (_) {});
    });
  });

  tearDown(() async {
    for (final socket in clients) {
      socket.destroy();
    }
    await server.close();
  });

  BridgeClient connectClient() {
    final client = BridgeClient();
    addTearDown(client.dispose);
    client.connect(
        ConnectionSettings(host: host, port: server.port, token: '12345'));
    return client;
  }

  test('dati freschi tolgono il cartello anche senza `recovered`', () async {
    final client = connectClient();
    await _until(() => client.connected, 'connessione');
    final bridge = clients.single;

    _write(bridge, {
      'type': 'error',
      'error': 'dashboard muta',
      'since': DateTime.now()
              .subtract(const Duration(hours: 3))
              .millisecondsSinceEpoch /
          1000,
    });
    await _until(() => client.dashboardError != null, 'il guasto arriva');

    // Il ponte torna a misurare ma il `recovered` non arriva mai: e' quello
    // che succede quando cade mentre il telefono e' scollegato, o quando il
    // ponte riparte senza memoria del guasto.
    _write(bridge, {
      'type': 'update',
      'sources': {
        'cpu': {'usage': 12},
      },
    });
    await _until(() => client.dashboardError == null, 'il cartello sparisce');
    expect(client.dashboardDownSince, isNull);
  });

  test('kdeconnect da solo non basta a dichiarare viva la dashboard', () async {
    final client = connectClient();
    await _until(() => client.connected, 'connessione');
    final bridge = clients.single;

    _write(bridge, {'type': 'error', 'error': 'dashboard muta', 'since': 1.0});
    await _until(() => client.dashboardError != null, 'il guasto arriva');

    // `phones` risponde anche a dashboard spenta: non dice niente su di lei.
    _write(bridge, {
      'type': 'update',
      'sources': {
        'phones': {'devices': []},
      },
    });
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(client.dashboardError, isNotNull);
  });

  test('il guasto non sopravvive alla sessione in cui e\' stato visto',
      () async {
    final client = connectClient();
    await _until(() => client.connected, 'connessione');

    _write(clients.single, {
      'type': 'error',
      'error': 'dashboard muta',
      'since': 1.0,
    });
    await _until(() => client.dashboardError != null, 'il guasto arriva');

    // Il ponte cade e il telefono si ricollega: se la dashboard e' ancora
    // spenta lo ridice lui, e finche' non lo dice non si afferma niente.
    clients.single.destroy();
    await _until(() => !client.connected, 'la caduta');
    await _until(() => client.connected, 'il ritorno',
        timeout: const Duration(seconds: 10));
    expect(client.dashboardError, isNull);
    expect(client.dashboardDownSince, isNull);
  });
}

void _write(Socket socket, Map<String, dynamic> message) {
  socket.write('${jsonEncode(message)}\n');
}

Future<void> _until(bool Function() done, String what,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) fail('$what: non è arrivato');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
