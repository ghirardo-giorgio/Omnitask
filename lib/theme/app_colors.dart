import 'package:flutter/material.dart';

/// La tavolozza della dashboard, con i nomi che ha di la'.
///
/// Sul desktop i colori stanno scritti per esteso in ogni file — `#0d1117`
/// compare trenta volte, `#30363d` centoquattro — tranne in un posto solo,
/// `PetColor.qml`, dove hanno un nome semantico. Qui si segue quel posto: un
/// colore chiamato `surface` si puo' cambiare una volta per tutte, uno
/// chiamato `#161b22` va rincorso.
class AppColors {
  const AppColors._();

  /// Sfondo della finestra.
  static const background = Color(0xFF0D1117);

  /// Le card dei moduli.
  static const surface = Color(0xFF161B22);

  /// Superficie sollevata: premuto, selezionato, divisori.
  static const surfaceHover = Color(0xFF21262D);

  static const border = Color(0xFF30363D);
  static const borderMuted = Color(0xFF21262D);

  /// Testo principale.
  static const foreground = Color(0xFFC9D1D9);

  /// Etichette e valori secondari.
  static const muted = Color(0xFF8B949E);

  /// Spento: un modulo disattivato, un valore che non c'e'.
  static const disabled = Color(0xFF6E7681);

  /// Terziario, quasi sfondo.
  static const faint = Color(0xFF484F58);

  /// Il sottotitolo di una card: il modello del processore, quello del disco.
  /// Prima erano scritti in `faint`, che su `surface` da' due a uno di
  /// contrasto e a mezzo metro sparisce; questo ne da' nove, e resta distinto
  /// da `accent`, che qui dentro vuol dire "selezionato".
  static const info = Color(0xFF79C0FF);

  /// Accento: selezione, bordo acceso, la CPU nei grafici blu.
  static const accent = Color(0xFF58A6FF);

  /// Accento pieno, quello che riempie un interruttore acceso.
  static const accentSolid = Color(0xFF1F6FEB);

  static const ok = Color(0xFF3FB950);
  static const warning = Color(0xFFD29922);
  static const urgent = Color(0xFFF85149);
  static const busy = Color(0xFFDB6D28);
  static const violet = Color(0xFFA371F7);

  /// Fondo tinto di una riga selezionata.
  static const selected = Color(0xFF132033);

  /// Le soglie che il desktop applica a una percentuale qualunque: sopra il
  /// 90 e' un problema, sopra il 75 e' da tenere d'occhio. Stanno qui perche'
  /// sono ripetute in DiskGauge, StatBar, CoreBars e nei pannelli.
  static Color forPercent(double percent) {
    if (percent >= 90) return urgent;
    if (percent >= 75) return warning;
    return ok;
  }

  /// Un colore scritto come "#rrggbb", quello che manda il ponte. Il
  /// fallback vale per una stringa vuota o storta: un grafico senza colore
  /// non si disegna, e non e' un motivo per non disegnarlo.
  static Color parse(String? value, Color fallback) {
    if (value == null || value.length != 7 || !value.startsWith('#')) {
      return fallback;
    }
    final parsed = int.tryParse(value.substring(1), radix: 16);
    return parsed == null ? fallback : Color(0xFF000000 | parsed);
  }

  static ThemeData theme() {
    const font = 'Roboto';
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      fontFamily: font,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentSolid,
        surface: surface,
        error: urgent,
        onPrimary: Colors.white,
        onSurface: foreground,
      ),
      dividerColor: border,
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: foreground, fontSize: 13),
        bodySmall: TextStyle(color: muted, fontSize: 11),
        titleMedium: TextStyle(color: foreground, fontSize: 14, fontWeight: FontWeight.w600),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: background,
        foregroundColor: foreground,
        elevation: 0,
        centerTitle: true,
      ),
    );
  }
}
