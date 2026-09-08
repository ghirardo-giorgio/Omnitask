import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask/main.dart';
import 'package:omnitask/models/connection_settings.dart';
import 'package:omnitask/services/bridge_client.dart';
import 'package:omnitask/screens/connection_screen.dart';
import 'package:omnitask/screens/dashboard_screen.dart';
import 'package:omnitask/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La prima configurazione deve valere subito: prima si arrivava alla
/// dashboard solo riavviando l'app, perche' la schermata veniva scelta una
/// volta sola all'avvio.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Il wakelock e' un plugin: in test non c'e' nessuno schermo da tenere
  // acceso, e senza questo la dashboard non si monta.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/wakelock_plus'),
      (call) async => call.method == 'isEnabled' ? false : null,
    );
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('impostata la connessione si passa alla dashboard senza riavviare',
      (tester) async {
    final settings = SettingsService(await SharedPreferences.getInstance());
    final client = _OfflineClient();
    await tester.pumpWidget(OmnitaskApp(settings: settings, client: client));
    expect(find.byType(ConnectionScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(0), '127.0.0.1');
    await tester.enterText(find.byType(TextField).at(1), '8770');
    await tester.enterText(find.byType(TextField).at(2), '12345');
    await tester.tap(find.text('Collega'));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(ConnectionScreen), findsNothing);
    expect(client.connectedTo?.host, '127.0.0.1');
  });

  testWidgets('dimenticare il PC riporta alla schermata di connessione',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'connessione': '{"indirizzo":"127.0.0.1","porta":8770,"token":"12345"}',
    });
    final settings = SettingsService(await SharedPreferences.getInstance());
    final client = _OfflineClient();
    await tester.pumpWidget(OmnitaskApp(settings: settings, client: client));
    expect(find.byType(DashboardScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Connessione'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dimentica questo PC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dimentica'));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(find.byType(DashboardScreen), findsNothing);
    expect(settings.configured, isFalse);
    expect(client.disconnections, 1);
  });
}

/// Un canale che registra cosa gli e' stato chiesto senza aprire niente: qui
/// si prova la navigazione, non il protocollo — quello ha il suo test contro
/// un ponte vero.
class _OfflineClient extends BridgeClient {
  ConnectionSettings? connectedTo;
  int disconnections = 0;

  @override
  void connect(ConnectionSettings settings) => connectedTo = settings;

  @override
  void disconnect() => disconnections++;
}
