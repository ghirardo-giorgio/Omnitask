import 'package:flutter/widgets.dart';

import '../models/snapshot.dart';

/// Cosa serve a un modulo per disegnarsi, e come si disegna.
///
/// Sul desktop il catalogo non e' scritto da nessuna parte: `scripts/panels.py`
/// legge la cartella `panels/` e lo compone leggendo `panelId` dentro ogni
/// file. Qui non si puo' — in un'app compilata non esiste una cartella da
/// scandire — quindi il catalogo e' questa mappa, con gli stessi id di la',
/// cosi' una configurazione si legge da tutte e due le parti.
class ModuleSpec {
  const ModuleSpec({
    required this.id,
    required this.title,
    required this.section,
    required this.build,
    this.metrics = const [],
  });

  final String id;

  /// In italiano con gli accenti veri, come le stringhe del desktop.
  final String title;

  /// La sezione in cui finisce la prima volta, prima che l'utente lo sposti.
  final String section;

  /// Le serie storiche fisse che disegna. Quelle che dipendono da una scelta
  /// — quale sensore, quale disco, quale entita' — non stanno qui: le
  /// aggiunge il modulo a runtime, perche' la scelta e' dell'utente.
  final List<String> metrics;

  final Widget Function(BuildContext context, Snapshot snapshot) build;
}
