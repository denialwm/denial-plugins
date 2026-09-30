/// Session-local ordering: enumeration seeds it, focus changes never reorder it.
/// Closed groups are forgotten; a newly opened group is appended.
class WindowGroups<T> {
  WindowGroups({required this.idOf, required this.appOf});
  final int Function(T) idOf;
  final String Function(T) appOf;
  final _groups = <String, List<int>>{};

  Map<String, List<T>> update(Iterable<T> windows) {
    final byId = <int, T>{};
    final keys = <int, String>{};
    for (final window in windows) {
      final id = idOf(window);
      final app = appOf(window)
          .trim()
          .toLowerCase()
          .replaceFirst(RegExp(r'\.desktop$'), '');
      final key = app.isEmpty ? 'window:$id' : 'app:$app';
      byId[id] = window;
      keys[id] = key;
    }
    for (final entry in _groups.entries) {
      entry.value.removeWhere((id) => keys[id] != entry.key);
    }
    _groups.removeWhere((_, ids) => ids.isEmpty);
    for (final entry in keys.entries) {
      final ids = _groups.putIfAbsent(entry.value, () => []);
      if (!ids.contains(entry.key)) ids.add(entry.key);
    }
    return {
      for (final entry in _groups.entries)
        entry.key: [for (final id in entry.value) byId[id] as T],
    };
  }
}
