import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trekit/features/home/presentation/home_screen.dart';
import 'package:trekit/features/trips/domain/trip_organizer.dart';

void main() {
  testWidgets('adventure organizer fits a phone-width screen', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final searchController = TextEditingController();
    addTearDown(searchController.dispose);
    var selectedFilter = TripOwnershipFilter.all;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdventureOrganizer(
            searchController: searchController,
            filter: selectedFilter,
            sortOrder: TripSortOrder.recentlyUpdated,
            visibleCount: 3,
            totalCount: 3,
            onSearchChanged: (_) {},
            onSearchClear: () => searchController.clear(),
            onFilterChanged: (value) => selectedFilter = value,
            onSortChanged: (_) {},
            onClear: () {},
          ),
        ),
      ),
    );

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Mine'), findsOneWidget);
    expect(find.text('Shared'), findsOneWidget);
    expect(find.text('3 adventures'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Mine'));
    expect(selectedFilter, TripOwnershipFilter.owned);
  });
}
