/// Un modulo dentro la vista dinamica, e da quanto.
class ActiveModule {
  const ActiveModule({
    required this.id,
    required this.score,
    required this.enteredAt,
    this.calm = false,
  });

  final String id;

  /// Quanto merita di essere guardato adesso, 0-100. Lo calcola il PC: e'
  /// l'unico che ha i dati di tutti i moduli, anche di quelli che il
  /// telefono in questo momento non sta scaricando.
  final double score;

  final DateTime enteredAt;

  /// Vero quando è entrato non perché superava la soglia, ma perché non la
  /// superava nessuno: è uno dei più alti di una macchina tranquilla.
  final bool calm;
}

/// Le regole della vista: quanto in alto deve stare un modulo per entrare, e
/// come si sfoglia quando sono tanti.
///
/// Stanno sul telefono e non sul PC di proposito. I punteggi sono fatti della
/// macchina, uguali per tutti; la soglia oltre la quale una cosa «merita
/// attenzione» è una preferenza di chi guarda, e due telefoni devono poter
/// vedere due viste diverse dagli stessi numeri.
class ActivityRules {
  const ActivityRules({
    this.thresholds = const {},
    this.priority = const [],
    this.excluded = const {},
    this.defaultThreshold = 80,
    this.hysteresis = 10,
    this.minHoldSeconds = 20,
    this.perPage = 3,
    this.rotateSeconds = 8,
    this.pauseSeconds = 30,
    this.calmCount = 3,
  });

  /// Soglia per modulo, dove l'utente l'ha cambiata.
  final Map<String, double> thresholds;

  /// L'ordine di preferenza, deciso trascinando le righe.
  ///
  /// Non scavalca l'urgenza — un disco in avaria sta in cima anche se è
  /// l'ultimo della lista — ma decide fra moduli grosso modo pari merito,
  /// che è il caso frequente: quando dieci cose sono tutte sopra soglia i
  /// loro punteggi si somigliano, e senza una preferenza l'ordine sarebbe
  /// deciso da decimali che cambiano a ogni campione.
  ///
  /// Chi non c'è dentro vale come se stesse in fondo.
  final List<String> priority;

  /// I moduli che non entrano nella vista dinamica, per quanto alto sia il
  /// loro punteggio.
  ///
  /// È un'esclusione dalla sola vista: il modulo resta acceso nella sua
  /// sezione e si guarda quando lo si vuole guardare. Serve per le cose che
  /// stanno in alto per natura senza che questo sia una notizia — una rete
  /// che scarica di continuo, un disco sempre pieno per scelta — dove
  /// spegnere il modulo sarebbe troppo e alzare la soglia a cento è un modo
  /// obliquo di dire la stessa cosa.
  final Set<String> excluded;

  final double defaultThreshold;

  bool isExcluded(String moduleId) => excluded.contains(moduleId);

  /// Di quanto deve ricadere un modulo per uscire. Senza, uno che oscilla
  /// intorno al valore di taglio entrerebbe e uscirebbe a ogni campione.
  final double hysteresis;

  /// Per quanto resta dentro chi è appena entrato, anche se crolla subito.
  /// Un picco di un secondo che fa comparire e sparire una card è peggio che
  /// non mostrarla affatto.
  final int minHoldSeconds;

  final int perPage;
  final int rotateSeconds;

  /// Quanto sta ferma la rotazione dopo che l'hai toccata.
  final int pauseSeconds;

  /// Quanti mostrarne quando non c'è niente sopra soglia. Una vista che si
  /// svuota sembra rotta, e a riposo è proprio quando la si apre per
  /// controllare che sia tutto a posto.
  final int calmCount;

  double thresholdFor(String moduleId) =>
      thresholds[moduleId] ?? defaultThreshold;

  /// Quanto in alto sta un modulo nelle preferenze: più basso è il numero,
  /// più conta. Chi non è nell'elenco finisce in coda.
  int rankOf(String moduleId) {
    final at = priority.indexOf(moduleId);
    return at < 0 ? priority.length + 1 : at;
  }

  /// La fascia di urgenza di un punteggio.
  ///
  /// Serve a decidere quando due moduli sono «pari merito» abbastanza da
  /// lasciar parlare le preferenze. Dieci punti: 95 e 91 sono la stessa
  /// cosa, 95 e 82 no. Qualunque taglio ha lo stesso difetto — 90 e 89
  /// finiscono in fasce diverse pur essendo identici — e dieci è largo
  /// abbastanza da rendere il caso raro, stretto abbastanza da non
  /// appiattire un allarme su un carico normale.
  int bandOf(double score) => (score ~/ 10);

  ActivityRules copyWith({
    Map<String, double>? thresholds,
    List<String>? priority,
    Set<String>? excluded,
    double? defaultThreshold,
    int? perPage,
    int? rotateSeconds,
    int? pauseSeconds,
  }) {
    return ActivityRules(
      thresholds: thresholds ?? this.thresholds,
      priority: priority ?? this.priority,
      excluded: excluded ?? this.excluded,
      defaultThreshold: defaultThreshold ?? this.defaultThreshold,
      hysteresis: hysteresis,
      minHoldSeconds: minHoldSeconds,
      perPage: perPage ?? this.perPage,
      rotateSeconds: rotateSeconds ?? this.rotateSeconds,
      pauseSeconds: pauseSeconds ?? this.pauseSeconds,
      calmCount: calmCount,
    );
  }

  Map<String, dynamic> toJson() => {
        'soglie': thresholds,
        'priorita': priority,
        'esclusi': excluded.toList(),
        'sogliaPredefinita': defaultThreshold,
        'perPagina': perPage,
        'rotazione': rotateSeconds,
        'pausa': pauseSeconds,
      };

  static ActivityRules fromJson(Map<String, dynamic> json) {
    final raw = json['soglie'];
    return ActivityRules(
      thresholds: raw is Map
          ? {
              for (final entry in raw.entries)
                entry.key.toString(): (entry.value as num).toDouble(),
            }
          : const {},
      priority: (json['priorita'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      excluded: (json['esclusi'] as List?)?.map((e) => e.toString()).toSet() ??
          const {},
      defaultThreshold: (json['sogliaPredefinita'] as num?)?.toDouble() ?? 80,
      perPage: (json['perPagina'] as num?)?.toInt() ?? 3,
      rotateSeconds: (json['rotazione'] as num?)?.toInt() ?? 8,
      pauseSeconds: (json['pausa'] as num?)?.toInt() ?? 30,
    );
  }
}
