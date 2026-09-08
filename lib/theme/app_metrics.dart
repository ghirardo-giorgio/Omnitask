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

  // --- quanto occupa una card ------------------------------------------
  //
  // Serve a decidere quanti riquadri entrano in una schermata. Sono stime,
  // non misure: il layout vero lo fa Flutter, e queste servono a scegliere
  // *prima* quanti moduli mettere in pagina. Vivono qui, accanto alle misure
  // da cui sono composte, perché altrove resterebbero indietro in silenzio
  // quando una di quelle cambia — e una stima sbagliata si vede, è una card
  // che sborda dal fondo. `test/module_height_test.dart` le confronta con
  // l'altezza vera di ogni modulo renderizzato e fallisce se divergono.

  /// La riga del titolo: la detta il valore grosso, non il titolo.
  static const double titleRow = cardValue;

  /// Una riga etichetta/barra/valore, con la sua imbottitura.
  static const double statBarRow = statLabel + gapTiny * 2 + gapSmall;

  /// Il sottotitolo, dove c'è.
  static const double subtitleRow = cardSubtitle + gapTiny + gapSmall;

  /// Una cella di temperatura: due righe di etichetta e il numero.
  static const double tempTile = tempLabel * 2 + gapTiny + tempValue + gapSmall;

  /// Una cella a ciambella — un disco, la batteria di un telefono — nel suo
  /// caso più alto: l'anello, il nome su due righe, e le due righe di
  /// dettaglio sotto. Il fattore 1.2 è l'interlinea dichiarata sull'etichetta
  /// in `DonutTile`.
  static const double donutTile =
      donut + gapSmall + statValue * 1.2 * 2 + 13 + gapTiny + 13;

  /// Margine, imbottitura, titolo e lo stacco prima del contenuto.
  static const double cardChrome = gap + cardPadding * 2 + titleRow + gapSmall;

  /// L'altezza di una card che contiene [content].
  static double card(double content, {bool subtitle = false}) =>
      cardChrome + content + (subtitle ? subtitleRow : 0);

  /// Una card fatta di un elenco di [rows] righe.
  static double cardWithRows(int rows, {bool subtitle = false}) =>
      card(rows * rowHeight, subtitle: subtitle);

  /// Una card fatta di un grafico.
  static double cardWithChart({bool subtitle = false}) =>
      card(sparklineHeight, subtitle: subtitle);

  /// Una card fatta di una griglia di [items] celle alte [tile], su
  /// [columns] colonne.
  static double cardWithGrid(int items, int columns, double tile,
      {bool subtitle = false}) {
    if (items <= 0) return card(0, subtitle: subtitle);
    final rows = (items + columns - 1) ~/ columns;
    return card(rows * tile + (rows - 1) * gap, subtitle: subtitle);
  }

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
