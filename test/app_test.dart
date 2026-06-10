// HydroIQ — Basic smoke test
// Ensures the app compiles and core constants are accessible.
import 'package:flutter_test/flutter_test.dart';
import 'package:hydroiq/core/constants/app_constants.dart';

void main() {
  group('AppConstants', () {
    test('app name is HydroIQ', () {
      expect(AppConstants.appName, 'HydroIQ');
    });

    test('default daily goal is 2000 ml', () {
      expect(AppConstants.defaultDailyGoalMl, 2000);
    });

    test('quick add amounts are correct', () {
      expect(AppConstants.quickAddAmounts, [100, 250, 500, 1000]);
    });
  });
}
