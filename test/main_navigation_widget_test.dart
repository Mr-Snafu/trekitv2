import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/home/presentation/home_screen.dart';

void main() {
  testWidgets('main navigation fits a phone-width screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var selectedIndex = -1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: TrekItNavigationBar(
            selectedIndex: 0,
            onSelected: (index) => selectedIndex = index,
          ),
        ),
      ),
    );

    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('Adventures'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Circle'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Create'));
    expect(selectedIndex, 2);
  });

  testWidgets('Create menu exposes every destination-aware action on mobile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var selectedAction = '';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CreateMenuSheet(
            canAddContent: true,
            onCreateAdventure: () => selectedAction = 'adventure',
            onCreateEntry: () => selectedAction = 'entry',
            onAddPhoto: () => selectedAction = 'photo',
            onCreateSnippet: () => selectedAction = 'snippet',
          ),
        ),
      ),
    );

    expect(find.text('New adventure'), findsOneWidget);
    expect(find.text('New journal entry'), findsOneWidget);
    expect(find.text('Add a photo'), findsOneWidget);
    expect(find.text('Quick Snippet'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Add a photo'));
    expect(selectedAction, 'photo');
    await tester.tap(find.text('Quick Snippet'));
    expect(selectedAction, 'snippet');
  });
}
