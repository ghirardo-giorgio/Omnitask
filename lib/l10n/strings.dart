/// Le traduzioni, con lo schema del desktop: la chiave *e'* la stringa
/// italiana, non un identificatore.
///
/// Costa un dizionario in piu' (l'italiano non ne ha bisogno) e in cambio
/// toglie il caso peggiore: una traduzione che manca ricade sull'italiano
/// leggibile invece che su `panel.cpu.title.short`.
class Strings {
  Strings._(this.lang, this._table);

  final String lang;
  final Map<String, String> _table;

  static Strings current = Strings._('it', const {});

  static const available = ['it', 'en'];

  static void use(String lang) {
    current = Strings._(lang, _tables[lang] ?? const {});
  }

  String call(String key) => _table[key] ?? key;

  static const Map<String, Map<String, String>> _tables = {
    'it': {},
    'en': {
      'Sistema': 'System',
      'Salute': 'Health',
      'Rete': 'Network',
      'Casa': 'Home',
      'Persona': 'Body',
      'Dispositivi': 'Devices',
      'Sezioni': 'Sections',
      'Impostazioni': 'Settings',
      'Connessione': 'Connection',
      'Indirizzo del PC': 'Computer address',
      'Porta': 'Port',
      'Token': 'Token',
      'Collega': 'Connect',
      'Verifica connessione': 'Test connection',
      'Collegato': 'Connected',
      'Collegamento…': 'Connecting…',
      'Non collegato': 'Disconnected',
      'La dashboard non risponde': 'The dashboard is not answering',
      'in attesa del primo dato…': 'waiting for the first sample…',
      'Moduli accesi': 'Modules on',
      'Spenti': 'Off',
      'Nuova sezione': 'New section',
      'Rinomina': 'Rename',
      'Elimina': 'Delete',
      'Certificato cambiato': 'Certificate changed',
      'Accetta il nuovo certificato': 'Accept the new certificate',
      'Nessun modulo acceso in questa sezione': 'No module is on in this section',
      'CPU': 'CPU',
      'RAM': 'RAM',
      'GPU': 'GPU',
      'VRAM': 'VRAM',
      'Consumo': 'Power',
      'Classifica CPU': 'Top CPU',
      'Classifica RAM': 'Top RAM',
      'Classifica GPU': 'Top GPU',
      'Classifica VRAM': 'Top VRAM',
      'Temperature': 'Temperatures',
      'Dischi': 'Disks',
      'Stato sistema': 'System health',
      'Pressione': 'Pressure',
      'Frequenza': 'Frequency',
      'Connessioni': 'Connections',
      'Home Assistant': 'Home Assistant',
      'Solare': 'Solar',
      'Meteo': 'Weather',
      'Igrometro': 'Hygrometer',
      'Battito': 'Heart rate',
      'Inspire 3': 'Inspire 3',
      'Telefoni': 'Phones',
    },
  };
}

/// Scorciatoia: `tr('Dischi')`.
String tr(String key) => Strings.current(key);
