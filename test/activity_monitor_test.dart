import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask/models/activity.dart';
import 'package:omnitask/services/activity_monitor.dart';

/// Un orologio che si sposta a comando: la permanenza minima è di venti
/// secondi, e provarla aspettandoli davvero renderebbe la suite inutilizzabile.
class FakeClock {
  DateTime now = DateTime(2026, 1, 1, 12);
  DateTime call() => now;
  void advance(int seconds) => now = now.add(Duration(seconds: seconds));
}

void main() {
  late FakeClock clock;
  late ActivityMonitor monitor;

  setUp(() {
    clock = FakeClock();
    monitor = ActivityMonitor(clock: clock.call);
    monitor.candidates = {'cpu', 'ram', 'net', 'disks', 'temps', 'gpu', 'topcpu'};
  });

  tearDown(() => monitor.dispose());

  group('isteresi', () {
    test('entra a 80 e non esce a 75', () {
      monitor.update({'cpu': 82});
      expect(monitor.active.single.id, 'cpu');
      expect(monitor.calm, isFalse);

      clock.advance(60); // il tempo minimo è passato: se esce, esce per il valore
      monitor.update({'cpu': 75});
      expect(monitor.active.single.id, 'cpu',
          reason: 'sopra la soglia di uscita (70) deve restare');
    });

    test('esce sotto 70', () {
      monitor.update({'cpu': 82, 'disks': 91});
      clock.advance(60);
      monitor.update({'cpu': 69, 'disks': 91});
      // Il disco tiene la vista in allarme, quindi l'uscita della CPU si
      // vede: se fosse rimasta sola rientrerebbe come «tutto tranquillo»,
      // che è un'altra cosa e ha un suo test.
      expect(monitor.calm, isFalse);
      expect(monitor.active.map((m) => m.id).toList(), ['disks']);
    });

    test('uscito dall\'allarme, a riposo torna come tranquillo', () {
      monitor.update({'cpu': 82});
      clock.advance(60);
      monitor.update({'cpu': 12});
      // Non è più un allarme — ed è questo che conta — ma resta a schermo:
      // è il più alto di una macchina che non ha niente da segnalare, e una
      // vista vuota sembrerebbe rotta.
      expect(monitor.calm, isTrue);
      expect(monitor.active.single.calm, isTrue);
    });

    test('non entra a 79', () {
      monitor.update({'cpu': 79, 'ram': 10});
      expect(monitor.calm, isTrue, reason: 'nessuno ha superato la soglia');
    });
  });

  group('permanenza minima', () {
    test('un picco di un secondo resta dentro venti secondi', () {
      monitor.update({'cpu': 95});
      expect(monitor.active.single.id, 'cpu');

      clock.advance(1);
      monitor.update({'cpu': 3, 'disks': 88});
      expect(monitor.active.map((m) => m.id), contains('cpu'),
          reason: 'crollata subito, ma non ha fatto il suo tempo');

      clock.advance(19);
      monitor.update({'cpu': 3, 'disks': 88});
      expect(monitor.calm, isFalse);
      expect(monitor.active.map((m) => m.id).toList(), ['disks'],
          reason: 'fatto il suo tempo ed è crollata, esce');
    });

    test('vale anche per un modulo che sparisce dai punteggi', () {
      monitor.update({'gpu': 90});
      expect(monitor.active.single.id, 'gpu');

      clock.advance(2);
      monitor.update({'cpu': 5}); // la GPU non risponde più
      expect(monitor.active.map((m) => m.id), contains('gpu'));

      clock.advance(30);
      monitor.update({'cpu': 5});
      expect(monitor.active.map((m) => m.id), isNot(contains('gpu')));
    });
  });

  group('ordine e riposo', () {
    test('il più urgente è il primo', () {
      monitor.update({'cpu': 85, 'disks': 100, 'net': 92});
      expect(monitor.active.map((m) => m.id).toList(), ['disks', 'net', 'cpu']);
    });

    test('a riposo mostra i tre più alti e lo dichiara', () {
      monitor.update({'cpu': 4, 'ram': 55, 'net': 12, 'temps': 43, 'disks': 41});
      expect(monitor.calm, isTrue);
      expect(monitor.active.length, 3);
      expect(monitor.active.map((m) => m.id).toList(), ['ram', 'temps', 'disks']);
      expect(monitor.active.every((m) => m.calm), isTrue);
    });

    test('un modulo spento non entra, per quanto alto sia', () {
      monitor.candidates = {'cpu'};
      monitor.update({'cpu': 30, 'disks': 100});
      expect(monitor.active.map((m) => m.id), isNot(contains('disks')));
      expect(monitor.active.single.id, 'cpu');
    });
  });

  group('priorità', () {
    test('a pari merito decide l\'ordine scelto', () {
      monitor.rules = const ActivityRules(priority: ['net', 'cpu', 'ram']);
      // Tutti e tre nella stessa fascia: parlano le preferenze, non i
      // decimali.
      monitor.update({'cpu': 92, 'ram': 95, 'net': 91});
      expect(monitor.active.map((m) => m.id).toList(), ['net', 'cpu', 'ram']);
    });

    test('non scavalca l\'urgenza', () {
      monitor.rules = const ActivityRules(priority: ['net', 'cpu', 'disks']);
      // Il disco è ultimo nelle preferenze ma sta una fascia sopra: resta in
      // cima, che è tutto il senso di avere le fasce.
      monitor.update({'cpu': 85, 'net': 88, 'disks': 100});
      expect(monitor.active.first.id, 'disks');
      expect(monitor.active.map((m) => m.id).toList(), ['disks', 'net', 'cpu']);
    });

    test('chi non è nell\'elenco va in coda a pari merito', () {
      monitor.rules = const ActivityRules(priority: ['ram']);
      monitor.update({'cpu': 95, 'ram': 92, 'temps': 91});
      expect(monitor.active.first.id, 'ram');
    });

    test('senza preferenze si torna al punteggio puro', () {
      monitor.update({'cpu': 92, 'ram': 95, 'net': 91});
      expect(monitor.active.map((m) => m.id).toList(), ['ram', 'cpu', 'net']);
    });

    test('vale anche a riposo', () {
      monitor.rules = const ActivityRules(priority: ['net', 'ram']);
      monitor.update({'cpu': 4, 'ram': 12, 'net': 11, 'temps': 43});
      expect(monitor.calm, isTrue);
      // temps sta una fascia sopra tutti, poi le preferenze.
      expect(monitor.active.map((m) => m.id).toList(), ['temps', 'net', 'ram']);
    });
  });

  group('esclusione dalla vista', () {
    test('un modulo escluso non entra, per quanto alto sia', () {
      monitor.rules = const ActivityRules(excluded: {'net'});
      monitor.update({'net': 100, 'cpu': 85});
      expect(monitor.active.map((m) => m.id), isNot(contains('net')));
      expect(monitor.active.single.id, 'cpu');
    });

    test('escluderlo lo fa uscire subito, senza aspettare i venti secondi', () {
      monitor.update({'net': 100, 'cpu': 85});
      expect(monitor.active.map((m) => m.id), contains('net'));

      // Nessun avanzamento dell'orologio: la permanenza minima serve contro
      // i capricci dei punteggi, non contro una decisione dell'utente.
      monitor.rules = const ActivityRules(excluded: {'net'});
      expect(monitor.active.map((m) => m.id), isNot(contains('net')));
    });

    test('rimetterlo lo fa tornare al giro dopo', () {
      monitor.rules = const ActivityRules(excluded: {'net'});
      monitor.update({'net': 100});
      expect(monitor.calm, isTrue);

      monitor.rules = const ActivityRules();
      expect(monitor.active.single.id, 'net');
      expect(monitor.calm, isFalse);
    });

    test('resta escluso anche dal riempimento a riposo', () {
      monitor.rules = const ActivityRules(excluded: {'ram'});
      monitor.update({'cpu': 4, 'ram': 55, 'net': 12, 'temps': 43});
      expect(monitor.calm, isTrue);
      expect(monitor.active.map((m) => m.id), isNot(contains('ram')),
          reason: 'sarebbe stato il più alto, ma è escluso');
    });
  });

  group('pagine', () {
    test('si impagina e la sottoscrizione le copre tutte', () {
      monitor.update({
        'cpu': 99, 'topcpu': 98, 'ram': 95, 'net': 94, 'disks': 93, 'temps': 92,
      });
      expect(monitor.active.length, 6);
      expect(monitor.pageCount, 2);
      expect(monitor.currentPage.map((m) => m.id).toList(), ['cpu', 'topcpu', 'ram']);

      monitor.goToPage(1);
      expect(monitor.currentPage.map((m) => m.id).toList(), ['net', 'disks', 'temps']);

      // Si sottoscrive tutto, non la pagina: altrimenti ogni rotazione
      // mostrerebbe tre card vuote per due secondi.
      expect(monitor.subscription.length, 6);
    });

    test('una pagina sola non ruota', () {
      monitor.update({'cpu': 99});
      expect(monitor.pageCount, 1);
    });

    test('il tocco mette in pausa', () {
      monitor.update({'cpu': 99, 'topcpu': 98, 'ram': 95, 'net': 94});
      expect(monitor.pageCount, 2);
      monitor.pause();
      expect(monitor.paused, isTrue);
    });
  });
}
