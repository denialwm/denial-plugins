# Developing plugins in this collection

Each `plugins/PACKAGE_NAME/` directory is an independently selectable Dart
package. Run Pub and analysis from that package directory. The repository root
is not a Pub workspace or a plugin; ordinary shared libraries belong in
`packages/` and do not appear in the catalog.

Read Denial's [plugin development guide](https://github.com/denialwm/denial/blob/dev/docs/PLUGIN_DEVELOPMENT.md)
and [architecture contract](https://github.com/denialwm/denial/blob/dev/docs/PLUGIN_SYSTEM.md)
for SDK contracts and annotation discovery. The steps below are manual.

## 1. Prepare Denial's matching tools

Use a Denial installation with Plugin Manager and its release compiler kit:

```sh
denial-plugins prepare
DENIAL_PLUGIN_STATE="${XDG_STATE_HOME:-$HOME/.local/state}/denial/plugins"
DENIAL_PLUGIN_FLUTTER="$(jq -er '.flutter' "$DENIAL_PLUGIN_STATE/configuration.json")"
DENIAL_PLUGIN_RUNTIME="$(jq -er '.runtime' "$DENIAL_PLUGIN_STATE/configuration.json")"
DENIAL_PLUGIN_FLUTTER_ROOT="$(dirname "$(dirname "$DENIAL_PLUGIN_FLUTTER")")"
DENIAL_PLUGIN_DART="$DENIAL_PLUGIN_FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart"
```

Keep that terminal open. `prepare` verifies the kit and copies it into a writable
user cache. The normal Denial package supplies these tools and SDK sources.
`denial-ui-development` is optional for live JIT/hot-reload work and is not
required for release plugin builds. Do not run Flutter from package-managed
`/usr/lib` paths; it needs writable caches.

For a Denial source checkout, run `tools/denial-pc plugin-manager` and
`tools/denial-plugins prepare` from that checkout first, outside its sandbox.
Use its `tools/denial-plugins` for manager commands below.

## 2. Open one package

```sh
git clone https://github.com/denialwm/denial-plugins.git
cd denial-plugins/plugins/denial_taskbar
```

For a new plugin, create `plugins/YOUR_PACKAGE/` with its own `pubspec.yaml` and
`lib/` directory. Declare the matching Denial SDK versions in `dependencies`.
Current source metadata versions are `denial_sdk: '0.0.0'` and
`denial_flutter_sdk: '0.0.0'`, with Dart `^3.13.0` and Flutter `3.47.5`.
Check your installed SDK manifests when targeting another Denial generation.

## 3. Write local SDK overrides manually

Print the runtime source path:

```sh
printf '%s\n' "$DENIAL_PLUGIN_RUNTIME"
```

Create `pubspec_overrides.yaml` in the package directory. Replace
`/ABSOLUTE/RUNTIME` with that printed path; YAML does not expand shell variables:

```yaml
dependency_overrides:
  denial_sdk:
    path: /ABSOLUTE/RUNTIME/packages/denial_sdk
  denial_flutter_sdk:
    path: /ABSOLUTE/RUNTIME/packages/denial_flutter_sdk
```

This file is ignored by Git. Commit SDK constraints in `pubspec.yaml`; never
commit machine-local paths or SDK copies. Plugin Manager supplies its own
installed SDK overrides when users install a Git package. No SDK or plugin
publication to pub.dev is required. Ordinary third-party Dart dependencies
can still come from pub.dev.

## 4. Select the editor SDK manually

Print the Flutter root:

```sh
printf '%s\n' "$DENIAL_PLUGIN_FLUTTER_ROOT"
```

Create `.vscode/settings.json` in the package directory, replacing
`/ABSOLUTE/FLUTTER` with that path:

```json
{
  "dart.flutterSdkPath": "/ABSOLUTE/FLUTTER",
  "dart.sdkPath": "/ABSOLUTE/FLUTTER/bin/cache/dart-sdk"
}
```

Other editors should use those same SDK directories for analysis. Reload the
analysis server after changing paths. Both local files are ignored. After a
Denial upgrade, prepare again and update the overrides and editor paths to the
new kit.

## 5. Resolve and check

From the selected package directory:

```sh
"$DENIAL_PLUGIN_FLUTTER" pub get
"$DENIAL_PLUGIN_DART" format --output=none --set-exit-if-changed lib test
"$DENIAL_PLUGIN_DART" analyze --fatal-infos lib
```

For the taskbar, also run its headless checks:

```sh
"$DENIAL_PLUGIN_DART" test/window_groups_test.dart
"$DENIAL_PLUGIN_DART" test/preview_emphasis_test.dart
"$DENIAL_PLUGIN_DART" test/taskbar_preferences_test.dart
```

Use public SDK contracts and annotated `@Plugin()` libraries with
`@Provides(Contract)` classes. Keep advisory `denial_plugin` declarations in
sync with the actual contributions. Visual validation belongs to the user.

## 6. Build and install

To try an edited package without publishing it:

```sh
denial-plugins --local add "$PWD"
denial-plugins plan
denial-plugins build CANDIDATE_ID
```

Replace `CANDIDATE_ID` with the ID returned by `plan`. Resolve any reported
exclusive-provider choice or missing dependency before building. Activate the
completed candidate with `denial-plugins activate CANDIDATE_ID`, or use Apply
in Plugins. Activation changes the desktop; run it when you intend to apply
the plugin. Do not restart the compositor for ordinary plugin edits.

To test Git distribution, commit and push the collection, then inspect its URL
and add the selected package using `--path plugins/PACKAGE_NAME`. The manager
pins the resolved commit; an explicit Update advances it. A local source and a
Git source with the same package name require explicit replacement in the
selection; they are not separate plugin identities.

## 7. Add a catalog entry

Add one entry per installable plugin to root `plugins.yaml`:

```yaml
schema: 1
plugins:
  - git: https://github.com/denialwm/denial-plugins.git
    path: plugins/denial_taskbar
```

Future plugins add entries with their own package paths. Names, descriptions,
SDK constraints, dependencies, and contributions stay in each package.
Catalog entries accept only `git`, `path`, and optional `ref`; catalog inclusion
does not activate anything or declare dependencies among sibling plugins.
