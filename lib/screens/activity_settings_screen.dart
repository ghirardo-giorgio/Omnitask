import 'package:flutter/material.dart';

import '../models/activity.dart';
import '../modules/registry.dart';
import '../services/activity_monitor.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';
import '../widgets/pill_switch.dart';

/// Quanto in alto deve stare un modulo per finire nella vista dinamica.
///
/// Ogni riga mostra il punteggio di adesso accanto alla soglia, così si
/// regola guardando il numero vero invece che a memoria: «la rete sta a 95 e
/// non voglio vederla» è una decisione che si prende in un secondo, «ottanta
/// è troppo o troppo poco?» no.
class ActivitySettingsScreen extends StatefulWidget {
  const ActivitySettingsScreen({
    super.key,
    required this.settings,
    required this.monitor,
  });

  final SettingsService settings;
  final ActivityMonitor monitor;

  @override
  State<ActivitySettingsScreen> createState() => _ActivitySettingsScreenState();
}

class _ActivitySettingsScreenState extends State<ActivitySettingsScreen> {
  SettingsService get settings => widget.settings;
  ActivityRules get rules => settings.activityRules;

  @override
  void initState() {
    super.initState();
    widget.monitor.addListener(_onScores);
  }

  @override
  void dispose() {
    widget.monitor.removeListener(_onScores);
    super.dispose();
  }

  void _onScores() {
    if (mounted) setState(() {});
  }

  Future<void> _apply(ActivityRules value) async {
    await settings.setActivityRules(value);
    widget.monitor.rules = value;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scores = widget.monitor.scores;
    final ids = _ordered();

    return Scaffold(
      appBar: AppBar(title: const Text('Soglie di attività')),
      body: ListView(
        padding: const EdgeInsets.all(AppMetrics.cardPadding),
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.activityOn,
            activeThumbColor: AppColors.accent,
            title: const Text('Vista dinamica',
                style: TextStyle(color: AppColors.foreground, fontSize: 14)),
            subtitle: const Text(
              'La prima pagina, con quello che in questo momento merita attenzione',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            onChanged: (value) async {
              await settings.setActivityOn(value);
              setState(() {});
            },
          ),
          const Divider(color: AppColors.borderMuted),
          // Quanti riquadri per pagina non si sceglie più: li conta la vista
          // guardando quanto è alto lo schermo e quanto occupa ognuno coi
          // dati di adesso. Un numero fisso sbagliava in tutte e due le
          // direzioni — tre card leggere lasciavano mezzo schermo vuoto, tre
          // card alte già traboccavano.
          _stepper(
            'Secondi fra una pagina e l\'altra',
            rules.rotateSeconds,
            3,
            60,
            (value) => _apply(rules.copyWith(rotateSeconds: value)),
            step: 1,
          ),
          _stepper(
            'Pausa dopo il tocco, in secondi',
            rules.pauseSeconds,
            5,
            300,
            (value) => _apply(rules.copyWith(pauseSeconds: value)),
            step: 5,
          ),
          const SizedBox(height: AppMetrics.gap),
          const Text(
            'SOGLIE',
            style: TextStyle(
                color: AppColors.muted, fontSize: 10, letterSpacing: 1,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppMetrics.gapTiny),
          const Text(
            'Un modulo entra quando supera la sua soglia, ed esce dieci punti '
            'più in basso. Resta comunque venti secondi, per non comparire e '
            'sparire a ogni picco.\n\n'
            'L\'interruttore ambra dice se un modulo può entrare nella vista: '
            'spento resta acceso nella sua sezione, ma non viene mai a '
            'chiamarti.\n\n'
            'L\'ordine di questa lista è la tua preferenza: fra moduli grosso '
            'modo pari merito viene prima chi sta più in alto. Non scavalca '
            'l\'urgenza — un disco in avaria resta in cima anche se è '
            'l\'ultimo qui.',
            style: TextStyle(color: AppColors.faint, fontSize: 11),
          ),
          const SizedBox(height: AppMetrics.gapSmall),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // La maniglia è esplicita: con quella di serie il trascinamento
            // partirebbe da qualunque punto della riga, cursore dello slider
            // compreso, e regolare una soglia diventerebbe un terno al lotto.
            buildDefaultDragHandles: false,
            onReorder: (from, to) => _reorder(ids, from, to),
            children: [
              for (var index = 0; index < ids.length; index++)
                _thresholdRow(
                  ids[index],
                  scores[ids[index]],
                  index,
                  key: ValueKey(ids[index]),
                ),
            ],
          ),
          const SizedBox(height: AppMetrics.gap * 2),
          const Text(
            'I moduli senza punteggio non entrano mai nella vista: Home Assistant '
            'nel suo insieme e il meteo sono cose che si consultano, non che '
            'chiamano.',
            style: TextStyle(color: AppColors.faint, fontSize: 11),
          ),
        ],
      ),
    );
  }

  /// L'ordine da mostrare: la preferenza salvata, e in coda — nell'ordine
  /// del catalogo — i moduli che non sono ancora stati spostati.
  List<String> _ordered() {
    final known = rules.priority.where(moduleRegistry.containsKey).toList();
    final rest = moduleRegistry.keys.where((id) => !known.contains(id));
    return [...known, ...rest];
  }

  Future<void> _reorder(List<String> ids, int from, int to) async {
    final order = List<String>.from(ids);
    final moved = order.removeAt(from);
    order.insert(to > from ? to - 1 : to, moved);
    await settings.setPriority(order);
    widget.monitor.rules = settings.activityRules;
    setState(() {});
  }

  Widget _thresholdRow(String id, double? score, int index, {Key? key}) {
    final spec = moduleRegistry[id]!;
    final threshold = rules.thresholdFor(id);
    final custom = rules.thresholds.containsKey(id);
    final inside = widget.monitor.active.any((m) => m.id == id && !m.calm);
    final excluded = rules.isExcluded(id);
    // Un modulo senza punteggio non entra comunque: l'interruttore c'è ma
    // non promette niente, e la riga lo dice invece di lasciarlo credere.
    final scorable = score != null;

    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: AppMetrics.gapSmall),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: AppMetrics.gapSmall),
                  child: Icon(Icons.drag_indicator, size: 17, color: AppColors.faint),
                ),
              ),
              GestureDetector(
                onTap: !scorable
                    ? null
                    : () async {
                        await settings.setExcludedFromActivity(id, !excluded);
                        widget.monitor.rules = settings.activityRules;
                        setState(() {});
                      },
                child: PillSwitch(
                  on: scorable && !excluded,
                  // Ambra e non blu: qui l'interruttore non dice «acceso» —
                  // il modulo lo è comunque, nella sua sezione — ma «può
                  // entrare nella vista dinamica».
                  onColor: AppColors.warning,
                ),
              ),
              const SizedBox(width: AppMetrics.gapSmall),
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: inside ? AppColors.warning : AppColors.borderMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppMetrics.gapSmall),
              Expanded(
                child: Text(
                  spec.title,
                  style: TextStyle(
                    color: !scorable || excluded
                        ? AppColors.disabled
                        : AppColors.foreground,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                !scorable
                    ? 'senza punteggio'
                    : (excluded ? 'mai nella vista' : 'adesso ${score.toStringAsFixed(0)}'),
                style: TextStyle(
                  color: !scorable || excluded
                      ? AppColors.faint
                      : AppColors.forPercent(score),
                  fontSize: 11,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: AppMetrics.gapSmall),
              SizedBox(
                width: 34,
                child: Text(
                  excluded ? '—' : threshold.toStringAsFixed(0),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: excluded
                        ? AppColors.faint
                        : (custom ? AppColors.accent : AppColors.muted),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              // Riporta al valore di partenza togliendo la voce, invece di
              // riscriverci sopra il numero predefinito.
              SizedBox(
                width: 32,
                child: custom && !excluded
                    ? IconButton(
                        iconSize: 15,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.restart_alt, color: AppColors.faint),
                        onPressed: () async {
                          await settings.setThreshold(id, null);
                          widget.monitor.rules = settings.activityRules;
                          setState(() {});
                        },
                      )
                    : null,
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor:
                  excluded ? AppColors.borderMuted : AppColors.accentSolid,
              inactiveTrackColor: AppColors.surfaceHover,
              thumbColor: excluded ? AppColors.faint : AppColors.accent,
              disabledActiveTrackColor: AppColors.borderMuted,
              disabledInactiveTrackColor: AppColors.surfaceHover,
              disabledThumbColor: AppColors.faint,
            ),
            child: Slider(
              value: threshold,
              min: 10,
              max: 100,
              divisions: 18,
              onChanged: !scorable || excluded ? null : (value) async {
                await settings.setThreshold(id, value);
                widget.monitor.rules = settings.activityRules;
                setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepper(String label, int value, int min, int max,
      Future<void> Function(int) onChange,
      {int step = 1}) {
    return Row(
      children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(color: AppColors.foreground, fontSize: 13)),
        ),
        IconButton(
          iconSize: 18,
          icon: const Icon(Icons.remove, color: AppColors.muted),
          onPressed: value - step < min ? null : () => onChange(value - step),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.foreground,
              fontSize: 14,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        IconButton(
          iconSize: 18,
          icon: const Icon(Icons.add, color: AppColors.muted),
          onPressed: value + step > max ? null : () => onChange(value + step),
        ),
      ],
    );
  }
}
