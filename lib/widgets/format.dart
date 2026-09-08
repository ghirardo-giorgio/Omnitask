// Le stesse formattazioni della dashboard (SystemStats.formatBytes e
// formatDuration), perche' "1,2 GB" e "1234567890 byte" sono lo stesso
// numero e solo uno dei due si legge su un telefono.

const _units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

String formatBytes(num? bytes, {bool perSecond = false}) {
  if (bytes == null) return '—';
  var value = bytes.toDouble();
  var unit = 0;
  while (value.abs() >= 1024 && unit < _units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value.abs() < 10 && unit > 0 ? 1 : 0;
  return '${value.toStringAsFixed(digits)} ${_units[unit]}${perSecond ? '/s' : ''}';
}

String formatPercent(num? value, {int digits = 1}) =>
    value == null ? '—' : '${value.toStringAsFixed(digits)}%';

String formatDuration(num? seconds) {
  if (seconds == null) return '—';
  final total = seconds.round();
  final days = total ~/ 86400;
  final hours = (total % 86400) ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  if (days > 0) return '${days}g ${hours}h';
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

String formatWatts(num? watts) =>
    watts == null ? '—' : '${watts.toStringAsFixed(1)} W';

String formatCelsius(num? degrees) =>
    degrees == null ? '—' : '${degrees.toStringAsFixed(0)}°';

/// Quanto e' vecchio un dato, detto in breve. Serve dove il numero potrebbe
/// essere fermo da un pezzo senza che si veda: il battito arriva ogni
/// minuto, e uno di venti minuti fa non e' il battito di adesso.
String formatAge(DateTime? when) {
  if (when == null) return '';
  final seconds = DateTime.now().difference(when).inSeconds;
  if (seconds < 5) return '';
  if (seconds < 60) return '${seconds}s fa';
  if (seconds < 3600) return '${seconds ~/ 60}m fa';
  return '${seconds ~/ 3600}h fa';
}
