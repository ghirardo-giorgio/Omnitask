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

  group('posti stabili', () {
    test('un riquadro non si sposta perché un punteggio ha cambiato ordine', () {
      monitor.update({'net': 91, 'ram': 90, 'cpu': 89});
      expect(monitor.active.map((m) => m.id).toList(), ['net', 'ram', 'cpu']);

      // La RAM supera la rete. Prima questo scambiava due card sotto gli
      // occhi di chi le stava leggendo, ogni due secondi, senza che fosse
      // successo niente.
      monitor.update({'net': 91, 'ram': 96, 'cpu': 89});
      expect(monitor.active.map((m) => m.id).toList(), ['net', 'ram', 'cpu'],
          reason: 'chi è seduto resta dov\'è');
    });

    test('chi esce libera il posto e i successivi scalano', () {
      monitor.update({'net': 91, 'ram': 90, 'cpu': 89});
      clock.advance(60);
      monitor.update({'net': 91, 'ram': 50, 'cpu': 89});
      expect(monitor.active.map((m) => m.id).toList(), ['net', 'cpu']);
    });

    test('un nuovo prende il posto solo se supera di una fascia intera', () {
      monitor.update({'net': 85, 'ram': 84, 'cpu': 83});
      expect(monitor.active.length, 3, reason: 'la pagina è piena');

      // Un disco in avaria sta due fasce sopra il più debole: si siede al
      // suo posto, e il più debole scala in coda.
      monitor.update({'net': 85, 'ram': 84, 'cpu': 83, 'disks': 100});
      expect(monitor.active.map((m) => m.id).toList(),
          ['net', 'ram', 'disks', 'cpu']);
    });

    test('chi non supera si accoda invece di scalzare', () {
      monitor.update({'net': 85, 'ram': 84, 'cpu': 83});
      // Stessa fascia del più debole: non basta per togliergli il posto,
      // altrimenti due moduli che oscillano se lo passerebbero all'infinito.
      monitor.update({'net': 85, 'ram': 84, 'cpu': 83, 'temps': 88});
      expect(monitor.active.map((m) => m.id).toList(),
          ['net', 'ram', 'cpu', 'temps']);
    });

    test('a riposo i posti sono altrettanto fermi', () {
      monitor.update({'cpu': 12, 'ram': 11, 'net': 10, 'temps': 9});
      expect(monitor.calm, isTrue);
      final seated = monitor.active.map((m) => m.id).toList();
      expect(seated.length, 3, reason: 'a riposo non c\'è coda');

      monitor.update({'cpu': 12, 'ram': 14, 'net': 10, 'temps': 9});
      expect(monitor.active.map((m) => m.id).toList(), seated);
    });
  });

  group('niente balletto', () {
    test('chi oscilla intorno alla soglia rientra al posto suo', () {
      monitor.update({'cpu': 95, 'ram': 90, 'net': 85});
      expect(monitor.active.map((m) => m.id).toList(), ['cpu', 'ram', 'net']);

      // La RAM scende sotto la soglia di uscita e se ne va.
      clock.advance(60);
      monitor.update({'cpu': 95, 'ram': 40, 'net': 85});
      expect(monitor.active.map((m) => m.id).toList(), ['cpu', 'net']);

      // Risale e rientra: prima ricompariva in fondo, e a ogni oscillazione
      // la si vedeva saltare da una posizione all'altra.
      monitor.update({'cpu': 95, 'ram': 90, 'net': 85});
      expect(monitor.active.map((m) => m.id).toList(), ['cpu', 'ram', 'net'],
          reason: 'torna dov\'era, non in coda');
    });

    test('il posto non resta prenotato per sempre', () {
      monitor.update({'cpu': 95, 'ram': 90, 'net': 85});
      clock.advance(60);
      monitor.update({'cpu': 95, 'ram': 40, 'net': 85});

      // Passati due minuti la memoria scade: chi torna si accoda come un
      // arrivato qualunque, altrimenti scavalcherebbe chi si è seduto nel
      // frattempo.
      clock.advance(130);
      monitor.update({'cpu': 95, 'ram': 40, 'net': 85});
      monitor.update({'cpu': 95, 'ram': 90, 'net': 85});
      expect(monitor.active.map((m) => m.id).toList(), ['cpu', 'net', 'ram']);
    });

    test('due moduli appaiati non si scambiano di posto', () {
      // Stesso punteggio, e ogni campione lo fa oscillare di un soffio:
      // è il caso che faceva ballare le card.
      monitor.update({'cpu': 90, 'gpu': 90, 'net': 85});
      final order = monitor.active.map((m) => m.id).toList();

      for (final swing in [0.4, -0.3, 0.2, -0.5]) {
        monitor.update({'cpu': 90 + swing, 'gpu': 90 - swing, 'net': 85});
        expect(monitor.active.map((m) => m.id).toList(), order);
      }
    });
  });

  group('capienza', () {
    test('sotto tre non si scende', () {
      monitor.setCapacity(1);
      expect(monitor.capacity, 3);
    });

    test('la graduatoria va oltre i posti, o la capienza non crescerebbe mai', () {
      monitor.update({'cpu': 12, 'ram': 11, 'net': 10, 'temps': 9, 'disks': 8});
      expect(monitor.calm, isTrue);
      expect(monitor.active.length, 3, reason: 'i posti sono tre');
      // Su questi la vista conta quanti riquadri entrano nello schermo. Con
      // i soli tre seduti la risposta sarebbe sempre «tre», qualunque sia
      // l'altezza: tre entrano in tre posti, e la capienza non poteva
      // crescere mai.
      expect(monitor.ranked.length, 5);
      expect(monitor.ranked.first.id, 'cpu');
    });

    test('con più posti non si ruota, perché entrano tutti', () {
      monitor.setCapacity(6);
      monitor.update({
        'cpu': 99, 'topcpu': 98, 'ram': 95, 'net': 94, 'disks': 93, 'temps': 92,
      });
      expect(monitor.active.length, 6);
      expect(monitor.pageCount, 1, reason: 'niente da ruotare');
    });

    test('allargare la capienza fa salire chi era in coda', () {
      monitor.update({
        'cpu': 99, 'topcpu': 98, 'ram': 95, 'net': 94,
      });
      expect(monitor.pageCount, 2);
      expect(monitor.currentPage.length, 3);

      monitor.setCapacity(4);
      expect(monitor.pageCount, 1);
      expect(monitor.currentPage.map((m) => m.id).toList(),
          ['cpu', 'topcpu', 'ram', 'net']);
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
