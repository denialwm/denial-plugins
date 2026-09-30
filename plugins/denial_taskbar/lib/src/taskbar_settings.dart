import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'taskbar_preferences.dart';

export 'taskbar_preferences.dart';

final taskbarPreferencesProvider =
    AsyncNotifierProvider<TaskbarPreferencesController, TaskbarPreferences>(
      TaskbarPreferencesController.new,
    );

class TaskbarPreferencesController extends AsyncNotifier<TaskbarPreferences> {
  late TaskbarPreferencesStore _store;
  Future<void> _writes = Future.value();

  @override
  Future<TaskbarPreferences> build() {
    _store = TaskbarPreferencesStore(TaskbarPreferencesStore.defaultFile());
    return _store.read();
  }

  Future<void> updatePins(
    List<PinnedApplication> Function(List<PinnedApplication>) update,
  ) {
    final operation = _writes.then((_) async {
      if (!ref.mounted) return;
      final current = state.requireValue;
      final snapshot = List<PinnedApplication>.unmodifiable(
        update(current.pinned),
      );
      await _store.writePins(snapshot);
      if (!ref.mounted) return;
      state = AsyncData(
        TaskbarPreferences(
          leftAligned: state.value?.leftAligned ?? false,
          pinned: snapshot,
        ),
      );
    });
    // A failed write is reported to the invoking UI but must not poison later saves.
    _writes = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
