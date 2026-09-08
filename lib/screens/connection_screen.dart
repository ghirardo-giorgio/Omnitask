import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/connection_settings.dart';
import '../services/bridge_client.dart';
import '../services/settings_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_metrics.dart';

/// Indirizzo, porta e token: le tre cose che servono per trovare il PC.
///
/// Il token si legge sul PC in ~/.config/quickshell/phone-bridge.json, o nel
/// log del ponte al primo avvio. Cinque cifre perche' si digitano su un
/// telefono senza sbagliare.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, required this.settings, required this.client});

  final SettingsService settings;
  final BridgeClient client;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  late final _host = TextEditingController(text: widget.settings.connection.host);
  late final _port = TextEditingController(text: widget.settings.connection.port.toString());
  late final _token = TextEditingController(text: widget.settings.connection.token);

  String? _outcome;
  bool _testing = false;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    super.dispose();
  }

  ConnectionSettings _read() => ConnectionSettings(
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 8770,
        token: _token.text.trim(),
        fingerprint: widget.settings.connection.fingerprint,
      );

  /// Prova indirizzo, porta e token senza salvare niente: un token sbagliato
  /// salvato costringerebbe a tornare qui dopo aver visto una schermata che
  /// gira a vuoto.
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _outcome = null;
    });
    final settings = _read();
    try {
      final connection = await openBridgeConnection(settings);
      connection.socket.write('{"cmd":"auth","token":"${settings.token}"}\n');
      final line = await connection.socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .first
          .timeout(const Duration(seconds: 6));
      connection.socket.destroy();
      final ok = line.contains('"ok": true') || line.contains('"ok":true');
      setState(() {
        _outcome = ok
            ? 'Risponde${connection.secure ? ', e la connessione è cifrata' : ' (in chiaro: sul PC manca openssl)'}'
            : 'Ha risposto, ma il token non va bene';
      });
    } catch (error) {
      setState(() => _outcome = 'Non risponde: $error');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  /// Salva e collega. Alla prima configurazione questa schermata e' la
  /// radice: non c'e' niente da chiudere, ed e' il cambio di impostazioni a
  /// far comparire la dashboard al suo posto. Aperta dalla dashboard,
  /// invece, si chiude e si torna sopra.
  Future<void> _save() async {
    final navigator = Navigator.of(context);
    final connection = _read();
    widget.client.connect(connection);
    await widget.settings.setConnection(connection);
    if (navigator.canPop()) navigator.pop();
  }

  /// Dimentica il PC: indirizzo, token e certificato fissato. Si torna alla
  /// schermata di prima configurazione, vuota.
  Future<void> _forget() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Dimenticare questo PC?'),
        content: const Text(
          'Indirizzo, token e certificato fissato vengono cancellati e la '
          'connessione si chiude. Le sezioni e i moduli restano come sono.',
          style: TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Dimentica', style: TextStyle(color: AppColors.urgent)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final navigator = Navigator.of(context);
    await widget.settings.clearConnection();
    _host.clear();
    _port.text = '8770';
    _token.clear();
    // Se si arrivava dalla dashboard, quella sotto non ha piu' niente da
    // mostrare: si torna alla radice, che adesso e' questa schermata.
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connessione')),
      body: ListView(
        padding: const EdgeInsets.all(AppMetrics.cardPadding),
        children: [
          const Text(
            'Il ponte deve essere in esecuzione sul PC, sulla stessa rete WiFi.',
            style: TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          const SizedBox(height: AppMetrics.gap),
          _field('Indirizzo del PC', _host, hint: 'es. 192.168.1.50'),
          _field('Porta', _port, keyboard: TextInputType.number),
          _field('Token', _token,
              keyboard: TextInputType.number,
              hint: 'le 5 cifre stampate dal ponte al primo avvio'),
          const SizedBox(height: AppMetrics.gap),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _testing ? null : _test,
                  child: Text(_testing ? 'Provo…' : 'Verifica connessione'),
                ),
              ),
              const SizedBox(width: AppMetrics.gap),
              Expanded(
                child: FilledButton(onPressed: _save, child: const Text('Collega')),
              ),
            ],
          ),
          if (_outcome != null) ...[
            const SizedBox(height: AppMetrics.gap),
            Text(
              _outcome!,
              style: TextStyle(
                color: _outcome!.startsWith('Risponde') ? AppColors.ok : AppColors.warning,
                fontSize: 12,
              ),
            ),
          ],
          if (widget.settings.connection.fingerprint != null) ...[
            const SizedBox(height: AppMetrics.gap * 2),
            const Text('CERTIFICATO FISSATO',
                style: TextStyle(color: AppColors.faint, fontSize: 9, letterSpacing: 1)),
            const SizedBox(height: AppMetrics.gapTiny),
            Text(
              widget.settings.connection.fingerprint!,
              style: const TextStyle(
                  color: AppColors.muted, fontSize: 10, fontFamily: 'monospace'),
            ),
          ],
          if (widget.settings.configured) ...[
            const SizedBox(height: AppMetrics.gap * 2),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: AppMetrics.gap),
            TextButton.icon(
              onPressed: _forget,
              icon: const Icon(Icons.link_off, size: 18, color: AppColors.urgent),
              label: const Text('Dimentica questo PC',
                  style: TextStyle(color: AppColors.urgent)),
            ),
            const SizedBox(height: AppMetrics.gapTiny),
            const Text(
              'Da usare se cambi PC, se il ponte è stato reinstallato o se il '
              'token non è più quello.',
              style: TextStyle(color: AppColors.faint, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController controller,
      {TextInputType? keyboard, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppMetrics.gap),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        inputFormatters:
            keyboard == TextInputType.number ? [FilteringTextInputFormatter.digitsOnly] : null,
        style: const TextStyle(color: AppColors.foreground),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: AppColors.muted),
          hintStyle: const TextStyle(color: AppColors.faint, fontSize: 12),
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppMetrics.cardRadius),
            borderSide: const BorderSide(color: AppColors.border),
          ),
        ),
      ),
    );
  }
}
