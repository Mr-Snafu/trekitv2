import 'package:flutter/material.dart';

import '../domain/trip.dart';

IconData tripCategoryIcon(TripCategory category) {
  return switch (category) {
    TripCategory.roadTrip => Icons.directions_car_outlined,
    TripCategory.vacation => Icons.beach_access_outlined,
    TripCategory.outdoorAdventure => Icons.landscape_outlined,
    TripCategory.specialEvent => Icons.celebration_outlined,
    TripCategory.familyEvent => Icons.family_restroom_outlined,
    TripCategory.nightOut => Icons.nightlife_outlined,
    TripCategory.dayTrip => Icons.wb_sunny_outlined,
    TripCategory.other => Icons.category_outlined,
  };
}

Color tripCategoryColor(TripCategory category) {
  return switch (category) {
    TripCategory.roadTrip => const Color(0xFFB85D22),
    TripCategory.vacation => const Color(0xFF167A8A),
    TripCategory.outdoorAdventure => const Color(0xFF28745B),
    TripCategory.specialEvent => const Color(0xFFA33F65),
    TripCategory.familyEvent => const Color(0xFF7654A8),
    TripCategory.nightOut => const Color(0xFF4D568E),
    TripCategory.dayTrip => const Color(0xFF9A6B10),
    TripCategory.other => const Color(0xFF6C625B),
  };
}
