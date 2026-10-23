import 'dart:io';

import 'package:denial_taskbar/src/taskbar_actions.dart';

void main() {
  List<String> clicks({required bool tiled, required bool initiallyMinimized}) {
    var minimized = initiallyMinimized;
    return List.generate(3, (_) {
      final minimize = shouldMinimizeTaskbarWindow(
        tiled: tiled,
        minimized: minimized,
      );
      // Model the compositor publishing the result before the next click.
      minimized = minimize;
      return minimize ? 'minimize' : 'activate';
    });
  }

  for (final scenario in [
    (
      tiled: true,
      initiallyMinimized: false,
      expected: 'minimize,activate,minimize',
    ),
    (
      tiled: true,
      initiallyMinimized: true,
      expected: 'activate,minimize,activate',
    ),
    (
      tiled: false,
      initiallyMinimized: false,
      expected: 'activate,activate,activate',
    ),
    (
      tiled: false,
      initiallyMinimized: true,
      expected: 'activate,activate,activate',
    ),
  ]) {
    if (clicks(
          tiled: scenario.tiled,
          initiallyMinimized: scenario.initiallyMinimized,
        ).join(',') !=
        scenario.expected) {
      throw StateError('Unexpected repeated-click behavior: $scenario');
    }
  }
  if (shouldMinimizeTaskbarWindow(
    tiled: true,
    minimized: false,
    desktopVisible: true,
  )) {
    throw StateError(
      'Clicking a hidden tile during Show Desktop must reveal it.',
    );
  }
  // A mixed group hides its remaining visible windows; an entirely minimized
  // group restores, so repeated clicks can always bring the app back.
  for (final group in [
    (minimized: [false, true], expected: true),
    (minimized: [true, true], expected: false),
  ]) {
    if (shouldMinimizeTaskbarWindow(
          tiled: true,
          minimized: group.minimized.every((value) => value),
        ) !=
        group.expected) {
      throw StateError('Wrong grouped-window click behavior: $group');
    }
  }
  const batterySteps = {
    -1: 0,
    0: 0,
    14: 0,
    15: 1,
    29: 1,
    30: 2,
    44: 2,
    45: 3,
    59: 3,
    60: 4,
    74: 4,
    75: 5,
    89: 5,
    90: 6,
    99: 6,
    100: 7,
    101: 7,
  };
  for (final entry in batterySteps.entries) {
    if (taskbarBatteryBars(entry.key) != entry.value) {
      throw StateError('Wrong battery icon at ${entry.key}%');
    }
  }
  stdout.writeln('Taskbar window toggles and battery level checks passed.');
}
