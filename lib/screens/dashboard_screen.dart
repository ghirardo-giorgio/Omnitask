import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../models/connection_settings.dart';
import '../modules/registry.dart';
import '../services/activity_monitor.dart';
import '../services/bridge_client.dart';
import '../services/settings_service.dart';
import '../widgets/dynamic_view.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/format.dart';
import 'activity_settings_screen.dart';
import 'connection_screen.dart';
import 'sections_screen.dart';

/// La schermata principale: una pagina per sezione, si passa con lo swipe.
///
/// La sottoscrizione segue la pagina. Aprire la sezione Rete fa interrogare
/// `connections` sul PC; uscirne lo fa smettere entro un giro. E' la ragione
/// per cui le sezioni esistono: su un telefono non ci sta tutto, e chiedere
/// tutto per mostrarne un sesto sarebbe uno spreco su tutte e due le
/// macchine.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.settings,
    required this.client,
    required this.monitor,
  });

  final SettingsService settings;
  final BridgeClient client;
  final ActivityMonitor monitor;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _pages = PageController();
  int _page = 0;

  @override
  void initState() {
    super.initState();
    // Una dashboard si guarda, non si tocca: senza questo lo schermo si
    // spegne mentre si osserva un grafico salire.
    WakelockPlus.enable();
    widget.client.addListener(_onChange);
    widget.settings.addListener(_onChange);
    widget.monitor.addListener(_onActivityChanged);
    widget.client.onActivity = _onScores;
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    widget.client.removeListener(_onChange);
    widget.settings.removeListener(_onChange);
    widget.monitor.removeListener(_onActivityChanged);
    widget.client.onActivity = null;
    _pages.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  void _onScores(Map<String, double> scores) {
    widget.monitor.candidates = widget.settings.activeModules;
    widget.monitor.update(scores);
  }

  /// Quando l'insieme dei moduli in attività cambia, cambia anche cosa
  /// serve scaricare — ma solo se si sta guardando la vista dinamica.
  void _onActivityChanged() {
    if (!mounted) return;
    setState(() {});
    if (_isDynamic(_page)) _subscribe();
  }

  /// La vista dinamica è la pagina zero, quando è accesa.
  bool _isDynamic(int page) => widget.settings.activityOn && page == 0;

  /// Le sezioni come pagine: la vista dinamica in testa, poi quelle fisse.
  List<Section?> get _pageList => [
        if (widget.settings.activityOn) null,
        ...widget.settings.sections,
      ];

  /// Dice al ponte cosa si sta guardando: i moduli della pagina aperta, le
  /// loro serie e le entita' di Home Assistant che gli servono.
  ///
  /// Un messaggio solo, e sostituisce il precedente: il ponte non tiene una
  /// storia delle sottoscrizioni, tiene quella di adesso.
  void _subscribe() {
    final pages = _pageList;
    if (pages.isEmpty) return;
    final current = pages[_page.clamp(0, pages.length - 1)];

    // Sulla vista dinamica i moduli non li sceglie l'utente: sono quelli che
    // in questo momento sono in attività, e cambiano sotto i piedi.
    final modules = current == null
        ? widget.monitor.subscription.where(moduleRegistry.containsKey).toSet()
        : current.modules.where(moduleRegistry.containsKey).toSet();

    widget.client.subscribe(
      modules,
      {for (final id in modules) ...?moduleRegistry[id]?.metrics},
      entitiesFor(modules),
      // La sorveglianza resta accesa anche stando su una sezione fissa: è
      // l'unico modo perché la vista dinamica sappia già cosa mostrare
      // quando ci si torna, invece di ripartire vuota ogni volta.
      widget.settings.activityOn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final client = widget.client;
    final pages = _pageList;
    final current = pages.isEmpty
        ? null
        : pages[_page.clamp(0, pages.length - 1)];

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              pages.isEmpty
                  ? 'Omnitask'
                  : (current?.name ?? SettingsService.activitySection),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            _StatusLine(client: client),
          ],
        ),
        leading: IconButton(
          tooltip: 'Sezioni e moduli',
          icon: const Icon(Icons.tune, size: 20),
          onPressed: () async {
            await Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => SectionsScreen(settings: settings),
            ));
            _subscribe();
            setState(() {});
          },
        ),
        actions: [
          if (settings.activityOn)
            IconButton(
              tooltip: 'Soglie di attività',
              icon: const Icon(Icons.speed, size: 20),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => ActivitySettingsScreen(
                    settings: settings,
                    monitor: widget.monitor,
                  ),
                ));
                setState(() {});
              },
            ),
          IconButton(
            tooltip: 'Connessione',
            icon: const Icon(Icons.settings, size: 20),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (context) =>
                  ConnectionScreen(settings: settings, client: client),
            )),
          ),
        ],
      ),
      body: Column(
        children: [
          if (client.certificateMismatch != null)
            _CertificateWarning(client: client, settings: settings),
          if (client.dashboardError != null) _DashboardDown(client: client),
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: pages.length,
              onPageChanged: (page) {
                setState(() => _page = page);
                _subscribe();
              },
              itemBuilder: (context, index) {
                final section = pages[index];
                if (section == null) {
                  return DynamicView(
                    monitor: widget.monitor,
                    snapshot: client.snapshot,
                  );
                }
                return _section(section);
              },
            ),
          ),
          if (pages.length > 1) _dots(pages.length),
        ],
      ),
    );
  }

  Widget _section(Section section) {
    final modules = section.modules.where(moduleRegistry.containsKey).toList();
    if (modules.isEmpty) {
      return const Center(
        child: Text(
          'Nessun modulo acceso in questa sezione',
          style: TextStyle(color: AppColors.faint, fontSize: 12),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppMetrics.cardPadding),
      children: [
        for (final id in modules)
          moduleRegistry[id]!.build(context, widget.client.snapshot),
      ],
    );
  }

  Widget _dots(int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppMetrics.gap, top: AppMetrics.gapTiny),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var index = 0; index < count; index++)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: index == _page ? AppColors.accent : AppColors.border,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
    );
  }
}

/// Una riga sotto il titolo che dice se i numeri sopra sono di adesso.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.client});

  final BridgeClient client;

  @override
  Widget build(BuildContext context) {
    final (text, color) = switch (client.status) {
      ConnectionStatus.connected => (
          '${client.hostName ?? 'collegato'}'
              '${client.connectionSecure ? '' : ' · in chiaro'}',
          AppColors.ok
        ),
      ConnectionStatus.connecting => ('collegamento…', AppColors.warning),
      ConnectionStatus.disconnected => (
          client.lastFailureReason == null ? 'non collegato' : 'non collegato · riprovo',
          AppColors.urgent
        ),
    };
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppMetrics.gapTiny),
        Text(text, style: const TextStyle(color: AppColors.faint, fontSize: 10)),
      ],
    );
  }
}

/// La dashboard e' spenta: i numeri restano a schermo ma smettono di essere
/// di adesso, e va detto invece di lasciarli fermi.
class _DashboardDown extends StatelessWidget {
  const _DashboardDown({required this.client});

  final BridgeClient client;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.warning.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(
          horizontal: AppMetrics.cardPadding, vertical: AppMetrics.gapSmall),
      child: Text(
        'La dashboard non risponde${client.dashboardDownSince == null ? '' : ' da ${formatAge(client.dashboardDownSince)}'}'
        ' — quello che vedi è vecchio.',
        style: const TextStyle(color: AppColors.warning, fontSize: 11),
      ),
    );
  }
}

/// Il certificato non e' quello di prima. Non si prosegue da soli: o il
/// ponte e' stato reinstallato, o qualcuno sulla rete si sta spacciando per
/// il PC, e da qui le due cose sono identiche.
class _CertificateWarning extends StatelessWidget {
  const _CertificateWarning({required this.client, required this.settings});

  final BridgeClient client;
  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.urgent.withValues(alpha: 0.15),
      padding: const EdgeInsets.all(AppMetrics.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Certificato cambiato',
              style: TextStyle(color: AppColors.urgent, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppMetrics.gapTiny),
          const Text(
            'Il PC si presenta con un certificato diverso da quello accettato la '
            'prima volta. Se hai reinstallato il ponte è normale; altrimenti '
            'qualcuno sulla rete si sta spacciando per il tuo PC.',
            style: TextStyle(color: AppColors.foreground, fontSize: 11),
          ),
          const SizedBox(height: AppMetrics.gapSmall),
          Text(
            'atteso:  ${settings.connection.fingerprint ?? '—'}\n'
            'ricevuto: ${client.certificateMismatch}',
            style: const TextStyle(
                color: AppColors.muted, fontSize: 10, fontFamily: 'monospace'),
          ),
          const SizedBox(height: AppMetrics.gapSmall),
          TextButton(
            onPressed: () async {
              await settings.setConnection(
                settings.connection.copyWith(fingerprint: client.certificateMismatch),
              );
              client.acceptNewCertificate();
            },
            child: const Text('Accetta il nuovo certificato'),
          ),
        ],
      ),
    );
  }
}
