import 'dart:io';

import 'package:denial_taskbar/src/window_groups.dart';

typedef Window = ({int id, String app});

void main() {
  final groups = WindowGroups<Window>(idOf: (w) => w.id, appOf: (w) => w.app);
  const a = (id: 1, app: 'Editor.desktop');
  const b = (id: 2, app: 'Browser');
  const c = (id: 3, app: 'editor');
  const d = (id: 4, app: 'Terminal');
  void check(List<Window> windows, String expected) {
    final actual = groups
        .update(windows)
        .values
        .map((group) => group.map((w) => w.id).join(','))
        .join('|');
    if (actual != expected) throw StateError('$actual != $expected');
  }

  check([a, b], '1|2');
  check([b, a], '1|2'); // Focus reorder is ignored.
  check([c, b, a], '1,3|2'); // Same app stacks and instances stay ordered.
  check([d, c, a, b], '1,3|2|4'); // New app appends even if first in input.
  check([d, c, b], '3|2|4'); // Closing first instance retains group position.
  check([d, b], '2|4');
  check([a, d, b], '2|4|1'); // Reopened group appends.
  check([], '');
  check([(id: 5, app: ''), (id: 6, app: '')], '5|6');
  check([(id: 6, app: ''), (id: 5, app: '')], '5|6');
  stdout.writeln('Window grouping and stable ordering checks passed.');
}
