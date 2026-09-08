import '../models/module_spec.dart';
import 'body.dart';
import 'devices.dart';
import 'health.dart';
import 'home.dart';
import 'network.dart';
import 'system.dart';

/// Il catalogo. Gli id sono quelli dei pannelli del desktop, e le sezioni di
/// partenza sono la traduzione delle sue tre colonne in qualcosa che stia in
/// uno schermo alto e stretto.
///
/// Un modulo che il ponte non conosce resta qui ma non viene mai chiesto: e'
/// il ponte a dire, autenticandosi, quali sa servire.
final Map<String, ModuleSpec> moduleRegistry = {
  for (final spec in _all) spec.id: spec,
};

const sectionSystem = 'Sistema';
const sectionHealth = 'Salute';
const sectionNetwork = 'Rete';
const sectionHome = 'Casa';
const sectionBody = 'Persona';
const sectionDevices = 'Dispositivi';

/// L'ordine in cui le sezioni compaiono la prima volta.
const defaultSections = [
  sectionSystem,
  sectionHealth,
  sectionNetwork,
  sectionHome,
  sectionBody,
  sectionDevices,
];

final List<ModuleSpec> _all = [
  ModuleSpec(
    id: 'cpu',
    title: 'CPU',
    section: sectionSystem,
    metrics: ['cpu'],
    build: (context, snapshot) => cpuModule(snapshot),
    heightFor: chartWithSubtitleHeight,
  ),
  ModuleSpec(
    id: 'topcpu',
    title: 'Classifica CPU',
    section: sectionSystem,
    build: (context, snapshot) => topCpuModule(snapshot),
    heightFor: topCpuHeight,
  ),
  ModuleSpec(
    id: 'ram',
    title: 'RAM',
    section: sectionSystem,
    metrics: ['memory'],
    build: (context, snapshot) => ramModule(snapshot),
    heightFor: chartWithSubtitleHeight,
  ),
  ModuleSpec(
    id: 'topram',
    title: 'Classifica RAM',
    section: sectionSystem,
    build: (context, snapshot) => topRamModule(snapshot),
    heightFor: topRamHeight,
  ),
  ModuleSpec(
    id: 'gpu',
    title: 'GPU',
    section: sectionSystem,
    metrics: ['gpu'],
    build: (context, snapshot) => gpuModule(snapshot),
    heightFor: chartWithSubtitleHeight,
  ),
  ModuleSpec(
    id: 'topgpu',
    title: 'Classifica GPU',
    section: sectionSystem,
    build: (context, snapshot) => topGpuModule(snapshot),
    heightFor: topGpuHeight,
  ),
  ModuleSpec(
    id: 'vram',
    title: 'VRAM',
    section: sectionSystem,
    metrics: ['vram'],
    build: (context, snapshot) => vramModule(snapshot),
    heightFor: chartWithSubtitleHeight,
  ),
  ModuleSpec(
    id: 'power',
    title: 'Consumo',
    section: sectionSystem,
    metrics: ['power_cpu', 'power_gpu'],
    build: (context, snapshot) => powerModule(snapshot),
    heightFor: chartWithSubtitleHeight,
  ),
  ModuleSpec(
    id: 'freq',
    title: 'Frequenza',
    section: sectionSystem,
    metrics: ['freq'],
    build: (context, snapshot) => freqModule(snapshot),
  ),
  ModuleSpec(
    id: 'temps',
    title: 'Temperature',
    section: sectionHealth,
    build: (context, snapshot) => tempsModule(snapshot),
    heightFor: tempsHeight,
  ),
  ModuleSpec(
    id: 'disks',
    title: 'Dischi',
    section: sectionHealth,
    build: (context, snapshot) => disksModule(snapshot),
    heightFor: disksHeight,
  ),
  ModuleSpec(
    id: 'health',
    title: 'Stato sistema',
    section: sectionHealth,
    build: (context, snapshot) => healthModule(snapshot),
    heightFor: healthHeight,
  ),
  ModuleSpec(
    id: 'pressure',
    title: 'Pressione',
    section: sectionHealth,
    metrics: ['psi_cpu', 'psi_io', 'psi_mem'],
    build: (context, snapshot) => pressureModule(snapshot),
    heightFor: pressureHeight,
  ),
  ModuleSpec(
    id: 'net',
    title: 'Rete',
    section: sectionNetwork,
    metrics: ['net_rx', 'net_tx'],
    build: (context, snapshot) => netModule(snapshot),
    heightFor: netHeight,
  ),
  ModuleSpec(
    id: 'connections',
    title: 'Connessioni',
    section: sectionNetwork,
    build: (context, snapshot) => connectionsModule(snapshot),
    heightFor: connectionsHeight,
  ),
  ModuleSpec(
    id: 'homeassistant',
    title: 'Home Assistant',
    section: sectionHome,
    build: (context, snapshot) => homeAssistantModule(snapshot),
    heightFor: homeAssistantHeight,
  ),
  ModuleSpec(
    id: 'solar',
    title: 'Solare',
    section: sectionHome,
    // Le entita' del tester solare sono quelle che pubblica
    // scripts/solar_meter.py: il nome non cambia, e chiederle per nome
    // evita di dipendere da cosa l'utente ha scelto nelle opzioni.
    metrics: ['ha:sensor.solare_usb_potenza'],
    build: (context, snapshot) => solarModule(snapshot),
    heightFor: solarHeight,
  ),
  ModuleSpec(
    id: 'igrometro',
    title: 'Igrometro',
    section: sectionHome,
    metrics: ['ha:sensor.igrometro_umidita'],
    build: (context, snapshot) => igrometroModule(snapshot),
    heightFor: igrometroHeight,
  ),
  ModuleSpec(
    id: 'weather',
    title: 'Meteo',
    section: sectionHome,
    build: (context, snapshot) => weatherModule(snapshot),
    heightFor: weatherHeight,
  ),
  ModuleSpec(
    id: 'heart',
    title: 'Battito',
    section: sectionBody,
    metrics: ['heart'],
    build: (context, snapshot) => heartModule(snapshot),
    heightFor: heartHeight,
  ),
  ModuleSpec(
    id: 'inspire',
    title: 'Inspire 3',
    section: sectionBody,
    build: (context, snapshot) => inspireModule(snapshot),
    heightFor: inspireHeight,
  ),
  ModuleSpec(
    id: 'phones',
    title: 'Telefoni',
    section: sectionDevices,
    build: (context, snapshot) => phonesModule(snapshot),
    heightFor: phonesHeight,
  ),
];

/// Le entita' di Home Assistant che un modulo vuole vedere anche senza
/// grafico. Si ricavano dalle sue metriche: chi disegna `ha:sensor.x` ne
/// vuole per forza anche lo stato.
Set<String> entitiesFor(Iterable<String> modules) {
  final out = <String>{};
  for (final id in modules) {
    for (final metric in moduleRegistry[id]?.metrics ?? const <String>[]) {
      if (metric.startsWith('ha:')) out.add(metric.substring(3));
    }
  }
  // L'Inspire 3 non ha grafici ma ha due entita' precise, e senza chiederle
  // resterebbe vuoto: le prime quaranta entita' in ordine alfabetico non le
  // contengono.
  if (modules.contains('inspire')) {
    out.addAll(['sensor.inspire_3_battery', 'sensor.inspire_3_last_sync_time']);
  }
  return out;
}
