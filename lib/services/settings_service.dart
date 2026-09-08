import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/activity.dart';
import '../models/connection_settings.dart';
import '../modules/registry.dart';

/// Una sezione: un nome e i moduli accesi dentro, in ordine.
class Section {
  Section(this.name, this.modules);

  String name;
  List<String> modules;

  Map<String, dynamic> toJson() => {'nome': name, 'moduli': modules};

  static Section fromJson(Map<String, dynamic> json) => Section(
        json['nome']?.toString() ?? 'Sezione',
        (json['moduli'] as List?)?.map((m) => m.toString()).toList() ?? [],
      );
}

/// Le impostazioni, scritte su disco a ogni modifica.
///
/// Non c'e' un pulsante «Applica», come non c'e' nelle opzioni del desktop:
/// una preferenza che si vede cambiare ma non e' ancora salvata e' una
/// preferenza che si perde.
///
/// Lo schema e' quello del desktop tradotto: li' un modulo e' acceso se
/// compare in una delle tre colonne — non c'e' nessun booleano da nessuna
/// parte — e qui e' acceso se compare in una delle sezioni. Spegnere vuol
/// dire togliere dalla lista, e l'ordine della lista e' l'ordine sullo
/// schermo.
class SettingsService extends ChangeNotifier {
  SettingsService(this._prefs) {
    _load();
  }

  static const _keyConnection = 'connessione';
  static const _keySections = 'sezioni';
  static const _keyLanguage = 'lingua';
  static const _keyActivity = 'attivita';

  /// Il nome della vista dinamica. Non è una sezione come le altre — i suoi
  /// moduli li sceglie il punteggio, non l'utente — ma occupa una pagina
  /// come loro, e sta in testa: è la prima cosa che si vede aprendo l'app.
  static const activitySection = 'Attività';

  final SharedPreferences _prefs;

  ConnectionSettings connection = ConnectionSettings.empty;
  List<Section> sections = [];
  String language = 'it';

  bool activityOn = true;
  ActivityRules activityRules = const ActivityRules();

  bool get configured => connection.valid;

  /// Tutti i moduli accesi, in tutte le sezioni.
  Set<String> get activeModules =>
      sections.expand((section) => section.modules).toSet();

  void _load() {
    final raw = _prefs.getString(_keyConnection);
    if (raw != null) {
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        connection = ConnectionSettings(
          host: json['indirizzo']?.toString() ?? '',
          port: (json['porta'] as num?)?.toInt() ?? 8770,
          token: json['token']?.toString() ?? '',
          fingerprint: json['impronta']?.toString(),
        );
      } catch (_) {
        connection = ConnectionSettings.empty;
      }
    }

    final rawSections = _prefs.getString(_keySections);
    if (rawSections != null) {
      try {
        final list = jsonDecode(rawSections) as List;
        sections = list
            .whereType<Map>()
            .map((s) => Section.fromJson(Map<String, dynamic>.from(s)))
            .toList();
      } catch (_) {
        sections = [];
      }
    }
    if (sections.isEmpty) sections = _defaults();

    language = _prefs.getString(_keyLanguage) ?? 'it';

    final rawActivity = _prefs.getString(_keyActivity);
    if (rawActivity != null) {
      try {
        final json = jsonDecode(rawActivity) as Map<String, dynamic>;
        activityOn = json['accesa'] != false;
        activityRules = ActivityRules.fromJson(json);
      } catch (_) {
        activityOn = true;
        activityRules = const ActivityRules();
      }
    }
  }

  Future<void> _saveActivity() async {
    await _prefs.setString(
      _keyActivity,
      jsonEncode({'accesa': activityOn, ...activityRules.toJson()}),
    );
    notifyListeners();
  }

  Future<void> setActivityOn(bool value) async {
    activityOn = value;
    await _saveActivity();
  }

  Future<void> setActivityRules(ActivityRules value) async {
    activityRules = value;
    await _saveActivity();
  }

  /// L'ordine di preferenza, dopo un trascinamento. Si salva sempre per
  /// intero, anche i moduli mai spostati: una lista parziale renderebbe la
  /// posizione di chi manca dipendente dall'ordine del catalogo, che è un
  /// dettaglio di come è scritta l'app e non una scelta di nessuno.
  Future<void> setPriority(List<String> order) async {
    activityRules = activityRules.copyWith(priority: order);
    await _saveActivity();
  }

  /// Toglie un modulo dalla vista dinamica, o ce lo rimette. Resta acceso
  /// nella sua sezione in entrambi i casi: è un'esclusione dalla vista, non
  /// uno spegnimento.
  Future<void> setExcludedFromActivity(String moduleId, bool excluded) async {
    final all = Set<String>.from(activityRules.excluded);
    if (excluded) {
      all.add(moduleId);
    } else {
      all.remove(moduleId);
    }
    activityRules = activityRules.copyWith(excluded: all);
    await _saveActivity();
  }

  /// La soglia di un modulo. Rimetterla al valore predefinito vuol dire
  /// toglierla, non riscriverci sopra il numero di partenza: una voce uguale
  /// al default resterebbe nel file a sporcare, indistinguibile da una
  /// scelta deliberata — la stessa regola dei colori sul desktop.
  Future<void> setThreshold(String moduleId, double? value) async {
    final thresholds = Map<String, double>.from(activityRules.thresholds);
    if (value == null) {
      thresholds.remove(moduleId);
    } else {
      thresholds[moduleId] = value;
    }
    activityRules = activityRules.copyWith(thresholds: thresholds);
    await _saveActivity();
  }

  /// La prima configurazione: ogni modulo nella sua sezione, tutti accesi.
  /// Si accendono tutti apposta — chi apre l'app la prima volta deve vedere
  /// cosa c'e', e spegnere quello che non gli serve e' piu' facile che
  /// indovinare cosa manca da una schermata vuota.
  List<Section> _defaults() {
    return [
      for (final name in defaultSections)
        Section(
          name,
          moduleRegistry.values
              .where((spec) => spec.section == name)
              .map((spec) => spec.id)
              .toList(),
        ),
    ];
  }

  Future<void> setConnection(ConnectionSettings value) async {
    connection = value;
    await _prefs.setString(
      _keyConnection,
      jsonEncode({
        'indirizzo': value.host,
        'porta': value.port,
        'token': value.token,
        if (value.fingerprint != null) 'impronta': value.fingerprint,
      }),
    );
    notifyListeners();
  }

  /// Dimentica indirizzo, token e certificato fissato: si torna alla
  /// schermata di prima configurazione. Le sezioni restano — chi cambia PC o
  /// rigenera il token non vuole per questo rifare la scelta dei moduli.
  Future<void> clearConnection() async {
    connection = ConnectionSettings.empty;
    await _prefs.remove(_keyConnection);
    notifyListeners();
  }

  Future<void> _saveSections() async {
    await _prefs.setString(
      _keySections,
      jsonEncode(sections.map((s) => s.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> setLanguage(String value) async {
    language = value;
    await _prefs.setString(_keyLanguage, value);
    notifyListeners();
  }

  // --- moduli -----------------------------------------------------------

  bool isOn(String moduleId) => activeModules.contains(moduleId);

  String? sectionOf(String moduleId) {
    for (final section in sections) {
      if (section.modules.contains(moduleId)) return section.name;
    }
    return null;
  }

  /// Accende o spegne un modulo. Acceso, torna nella sezione che gli
  /// compete secondo il catalogo — non nella prima disponibile: un modulo
  /// della salute che ricompare in mezzo alla rete confonde piu' di quanto
  /// aiuti.
  Future<void> toggle(String moduleId) async {
    if (isOn(moduleId)) {
      for (final section in sections) {
        section.modules.remove(moduleId);
      }
    } else {
      final home = moduleRegistry[moduleId]?.section;
      final target = sections.firstWhere(
        (section) => section.name == home,
        orElse: () => sections.first,
      );
      target.modules.add(moduleId);
    }
    await _saveSections();
  }

  Future<void> moveModule(String moduleId, String sectionName, int index) async {
    for (final section in sections) {
      section.modules.remove(moduleId);
    }
    final target = sections.firstWhere(
      (section) => section.name == sectionName,
      orElse: () => sections.first,
    );
    target.modules.insert(index.clamp(0, target.modules.length), moduleId);
    await _saveSections();
  }

  // --- sezioni ----------------------------------------------------------

  Future<void> addSection(String name) async {
    if (name.trim().isEmpty) return;
    sections.add(Section(name.trim(), []));
    await _saveSections();
  }

  Future<void> renameSection(int index, String name) async {
    if (name.trim().isEmpty) return;
    sections[index].name = name.trim();
    await _saveSections();
  }

  /// Toglie una sezione. I moduli che conteneva si spengono con lei: erano
  /// accesi perche' stavano li', e spostarli altrove d'ufficio vorrebbe dire
  /// riempire una sezione che l'utente non ha chiesto.
  Future<void> removeSection(int index) async {
    if (sections.length <= 1) return;
    sections.removeAt(index);
    await _saveSections();
  }

  Future<void> reorderSections(int from, int to) async {
    final section = sections.removeAt(from);
    sections.insert(to > from ? to - 1 : to, section);
    await _saveSections();
  }
}
