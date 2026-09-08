/// Le misure, tenute insieme come in PetStyle.qml.
class AppMetrics {
  const AppMetrics._();

  static const double cardRadius = 8;
  static const double cardPadding = 12;
  static const double gap = 10;
  static const double gapSmall = 6;
  static const double gapTiny = 3;

  /// Altezza di uno sparkline dentro una card. Sul desktop e' 40; su un
  /// telefono lo schermo e' stretto ma alto, e una linea di 40 pixel dentro
  /// una card larga tutto il display sarebbe un filo.
  static const double sparklineHeight = 56;

  /// Righe di elenco: classifiche, sensori, dischi.
  static const double rowHeight = 38;

  /// I corpi del testo. La dashboard di la' si guarda da trenta centimetri,
  /// questa a distanza di braccio: le stesse misure qui diventano illeggibili,
  /// e stanno raccolte in un posto solo perche' una scala si cambia tutta
  /// insieme o non si cambia.
  static const double cardTitle = 15;
  static const double cardValue = 28;
  static const double cardSubtitle = 13;
  static const double rowText = 15;
  static const double statLabel = 14;
  static const double statValue = 13;
  static const double statBarHeight = 8;

  /// Le ciambelle: dischi e batterie dei telefoni.
  static const double donut = 76;
  static const double donutStroke = 9;

  /// Le celle delle temperature, tre per riga.
  static const double tempValue = 22;
  static const double tempLabel = 11;
}
