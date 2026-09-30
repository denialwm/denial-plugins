import 'dart:convert';
import 'dart:io';

String normalizeApplicationId(String id) =>
    id.trim().toLowerCase().replaceFirst(RegExp(r'\.desktop$'), '');

class PinnedApplication {
  const PinnedApplication({
    required this.id,
    required this.appId,
    required this.name,
  });
  final String id;
  final String appId;
  final String name;
  Map<String, String> toJson() => {'id': id, 'appId': appId, 'name': name};
}

class TaskbarPreferences {
  const TaskbarPreferences({this.leftAligned = false, this.pinned = const []});
  final bool leftAligned;
  final List<PinnedApplication> pinned;

  factory TaskbarPreferences.fromJson(Map<String, dynamic> json) {
    final seen = <String>{};
    final pins = <PinnedApplication>[];
    if (json['pinnedApplications'] case final List entries) {
      for (final entry in entries) {
        if (entry is! Map) continue;
        final id = entry['id'];
        final appId = entry['appId'];
        final name = entry['name'];
        if (id is! String ||
            id.isEmpty ||
            appId is! String ||
            appId.isEmpty ||
            name is! String ||
            !seen.add(id)) {
          continue;
        }
        pins.add(PinnedApplication(id: id, appId: appId, name: name));
      }
    }
    return TaskbarPreferences(
      leftAligned: json['iconAlignment'] == 'left',
      pinned: List.unmodifiable(pins),
    );
  }
}

/// Atomic, plugin-owned preferences. Preserve alignment and unknown keys when
/// updating pins; never replace a malformed or unreadable user file silently.
class TaskbarPreferencesStore {
  TaskbarPreferencesStore(this.file);
  final File file;
  int _sequence = 0;

  static File defaultFile() {
    final env = Platform.environment;
    final configured = env['XDG_CONFIG_HOME'];
    final home = env['HOME'];
    final root = configured != null && configured.startsWith('/')
        ? configured
        : home != null && home.startsWith('/')
        ? '$home/.config'
        : null;
    if (root == null) {
      throw const FileSystemException('No configuration directory');
    }
    return File('$root/denial/plugins/denial_taskbar.json');
  }

  Future<Map<String, dynamic>> _readJson() async {
    try {
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object');
      }
      return value;
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 2) return {};
      rethrow;
    }
  }

  Future<TaskbarPreferences> read() async =>
      TaskbarPreferences.fromJson(await _readJson());

  Future<void> writePins(List<PinnedApplication> pins) async {
    final json = await _readJson();
    json['pinnedApplications'] = pins.map((pin) => pin.toJson()).toList();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.$pid.${_sequence++}.tmp');
    try {
      await temp.writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(json)}\n',
        flush: true,
      );
      await temp.rename(file.path);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }
}

/// Live ordering is independent of focus and catalog enumeration. Only pinned
/// relative order is restored between sessions; new running apps append.
class TaskbarOrder {
  final _keys = <String>[];
  List<String> _pins = [];

  List<String> update(Iterable<String> live, Iterable<String> pinned) {
    final nextPins = pinned.toList();
    final liveKeys = live.toList();
    final valid = {...liveKeys, ...nextPins};
    _keys.removeWhere((key) => !valid.contains(key));
    if (_keys.isEmpty) _keys.addAll(nextPins);
    // Synchronize the relative pinned order across output instances without
    // moving unpinned entries that the user has positioned between pins.
    if (!_same(_pins, nextPins)) {
      for (final key in nextPins) {
        if (!_keys.contains(key)) _keys.add(key);
      }
      final slots = [
        for (var i = 0; i < _keys.length; i++)
          if (nextPins.contains(_keys[i])) i,
      ];
      for (var i = 0; i < slots.length; i++) {
        _keys[slots[i]] = nextPins[i];
      }
      _pins = List.of(nextPins);
    }
    for (final key in liveKeys) {
      if (!_keys.contains(key)) _keys.add(key);
    }
    return List.unmodifiable(_keys);
  }

  List<String> reorder(int from, int to) {
    if (from < 0 || from >= _keys.length || to < 0 || to >= _keys.length) {
      return List.unmodifiable(_keys);
    }
    final key = _keys.removeAt(from);
    _keys.insert(to, key);
    return List.unmodifiable(_keys);
  }

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length &&
      List.generate(a.length, (i) => a[i] == b[i]).every((v) => v);
}
