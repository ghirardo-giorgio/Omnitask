import 'package:flutter/material.dart';

import '../models/snapshot.dart';
import '../modules/registry.dart';
import '../services/activity_monitor.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

/// La vista dinamica: ciò che in questo momento merita di essere guardato,
/// una pagina per volta.
///
/// Il cambio pagina è una dissolvenza e non un secondo `PageView`. Uno
/// annidato si contenderebbe il gesto con lo scroll della lista, e con un
/// modulo alto — le temperature sono otto righe — la pagina supera l'altezza
/// dello schermo: si finirebbe con un trascinamento verso l'alto che a volte
/// scorre e a volte cambia pagina, che è il peggior tipo di interfaccia.
/// Così invece il verticale resta lo scroll, l'orizzontale resta il cambio
/// sezione, e la pagina si sceglie dai puntini.
class DynamicView extends StatelessWidget {
  const DynamicView({
    super.key,
    required this.monitor,
    required this.snapshot,
  });

  final ActivityMonitor monitor;
  final Snapshot snapshot;

  /// Quanti riquadri entrano in [available] punti di altezza.
  ///
  /// Un numero fisso sbagliava in tutte e due le direzioni: tre card leggere
  /// lasciavano mezzo schermo vuoto, tre card alte già traboccavano. Qui si
  /// riempie finché ci sta, guardando quanto ogni modulo dichiara di
  /// occupare coi dati che ha adesso.
  ///
  /// Si conta sulla graduatoria intera, non sui soli moduli in pagina.
  ///
  /// Con quelli non funzionava, e il difetto era circolare: a riposo i
  /// moduli in vista sono già tagliati alla capienza, quindi tre riquadri
  /// entravano in tre posti e la capienza non poteva crescere mai. La
  /// graduatoria contiene anche chi siederebbe, e non dipende da quanti
  /// posti ci sono: è ciò che rompe il cerchio.
  int _capacityFor(double available) {
    var used = 0.0;
    var fit = 0;
    for (final module in monitor.ranked) {
      final spec = moduleRegistry[module.id];
      if (spec == null) continue;
      used += spec.height(snapshot);
      // Un filo di tolleranza: senza, un riquadro che sfora di due punti
      // fa scendere la capienza, al giro dopo ci sta di nuovo, e le pagine
      // si mettono a rimbalzare fra due impaginazioni diverse.
      if (used > available * 1.05) break;
      fit++;
    }
    // Il minimo di tre resta anche quando i riquadri sono alti: una pagina da
    // due card con la rotazione che parte è peggio di un filo di
    // scorrimento.
    return fit < 3 ? 3 : fit;
  }

  @override
  Widget build(BuildContext context) {
    final page = monitor.currentPage;

    // Qualunque tocco ferma la rotazione, compreso l'inizio di uno scroll:
    // se si sta guardando, non deve scappare.
    return Listener(
      onPointerDown: (_) => monitor.pause(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(monitor: monitor),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              // La capienza si comunica al monitor dopo il frame: cambiarla
              // qui dentro vorrebbe dire notificare i listener durante il
              // layout, che Flutter non permette.
              final seats = _capacityFor(
                constraints.maxHeight -
                    AppMetrics.gapSmall -
                    AppMetrics.cardPadding,
              );
              if (seats != monitor.capacity) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => monitor.setCapacity(seats),
                );
              }
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: page.isEmpty
                  ? const _Empty()
                  : ListView(
                      // La chiave dice all'AnimatedSwitcher che è un'altra
                      // pagina: senza, dissolverebbe solo la prima volta.
                      key: ValueKey(monitor.page),
                      padding: const EdgeInsets.fromLTRB(
                        AppMetrics.cardPadding,
                        AppMetrics.gapSmall,
                        AppMetrics.cardPadding,
                        AppMetrics.cardPadding,
                      ),
                      children: [
                        for (final module in page)
                          if (moduleRegistry[module.id] != null)
                            _Scored(
                              score: module.score,
                              calm: module.calm,
                              child: moduleRegistry[module.id]!
                                  .build(context, snapshot),
                            ),
                      ],
                    ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

/// La riga in cima: cosa sta succedendo, a che pagina si è, e perché la
/// pagina si muove — o perché ha smesso.
class _Header extends StatelessWidget {
  const _Header({required this.monitor});

  final ActivityMonitor monitor;

  @override
  Widget build(BuildContext context) {
    final pages = monitor.pageCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppMetrics.cardPadding, AppMetrics.gapSmall, AppMetrics.cardPadding, 0),
      child: Row(
        children: [
          Text(
            monitor.calm ? 'TUTTO TRANQUILLO' : 'IN ATTIVITÀ',
            style: TextStyle(
              color: monitor.calm ? AppColors.faint : AppColors.warning,
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          if (pages > 1) ...[
            for (var index = 0; index < pages; index++)
              GestureDetector(
                onTap: () => monitor.goToPage(index),
                child: Container(
                  width: 18,
                  height: 18,
                  alignment: Alignment.center,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: index == monitor.page
                          ? AppColors.accent
                          : AppColors.border,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
            const SizedBox(width: AppMetrics.gapTiny),
            Icon(
              monitor.paused ? Icons.pause : Icons.slideshow,
              size: 13,
              color: monitor.paused ? AppColors.faint : AppColors.accent,
            ),
          ],
        ],
      ),
    );
  }
}

/// Il punteggio accanto al modulo: dice perché quella card è lì, che
/// altrimenti sarebbe una comparsa senza spiegazione.
class _Scored extends StatelessWidget {
  const _Scored({required this.score, required this.calm, required this.child});

  final double score;
  final bool calm;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = calm ? AppColors.faint : AppColors.forPercent(score);
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          bottom: AppMetrics.gap,
          left: 0,
          // Una barretta verticale sul fianco della card, alta quanto il
          // punteggio: si legge con la coda dell'occhio, non ruba spazio a
          // un numero e non va tradotta.
          child: FractionallySizedBox(
            alignment: Alignment.bottomLeft,
            heightFactor: (score / 100).clamp(0.04, 1.0),
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppMetrics.cardPadding * 2),
        child: Text(
          'In attesa dei primi punteggi dal PC…',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.faint, fontSize: 12),
        ),
      ),
    );
  }
}
