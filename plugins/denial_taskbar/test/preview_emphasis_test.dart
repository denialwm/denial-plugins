import 'dart:async';
import 'dart:io';

import 'package:denial_taskbar/src/preview_emphasis.dart';

void check(Object? actual, Object? expected) {
  if (actual != expected) throw StateError('$actual != $expected');
}

class ScheduledTimer implements Timer {
  ScheduledTimer(this.deadline, this.callback);
  final int deadline;
  final void Function() callback;
  @override
  bool isActive = true;
  @override
  int tick = 0;
  @override
  void cancel() => isActive = false;
  void fire() {
    if (!isActive) return;
    isActive = false;
    tick = 1;
    callback();
  }
}

void main() {
  var now = 0;
  final timers = <ScheduledTimer>[];
  void advance(int milliseconds) {
    now += milliseconds;
    for (final timer in List.of(timers)) {
      if (timer.deadline <= now) timer.fire();
    }
  }

  runZoned(
    () {
      final starts = <int>[];
      final releases = <int>[];
      final hover = PreviewEmphasis(
        request: (id) {
          starts.add(id);
          return () => releases.add(id);
        },
      );
      hover.enter(1);
      advance(299);
      check(starts.length, 0);
      hover.enter(1); // Remaining on the same preview does not reset the delay.
      advance(1);
      check(starts.join(','), '1');
      hover.leave(1);
      check(releases.join(','), '1');

      hover.enter(2);
      advance(150);
      hover.enter(3);
      hover.leave(2); // A late exit must not cancel the new preview.
      advance(150);
      check(starts.join(','), '1');
      advance(150);
      check(starts.join(','), '1,3');
      hover.clear(); // Popup dismissal or dragging.
      hover.clear();
      check(releases.join(','), '1,3');

      hover.enter(4);
      advance(299);
      hover.leave(4);
      advance(1);
      check(starts.join(','), '1,3');
      hover.enter(5);
      advance(300);
      hover.dispose();
      check(releases.join(','), '1,3,5');
      hover.enter(6);
      advance(2000);
      check(starts.join(','), '1,3,5');

      final pending = PreviewEmphasis(
        request: (id) {
          throw StateError('Disposed pending hover fired');
        },
      );
      pending.enter(7);
      pending.dispose();
      advance(300);
    },
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        final timer = ScheduledTimer(now + duration.inMilliseconds, callback);
        timers.add(timer);
        return timer;
      },
    ),
  );
  stdout.writeln(
    'Preview hover delay, handoff, dismissal and disposal checks passed.',
  );
}
