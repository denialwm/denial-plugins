import 'dart:convert';
import 'dart:io';

import 'package:denial_taskbar/src/taskbar_preferences.dart';

void check(Object? actual, Object? expected) {
  if (actual != expected) throw StateError('$actual != $expected');
}

Future<void> main() async {
  final order = TaskbarOrder();
  check(order.update(['b', 'a'], ['p', 'q']).join(','), 'p,q,b,a');
  check(order.update(['a', 'b'], ['p', 'q']).join(','), 'p,q,b,a');
  check(order.reorder(3, 1).join(','), 'p,a,q,b');
  check(order.update(['c', 'b', 'a'], ['p', 'q']).join(','), 'p,a,q,b,c');
  check(order.update(['c', 'b'], ['p', 'q']).join(','), 'p,q,b,c');
  check(order.reorder(0, 2).join(','), 'q,b,p,c');
  check(order.update(['b', 'c'], ['q', 'p']).join(','), 'q,b,p,c');
  check(order.update([], ['q', 'p']).join(','), 'q,p');
  check(TaskbarOrder().update(['b'], ['q', 'p']).join(','), 'q,p,b');
  check(order.update([], ['p']).join(','), 'p');
  check(order.update([], []).join(','), '');
  // Pinning an existing app preserves its current slot among running apps.
  final running = TaskbarOrder();
  running.update(['a', 'b', 'c'], []);
  check(running.update(['a', 'b', 'c'], ['b']).join(','), 'a,b,c');
  check(running.update(['a', 'c'], ['b']).join(','), 'a,b,c');
  // Other monitors adopt pinned relative order without moving unpinned slots.
  check(running.update(['a', 'c'], ['c', 'b']).join(','), 'a,c,b');
  check(normalizeApplicationId(' Editor.DESKTOP '), 'editor');

  final directory = await Directory.systemTemp.createTemp(
    'denial-taskbar-test-',
  );
  try {
    final file = File('${directory.path}/nested/settings.json');
    final store = TaskbarPreferencesStore(file);
    check((await store.read()).pinned.length, 0);
    await file.parent.create();
    await file.writeAsString(
      jsonEncode({'iconAlignment': 'left', 'futureSetting': 42}),
    );
    const first = PinnedApplication(
      id: 'desktop:editor.desktop',
      appId: 'editor.desktop',
      name: 'Editor',
    );
    const second = PinnedApplication(
      id: 'local:settings',
      appId: 'settings',
      name: 'Settings',
    );
    await store.writePins([second, first]);
    final loaded = await TaskbarPreferencesStore(file).read();
    check(loaded.leftAligned, true);
    check(
      loaded.pinned.map((pin) => pin.id).join(','),
      'local:settings,desktop:editor.desktop',
    );
    check((jsonDecode(await file.readAsString()) as Map)['futureSetting'], 42);
    await store.writePins([first]);
    check((await store.read()).pinned.single.name, 'Editor');
    check((await file.parent.list().toList()).length, 1);
    final parsed = TaskbarPreferences.fromJson({
      'pinnedApplications': [
        first.toJson(),
        first.toJson(),
        {'id': 7},
        null,
      ],
    });
    check(parsed.pinned.length, 1);
    await file.writeAsString('{broken');
    var rejected = false;
    try {
      await store.writePins([]);
    } on FormatException {
      rejected = true;
    }
    check(rejected, true);
    check(await file.readAsString(), '{broken');
  } finally {
    await directory.delete(recursive: true);
  }
  stdout.writeln('Taskbar ordering and atomic preference checks passed.');
}
