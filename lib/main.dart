import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/strings.dart';
import 'services/activity_monitor.dart';
import 'services/bridge_client.dart';
import 'services/settings_service.dart';
import 'theme/app_colors.dart';
import 'screens/connection_screen.dart';
import 'screens/dashboard_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  Strings.use(settings.language);
  runApp(OmnitaskApp(settings: settings));
}

class OmnitaskApp extends StatefulWidget {
  const OmnitaskApp({
    super.key,
    required this.settings,
    this.client,
    this.monitor,
  });

  final SettingsService settings;

  /// Di norma l'app apre il proprio canale verso il ponte; nei test se ne
  /// passa uno che non tocca la rete.
  final BridgeClient? client;

  /// Chi decide cosa entra nella vista dinamica. Iniettabile per la stessa
  /// ragione del client: nei test lo si guida a mano, con un orologio finto.
  final ActivityMonitor? monitor;

  @override
  State<OmnitaskApp> createState() => _OmnitaskAppState();
}

class _OmnitaskAppState extends State<OmnitaskApp> {
  late final _client = widget.client ?? BridgeClient();

  // Le soglie sono quelle salvate, e i candidati i moduli accesi: la vista
  // dinamica pesca solo fra quelli, così spegnere un modulo lo toglie da
  // tutto invece di vederselo ricomparire proprio quando è in attività.
  late final _monitor = widget.monitor ??
      ActivityMonitor(rules: widget.settings.activityRules)
    ..candidates = widget.settings.activeModules;

  /// Se la connessione era gia' impostata all'ultimo giro. Serve a
  /// distinguere il cambiamento che conta — configurata o no, cioe' quale
  /// schermata sta in cima — dalle altre notifiche delle impostazioni
  /// (moduli accesi, sezioni rinominate) che qui non cambiano niente.
  late bool _configured = widget.settings.configured;

  @override
  void initState() {
    super.initState();
    // Ci si ricollega da soli all'avvio, e dopo ogni caduta: e' un
    // telecomando, non un sito da visitare.
    if (widget.settings.configured) {
      _client.connect(widget.settings.connection);
    }
    _client.addListener(_pinCertificate);
    widget.settings.addListener(_onSettingsChanged);
  }

  /// Appena la connessione viene impostata si passa alla dashboard, e appena
  /// viene azzerata si torna a chiederla. Senza questo la prima
  /// configurazione si vedeva solo riavviando l'app: la schermata era stata
  /// scelta all'avvio e nessuno la ripensava piu'.
  void _onSettingsChanged() {
    final configured = widget.settings.configured;
    if (configured == _configured) return;
    if (!configured) _client.disconnect();
    setState(() => _configured = configured);
  }

  /// Il certificato accettato al primo collegamento si fissa: da li' in poi
  /// uno diverso non passa senza che l'utente lo dica.
  void _pinCertificate() {
    final presented = _client.peerFingerprint;
    if (presented == null || !_client.connected) return;
    if (widget.settings.connection.fingerprint == presented) return;
    if (widget.settings.connection.fingerprint == null) {
      widget.settings.setConnection(
        widget.settings.connection.copyWith(fingerprint: presented),
      );
    }
  }

  @override
  void dispose() {
    widget.settings.removeListener(_onSettingsChanged);
    _client.removeListener(_pinCertificate);
    _client.dispose();
    // Solo quello che si è creato da sé: un monitor passato da fuori lo
    // chiude chi l'ha aperto.
    if (widget.monitor == null) _monitor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Omnitask',
      debugShowCheckedModeBanner: false,
      theme: AppColors.theme(),
      home: _configured
          ? DashboardScreen(
              settings: widget.settings,
              client: _client,
              monitor: _monitor,
            )
          : ConnectionScreen(settings: widget.settings, client: _client),
    );
  }
}
