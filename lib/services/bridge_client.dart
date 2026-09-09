import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/connection_settings.dart';
import '../models/snapshot.dart';

/// L'impronta di un certificato come "AA:BB:CC…", nello stesso formato in
/// cui la stampa il ponte (vedi cert_fingerprint in phone_bridge.py), cosi'
/// le due stringhe si confrontano a vista.
String formatFingerprint(List<int> bytes) => bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

/// Le sorgenti che il ponte serve anche a dashboard spenta: kdeconnect
/// risponde da solo. Vederne arrivare una non dice niente sulla dashboard;
/// vedere arrivare qualsiasi altra cosa dice che e' viva.
const _sourcesWithoutDashboard = {'phones'};

/// Il certificato presentato dal PC non e' quello accettato la prima volta.
/// O il ponte e' stato reinstallato (certificato rigenerato), o qualcuno
/// sulla stessa rete si sta spacciando per il PC. Da qui le due cose non si
/// distinguono, quindi non si prosegue senza che l'utente scelga.
class CertificateMismatch implements Exception {
  const CertificateMismatch(this.presented);
  final String presented;
}

/// Il canale verso il ponte sul PC.
///
/// Protocollo: righe JSON separate da "\n". Dopo la connessione va mandato
/// per primo `{"cmd":"auth","token":"..."}`; solo dopo un `{"type":"auth",
/// "ok":true}` il ponte accetta `{"cmd":"subscribe",...}` e comincia a
/// spingere `snapshot` e `update`.
///
/// Il canale e' cifrato quando il ponte ha un certificato — se l'ha generato,
/// e lo genera da solo al primo avvio. L'app lo fissa al primo collegamento e
/// da li' in poi ne rifiuta uno diverso.
class BridgeClient extends ChangeNotifier {
  BridgeClient();

  Socket? _socket;
  StreamSubscription<String>? _sub;
  Timer? _reconnectTimer;
  ConnectionSettings? _settings;
  bool _disposed = false;
  bool _wantConnected = false;

  ConnectionStatus status = ConnectionStatus.disconnected;
  String? lastFailureReason;

  bool connectionSecure = false;
  String? peerFingerprint;

  /// Valorizzata quando il certificato non corrisponde a quello fissato:
  /// finche' l'utente non decide, l'app non riprova da sola — insistere
  /// verso un possibile impostore e' esattamente quello che non si deve
  /// fare.
  String? certificateMismatch;

  /// L'ultimo stato ricevuto, per sorgente.
  final Snapshot snapshot = Snapshot();

  /// Il nome del PC e i moduli che il ponte dichiara di saper servire:
  /// arrivano con l'autenticazione, e servono a non offrire nelle
  /// impostazioni un modulo che quel ponte non conosce.
  String? hostName;
  List<String> availableModules = const [];

  /// I moduli per cui il PC sa calcolare un punteggio. Gli altri non entrano
  /// mai nella vista dinamica, e la schermata delle soglie li toglie
  /// dall'elenco invece di mostrarne la riga con l'interruttore morto.
  ///
  /// Lo dichiara il ponte perché è lui ad avere le formule: dedurlo qui
  /// vorrebbe dire tenerne una seconda copia, e la prima a cambiare
  /// resterebbe da sola.
  List<String> scorableModules = const [];

  /// La dashboard e' spenta: i numeri che si vedono sono vecchi, e dirlo e'
  /// meglio che lasciarli fermi facendo finta.
  String? dashboardError;
  DateTime? dashboardDownSince;

  /// Cambia a ogni dato nuovo. I widget ci si agganciano invece di
  /// confrontare mappe.
  int version = 0;

  Set<String> _modules = {};
  Set<String> _metrics = {};
  Set<String> _entities = {};
  bool _activity = false;

  /// Chiamata quando il PC manda punteggi nuovi. Ci si aggancia
  /// l'ActivityMonitor: il client non sa cosa farne, e non deve.
  void Function(Map<String, double> scores)? onActivity;

  bool get connected => status == ConnectionStatus.connected;

  // --- connessione ------------------------------------------------------

  void connect(ConnectionSettings settings) {
    _settings = settings;
    _wantConnected = true;
    certificateMismatch = null;
    _reconnectTimer?.cancel();
    _openSocket();
  }

  void disconnect() {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _closeSocket();
    status = ConnectionStatus.disconnected;
    _notify();
  }

  /// Cosa sta guardando il telefono adesso. Si richiama a ogni cambio di
  /// sezione: quello che non si guarda non si scarica, e sul PC non viene
  /// nemmeno interrogato.
  ///
  /// Le `entities` sono separate dalle `metrics` perche' sono due richieste
  /// diverse: una serie storica di Home Assistant costa al PC uno scarico
  /// dal recorder, il solo stato corrente no. Un modulo che mostra una
  /// batteria senza grafico deve poter chiedere il secondo senza il primo.
  ///
  /// `activity` accende la sorveglianza: il PC comincia a mandare i punteggi
  /// di tutti i moduli anche mentre il telefono guarda un'altra pagina. È
  /// l'unica cosa che si chiede senza guardarla, e serve perché una vista
  /// dinamica che scoprisse la CPU alta solo guardandola non la farebbe mai
  /// entrare.
  void subscribe(
    Set<String> modules,
    Set<String> metrics, [
    Set<String> entities = const {},
    bool activity = false,
  ]) {
    if (setEquals(modules, _modules) &&
        setEquals(metrics, _metrics) &&
        setEquals(entities, _entities) &&
        activity == _activity) {
      return;
    }
    _modules = Set.of(modules);
    _metrics = Set.of(metrics);
    _entities = Set.of(entities);
    _activity = activity;
    _sendSubscribe();
  }

  void _sendSubscribe() {
    final socket = _socket;
    if (socket == null || status != ConnectionStatus.connected) return;
    _send(socket, {
      'cmd': 'subscribe',
      'modules': _modules.toList(),
      'metrics': _metrics.toList(),
      'entities': _entities.toList(),
      'activity': _activity,
    });
  }

  Future<void> _openSocket() async {
    final settings = _settings;
    if (settings == null || _disposed) return;

    status = ConnectionStatus.connecting;
    lastFailureReason = null;
    _notify();

    try {
      final connection = await openBridgeConnection(settings);
      final socket = connection.socket;
      _socket = socket;
      connectionSecure = connection.secure;
      peerFingerprint = connection.fingerprint;

      _send(socket, {'cmd': 'auth', 'token': settings.token});

      _sub = utf8.decoder
          .bind(socket)
          .transform(const LineSplitter())
          .listen(
            _handleLine,
            onError: (_) => _handleDisconnect(),
            onDone: _handleDisconnect,
            cancelOnError: true,
          );
    } on CertificateMismatch catch (mismatch) {
      certificateMismatch = mismatch.presented;
      status = ConnectionStatus.disconnected;
      _notify();
      return;
    } catch (error) {
      lastFailureReason = error.toString();
      _closeSocket();
      status = ConnectionStatus.disconnected;
      _notify();
      _scheduleReconnect();
    }
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    Map<String, dynamic> message;
    try {
      message = jsonDecode(line) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    switch (message['type']) {
      case 'auth':
        if (message['ok'] == true) {
          status = ConnectionStatus.connected;
          // Il guasto visto prima della caduta apparteneva alla sessione di
          // prima: il `recovered` che lo chiudeva puo' essere passato mentre
          // eravamo scollegati, e un ponte riavviato riparte comunque senza
          // memoria del guasto. Se e' ancora spenta lo ridice lui.
          dashboardError = null;
          dashboardDownSince = null;
          hostName = message['host']?.toString();
          final modules = message['modules'];
          if (modules is List) {
            availableModules = modules.map((m) => m.toString()).toList(growable: false);
          }
          final scorable = message['scorable'];
          if (scorable is List) {
            scorableModules = scorable.map((m) => m.toString()).toList(growable: false);
          }
          // La sottoscrizione riparte da sola dopo ogni caduta: il ponte non
          // si ricorda chi guardava cosa, e non deve — un client che torna
          // potrebbe tornare su un'altra sezione.
          _sendSubscribe();
        } else {
          final reason = message['reason']?.toString();
          lastFailureReason = message['error']?.toString();
          _closeSocket();
          status = ConnectionStatus.disconnected;
          // Un token sbagliato va corretto a mano: riprovare all'infinito
          // consumerebbe il freno del ponte e terrebbe l'utente su una
          // schermata che gira a vuoto. Gli altri rifiuti sono temporanei.
          if (reason != 'bad_token') _scheduleReconnect();
        }
        _notify();
        break;

      case 'snapshot':
        final sources = message['sources'];
        if (sources is Map<String, dynamic>) {
          snapshot.clear();
          snapshot.absorb(sources);
        }
        version++;
        _notify();
        break;

      case 'update':
        final sources = message['sources'];
        if (sources is Map<String, dynamic>) {
          _dashboardAnswered(sources);
          snapshot.absorb(sources);
        }
        version++;
        _notify();
        break;

      case 'error':
        dashboardError = message['error']?.toString();
        final since = message['since'];
        if (since is num) {
          dashboardDownSince =
              DateTime.fromMillisecondsSinceEpoch((since * 1000).round());
        }
        _notify();
        break;

      case 'activity':
        final scores = message['scores'];
        if (scores is Map) {
          onActivity?.call({
            for (final entry in scores.entries)
              if (entry.value is num)
                entry.key.toString(): (entry.value as num).toDouble(),
          });
        }
        break;

      case 'recovered':
        dashboardError = null;
        dashboardDownSince = null;
        _notify();
        break;
    }
  }

  /// Sono arrivate misure appena prese, quindi la dashboard risponde: il
  /// cartello va tolto senza aspettare il `recovered`. Quel messaggio e'
  /// l'annuncio del ritorno, non la prova: si perde se il telefono e' giu'
  /// proprio in quel momento, e un ponte riavviato non lo manda affatto.
  /// Cosi' il cartello non puo' sopravvivere ai dati che smentisce.
  ///
  /// Uno `snapshot` non basta — quello lo serve la cache del ponte, e a
  /// dashboard spenta e' vecchio di quanto dura il guasto.
  void _dashboardAnswered(Map<String, dynamic> sources) {
    if (dashboardError == null) return;
    final live =
        sources.keys.any((name) => !_sourcesWithoutDashboard.contains(name));
    if (!live) return;
    dashboardError = null;
    dashboardDownSince = null;
  }

  void _send(Socket socket, Map<String, dynamic> message) {
    try {
      socket.write('${jsonEncode(message)}\n');
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _closeSocket();
    if (_disposed) return;
    if (status != ConnectionStatus.disconnected) {
      status = ConnectionStatus.disconnected;
      _notify();
    }
    _scheduleReconnect();
  }

  void _closeSocket() {
    _sub?.cancel();
    _sub = null;
    try {
      _socket?.destroy();
    } catch (_) {}
    _socket = null;
  }

  void _scheduleReconnect() {
    if (!_wantConnected || _disposed || certificateMismatch != null) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _openSocket);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// L'utente ha guardato l'impronta nuova e ha detto di si'.
  void acceptNewCertificate() {
    certificateMismatch = null;
    final settings = _settings;
    if (settings != null) {
      _settings = settings.copyWith(fingerprint: null);
      _openSocket();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _closeSocket();
    super.dispose();
  }
}

/// Esito dell'apertura di una connessione verso il ponte.
class BridgeConnection {
  const BridgeConnection(this.socket, {required this.secure, this.fingerprint});
  final Socket socket;
  final bool secure;
  final String? fingerprint;
}

/// Apre la connessione, cifrata se il ponte lo permette.
///
/// Si tenta prima il TLS. Il certificato e' self-signed — nessuna autorita'
/// lo firma — quindi la validazione normale lo rifiuterebbe sempre: al suo
/// posto c'e' il pinning, cioe' l'impronta accettata la prima volta. Se il
/// TLS non riesce affatto si ricade in chiaro, che e' il caso di un PC senza
/// openssl.
Future<BridgeConnection> openBridgeConnection(ConnectionSettings settings) async {
  String? presented;
  try {
    final secure = await SecureSocket.connect(
      settings.host,
      settings.port,
      timeout: const Duration(seconds: 8),
      onBadCertificate: (certificate) {
        presented = formatFingerprint(certificate.sha1);
        final pinned = settings.fingerprint;
        // Primo collegamento: si accetta e si fissa. Da li' in poi solo
        // quella.
        return pinned == null || pinned.isEmpty || pinned == presented;
      },
    );
    return BridgeConnection(secure, secure: true, fingerprint: presented);
  } on HandshakeException {
    final pinned = settings.fingerprint;
    if (pinned != null && pinned.isNotEmpty && presented != null && presented != pinned) {
      throw CertificateMismatch(presented!);
    }
    // Nessun certificato dall'altra parte: si riprova in chiaro.
    final plain = await Socket.connect(
      settings.host,
      settings.port,
      timeout: const Duration(seconds: 8),
    );
    return BridgeConnection(plain, secure: false);
  }
}
