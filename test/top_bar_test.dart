import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serafim/src/utils/app_top_bar.dart';
import 'package:serafim/src/utils/serafim_mark.dart';

Future<void> _bar(WidgetTester t, AppTopBar bar) =>
    t.pumpWidget(MaterialApp(home: Scaffold(appBar: bar)));

void main() {
  testWidgets('the brand bar shows the Serafim logo and name', (t) async {
    await _bar(t, const AppTopBar());
    expect(find.byType(SerafimMark), findsOneWidget);
    expect(find.text('SERAFIM'), findsOneWidget);
  });

  testWidgets('other bars show just their title', (t) async {
    await _bar(t, const AppTopBar(title: 'CHATS'));
    expect(find.byType(SerafimMark), findsNothing);
    expect(find.text('CHATS'), findsOneWidget);
  });
}
