// Diagnostic : l'ancienne pastille (Badge + StreamBuilder) dans un ListTile de tiroir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ancienne pastille dans le tiroir', (tester) async {
    final flux = Stream<List<Map<String, dynamic>>>.value([
      {'n': 2}
    ]);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: Scaffold(
        drawer: Drawer(
          child: ListView(children: [
            ListTile(
              leading: StreamBuilder<List<Map<String, dynamic>>>(
                stream: flux,
                builder: (context, snap) {
                  final n = ((snap.data ?? const []).firstOrNull?['n'] as int?) ?? 0;
                  return Badge(isLabelVisible: n > 0, label: Text('$n'), backgroundColor: Colors.red, child: const Icon(Icons.local_bar));
                },
              ),
              title: const Text('Bar'),
            ),
          ]),
        ),
        body: const SizedBox(),
      ),
    ));
    final ScaffoldState s = tester.state(find.byType(Scaffold));
    s.openDrawer();
    await tester.pumpAndSettle();
    final e = tester.takeException();
    // ignore: avoid_print
    print('DIAGNOSTIC exception: $e');
    // ignore: avoid_print
    print('DIAGNOSTIC taille leading: ${tester.getSize(find.byType(StreamBuilder<List<Map<String, dynamic>>>))}');
  });
}
