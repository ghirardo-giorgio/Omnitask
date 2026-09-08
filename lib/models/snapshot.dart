/// Quello che il ponte manda, tenuto per sorgente.
///
/// Le sorgenti sono le stesse che il ponte interroga (`overview`, `health`,
/// `series`…): i moduli ci pescano dentro. Restano mappe non tipizzate
/// apposta — sono il JSON della dashboard, e ogni campo tipizzato qui
/// sarebbe un campo da rincorrere di la' a ogni cambiamento.
class Snapshot {
  Snapshot();

  final Map<String, Map<String, dynamic>> sources = {};

  /// Quando ogni sorgente e' arrivata: serve a dire "vecchio di un minuto"
  /// invece di mostrare un numero fermo come se fosse di adesso.
  final Map<String, DateTime> arrived = {};

  Map<String, dynamic>? operator [](String source) => sources[source];

  DateTime? ageOf(String source) => arrived[source];

  void absorb(Map<String, dynamic> fresh) {
    final now = DateTime.now();
    fresh.forEach((name, value) {
      if (value is Map<String, dynamic>) {
        sources[name] = value;
        arrived[name] = now;
      }
    });
  }

  void clear() {
    sources.clear();
    arrived.clear();
  }

  /// Una serie storica per nome, o null se non e' arrivata.
  Series? series(String metric) {
    final all = sources['series']?['series'];
    if (all is! Map) return null;
    final found = all[metric];
    return found is Map ? Series.fromJson(Map<String, dynamic>.from(found)) : null;
  }
}

/// Una serie da disegnare, come la manda Query.qml.
class Series {
  Series({
    required this.values,
    required this.unit,
    required this.max,
    required this.color,
    this.autoscale = false,
    this.minScale = 0,
    this.gaps = false,
    this.intervalMs,
  });

  /// I punti. Un `null` e' un buco vero — il braccialetto era sul comodino,
  /// il recorder non ha registrato — e va lasciato tale: uno zero al suo
  /// posto disegnerebbe un arresto cardiaco.
  final List<double?> values;
  final String unit;

  /// Il fondoscala contro cui il desktop disegna questa serie. Arriva da
  /// laggiu' perche' da qui non si potrebbe calcolare: la rete si scala
  /// contro il massimo fra download e upload insieme, una temperatura
  /// contro il proprio punto critico.
  final double max;
  final String color;

  /// Vero dove un fondoscala fisso non esiste (watt, battito, entita' di
  /// Home Assistant): lo si ricava dai valori presenti.
  final bool autoscale;
  final double minScale;
  final bool gaps;
  final int? intervalMs;

  static Series fromJson(Map<String, dynamic> json) {
    final raw = json['values'];
    return Series(
      values: raw is List
          ? raw.map((v) => v is num ? v.toDouble() : null).toList(growable: false)
          : const [],
      unit: json['unit']?.toString() ?? '',
      max: (json['max'] as num?)?.toDouble() ?? 0,
      color: json['color']?.toString() ?? '',
      autoscale: json['autoscale'] == true,
      minScale: (json['min_scale'] as num?)?.toDouble() ?? 0,
      gaps: json['gaps'] == true,
      intervalMs: (json['interval_ms'] as num?)?.toInt(),
    );
  }

  bool get isEmpty => values.every((v) => v == null);

  /// Il fondoscala da usare davvero.
  double scaleFor() {
    if (!autoscale) return max > 0 ? max : 1;
    var peak = minScale;
    for (final v in values) {
      if (v != null && v > peak) peak = v;
    }
    return peak > 0 ? peak * 1.15 : 1;
  }

  double? get latest {
    for (var i = values.length - 1; i >= 0; i--) {
      if (values[i] != null) return values[i];
    }
    return null;
  }
}
