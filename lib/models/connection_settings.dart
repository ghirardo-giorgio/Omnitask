/// Come si raggiunge il PC: quello che l'utente digita alla prima apertura.
class ConnectionSettings {
  const ConnectionSettings({
    required this.host,
    required this.port,
    required this.token,
    this.fingerprint,
  });

  final String host;
  final int port;
  final String token;

  /// L'impronta del certificato accettata al primo collegamento. Da li' in
  /// poi un certificato diverso non passa senza che l'utente lo dica: o il
  /// ponte e' stato reinstallato, o qualcuno sulla rete si sta spacciando
  /// per il PC, e le due cose non si distinguono da qui.
  final String? fingerprint;

  bool get valid => host.isNotEmpty && port > 0 && token.isNotEmpty;

  ConnectionSettings copyWith({String? host, int? port, String? token, String? fingerprint}) {
    return ConnectionSettings(
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      fingerprint: fingerprint ?? this.fingerprint,
    );
  }

  static const empty = ConnectionSettings(host: '', port: 8770, token: '');
}

enum ConnectionStatus { disconnected, connecting, connected }
