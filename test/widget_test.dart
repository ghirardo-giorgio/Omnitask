import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask/models/snapshot.dart';
import 'package:omnitask/widgets/sparkline.dart';

void main() {
  group('Series', () {
    test('un fondoscala fisso vince sull\'autoscale', () {
      final series = Series(
        values: const [10, 20, 30],
        unit: 'percent',
        max: 100,
        color: '#58a6ff',
      );
      expect(series.scaleFor(), 100);
      expect(series.latest, 30);
    });

    test('l\'autoscale tiene il minimo e lascia un margine sopra il picco', () {
      final watts = Series(
        values: const [4, 9, 6],
        unit: 'watts',
        max: 0,
        color: '#3fb950',
        autoscale: true,
        minScale: 60,
      );
      // Il picco e' 9, ma il minimo dichiarato e' 60: senza, un consumo di
      // due watt riempirebbe il grafico come se fosse tanto.
      expect(watts.scaleFor(), closeTo(69, 0.001));
    });

    test('un buco resta un buco, e l\'ultimo valore lo salta', () {
      final heart = Series(
        values: const [70, null, null],
        unit: 'bpm',
        max: 0,
        color: '#f85149',
        autoscale: true,
        gaps: true,
      );
      expect(heart.values[1], isNull);
      expect(heart.latest, 70);
      expect(heart.isEmpty, isFalse);
    });

    test('una serie tutta vuota si riconosce', () {
      final empty = Series(
        values: const [null, null],
        unit: 'bpm',
        max: 0,
        color: '#f85149',
      );
      expect(empty.isEmpty, isTrue);
      expect(empty.latest, isNull);
    });
  });

  group('Snapshot', () {
    test('assorbe le sorgenti e ne ricava le serie', () {
      final snapshot = Snapshot();
      snapshot.absorb({
        'overview': {'cpu': {'busy_percent': 12.5}},
        'series': {
          'series': {
            'cpu': {'values': [1, 2, 3], 'unit': 'percent', 'max': 100, 'color': '#3fb950'},
          },
        },
      });
      expect(snapshot['overview']?['cpu']['busy_percent'], 12.5);
      expect(snapshot.series('cpu')?.values.length, 3);
      expect(snapshot.series('memoria-che-non-c-e'), isNull);
      expect(snapshot.ageOf('overview'), isNotNull);
    });

    test('un aggiornamento parziale non cancella le altre sorgenti', () {
      final snapshot = Snapshot();
      snapshot.absorb({'health': {'uptime_seconds': 10}});
      snapshot.absorb({'overview': {'cpu': {'busy_percent': 1}}});
      expect(snapshot['health'], isNotNull);
      expect(snapshot['overview'], isNotNull);
    });
  });

  testWidgets('lo sparkline si disegna anche senza dati', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Sparkline(series: null, height: 40)),
    ));
    expect(find.byType(Sparkline), findsOneWidget);
  });
}
