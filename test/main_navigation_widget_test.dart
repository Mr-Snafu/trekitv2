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
}
