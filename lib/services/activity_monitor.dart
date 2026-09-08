import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/activity.dart';

/// Chi entra nella vista dinamica, chi resta, chi esce — e a che pagina si è.
///
/// Il PC manda i punteggi; qui si decide cosa farne. La divisione non è
/// casuale: i punteggi sono fatti della macchina, la decisione è di chi
/// guarda, e tenerla sul telefono vuol dire che cambiare una soglia ha
/// effetto subito invece di dover riconfigurare il PC.
///
/// Le tre regole che rendono la vista guardabile invece che epilettica sono
/// isteresi, permanenza minima e ordinamento, e sono tutte qui — che è anche
/// il motivo per cui questa classe non tocca né rete né widget: così si può
/// provare senza l'una né gli altri.
class ActivityMonitor extends ChangeNotifier {
  ActivityMonitor({
    ActivityRules rules = const ActivityRules(),
    DateTime Function()? clock,
  })  : _rules = rules,
        _now = clock ?? DateTime.now;

  ActivityRules _rules;
  final DateTime Function() _now;

  /// L'ultimo punteggio noto per modulo, anche di chi non è nella vista:
  /// serve alla schermata delle soglie, dove si regola guardando il numero
  /// vero invece che a memoria.
  Map<String, double> scores = const {};

  /// Fra quali moduli si può pescare: quelli che l'utente non ha spento.
  /// Spegnere un modulo lo toglie da tutto, vista dinamica compresa —
  /// altrimenti riapparirebbe proprio quello che si era deciso di non
  /// vedere.
  Set<String> candidates = const {};

  final Map<String, DateTime> _enteredAt = {};
  final Set<String> _inside = {};

  /// I posti, in ordine: chi siede dove. È questa lista a non essere
  /// ricostruita da zero a ogni campione — è tutta la stabilità della vista.
  final List<String> _seats = [];

  /// Quanti riquadri entrano in una pagata di schermo. Lo misura la vista,
  /// che è l'unica a sapere quanto è alto lo schermo e quanto occupa ogni
  /// modulo coi dati di adesso; qui si parte da tre, che è il minimo sotto
  /// cui non si scende.
  int _capacity = 3;
  int get capacity => _capacity;

  List<ActiveModule> _active = const [];
  List<ActiveModule> get active => _active;

  /// Vero quando nessuno supera la soglia e quelli mostrati sono solo i più
  /// alti di una macchina tranquilla.
  bool calm = true;

  ActivityRules get rules => _rules;

  set rules(ActivityRules value) {
    _rules = value;
    _rebuild();
    _restartRotation();
  }

  // --- pagine -----------------------------------------------------------

  int _page = 0;
  Timer? _rotation;
  Timer? _resume;
  bool paused = false;

  /// Quanti riquadri entrano davvero nello schermo, misurato dalla vista.
  ///
  /// Un numero fisso sbagliava in tutte e due le direzioni: tre card leggere
  /// lasciavano mezzo schermo vuoto, tre card alte già traboccavano. Il
  /// minimo di tre resta perché una pagina da due card con la rotazione che
  /// parte è peggio di un filo di scorrimento.
  void setCapacity(int seats) {
    final wanted = seats < 3 ? 3 : seats;
    if (wanted == _capacity) return;
    _capacity = wanted;
    // I posti oltre la nuova capienza tornano in gioco, e la pagina corrente
    // può essere finita fuori dalla fine.
    _rebuild();
    if (_page >= pageCount) _page = 0;
    _restartRotation();
    notifyListeners();
  }

  int get pageCount =>
      _active.isEmpty ? 1 : ((_active.length - 1) ~/ _capacity) + 1;

  int get page => _page.clamp(0, pageCount - 1);

  List<ActiveModule> get currentPage {
    if (_active.isEmpty) return const [];
    final start = page * _capacity;
    return _active.sublist(
      start,
      (start + _capacity).clamp(0, _active.length),
    );
  }

  /// I moduli da sottoscrivere: tutti quelli dentro, non solo la pagina che
  /// si vede. Sottoscrivere una pagina per volta farebbe arrivare ogni card
  /// vuota al primo giro di rotazione, e la rotazione è di otto secondi.
  Set<String> get subscription => _active.map((m) => m.id).toSet();

  void goToPage(int index) {
    _page = index.clamp(0, pageCount - 1);
    notifyListeners();
  }

  /// L'utente ha toccato: la rotazione si ferma e riprende da sola dopo un
  /// po' di quiete. Senza la pausa la vista è illeggibile — si sta leggendo
  /// una riga e la pagina scappa.
  void pause() {
    paused = true;
    _rotation?.cancel();
    _rotation = null;
    _resume?.cancel();
    _resume = Timer(Duration(seconds: _rules.pauseSeconds), () {
      paused = false;
      _restartRotation();
      notifyListeners();
    });
    notifyListeners();
  }

  void _restartRotation() {
    _rotation?.cancel();
    _rotation = null;
    if (paused || pageCount <= 1) return;
    _rotation = Timer.periodic(Duration(seconds: _rules.rotateSeconds), (_) {
      _page = (page + 1) % pageCount;
      notifyListeners();
    });
  }

  // --- punteggi ---------------------------------------------------------

  /// Arrivano punteggi nuovi dal PC.
  void update(Map<String, double> fresh) {
    scores = fresh;
    _rebuild();
    _restartRotation();
    notifyListeners();
  }

  void _rebuild() {
    final now = _now();
    final usable = <String, double>{
      for (final entry in scores.entries)
        if ((candidates.isEmpty || candidates.contains(entry.key)) &&
            !_rules.isExcluded(entry.key))
          entry.key: entry.value,
    };

    // Un modulo appena escluso esce subito, senza aspettare la permanenza
    // minima: quella serve a non far lampeggiare la vista per i capricci dei
    // punteggi, non a discutere una decisione dell'utente.
    for (final id in _inside.toList()) {
      if (_rules.isExcluded(id)) {
        _inside.remove(id);
        _enteredAt.remove(id);
      }
    }

    for (final entry in usable.entries) {
      final threshold = _rules.thresholdFor(entry.key);
      if (_inside.contains(entry.key)) {
        final held = now.difference(_enteredAt[entry.key] ?? now).inSeconds;
        // Si esce più in basso di dove si entra, e non prima di aver fatto
        // il proprio tempo.
        if (entry.value < threshold - _rules.hysteresis &&
            held >= _rules.minHoldSeconds) {
          _inside.remove(entry.key);
          _enteredAt.remove(entry.key);
        }
      } else if (entry.value >= threshold) {
        _inside.add(entry.key);
        _enteredAt[entry.key] = now;
      }
    }

    // Chi sparisce dai punteggi — una GPU staccata, Home Assistant che non
    // risponde più — esce come chi cala, con lo stesso tempo minimo.
    for (final id in _inside.toList()) {
      if (usable.containsKey(id)) continue;
      final held = now.difference(_enteredAt[id] ?? now).inSeconds;
      if (held >= _rules.minHoldSeconds) {
        _inside.remove(id);
        _enteredAt.remove(id);
      }
    }

    calm = _inside.isEmpty;

    // A riposo concorrono tutti; in allarme solo chi ha superato la soglia.
    final contenders = calm ? usable.keys.toList() : _inside.toList();
    _assignSeats(contenders, usable, queue: !calm);

    _active = [
      for (final id in _seats)
        ActiveModule(
          id: id,
          score: usable[id] ?? 0,
          enteredAt: _enteredAt[id] ?? now,
          calm: calm,
        ),
    ];

    if (_page >= pageCount) _page = 0;
  }

  /// Assegna i posti, cambiandone il meno possibile.
  ///
  /// È la regola che rende la vista leggibile: chi è già a schermo **resta
  /// dov'è**. Riordinare per punteggio a ogni campione voleva dire che la RAM
  /// passando da 52 a 53 scavalcava la rete e due card si scambiavano di
  /// posto — mentre le stai leggendo, e senza che fosse successo niente.
  ///
  /// Un posto si perde solo in due modi: uscendo dalla vista, o venendo
  /// rimpiazzati da qualcuno che merita davvero. «Davvero» è una fascia
  /// intera di scarto (dieci punti, la stessa unità delle preferenze):
  /// senza quel margine due moduli che oscillano intorno allo stesso valore
  /// si passerebbero il posto in continuazione, che è il difetto di partenza
  /// spostato di un livello.
  void _assignSeats(
    List<String> contenders,
    Map<String, double> usable, {
    required bool queue,
  }) {
    _seats.removeWhere((id) => !contenders.contains(id));

    // A riposo non c'è una coda: quello che non entra nella pagina non si
    // mostra affatto, invece di far ruotare pagine di moduli tranquilli.
    if (!queue && _seats.length > _capacity) {
      _seats.removeRange(_capacity, _seats.length);
    }

    double scoreOf(String id) => usable[id] ?? 0;

    final incoming = contenders.where((id) => !_seats.contains(id)).toList()
      ..sort((a, b) {
        // Fra chi aspetta di entrare l'ordine conta eccome: prima l'urgenza,
        // a pari urgenza le preferenze. È qui che `bandOf` e `rankOf`
        // servono davvero — per decidere chi si siede, non per rimescolare
        // chi è già seduto.
        final byBand = _rules.bandOf(scoreOf(b)).compareTo(_rules.bandOf(scoreOf(a)));
        if (byBand != 0) return byBand;
        final byRank = _rules.rankOf(a).compareTo(_rules.rankOf(b));
        if (byRank != 0) return byRank;
        return scoreOf(b).compareTo(scoreOf(a));
      });

    for (final id in incoming) {
      // Un posto libero nella pagina che si vede: ci si accomoda e basta.
      if (_seats.length < _capacity) {
        _seats.add(id);
        continue;
      }

      var weakest = 0;
      for (var seat = 1; seat < _capacity && seat < _seats.length; seat++) {
        if (scoreOf(_seats[seat]) < scoreOf(_seats[weakest])) weakest = seat;
      }

      if (_rules.bandOf(scoreOf(id)) > _rules.bandOf(scoreOf(_seats[weakest]))) {
        final displaced = _seats[weakest];
        _seats[weakest] = id;
        if (queue) _seats.add(displaced);
      } else if (queue) {
        _seats.add(id);
      }
    }
  }

  @override
  void dispose() {
    _rotation?.cancel();
    _resume?.cancel();
    super.dispose();
  }
}
