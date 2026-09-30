# Denial plugins

A collection of independently selectable plugins for
[Denial](https://github.com/denialwm/denial), a Flutter-native Wayland compositor.
The repository is a source container. Each plugin is its own Dart package;
installing one does not enable all packages in this repository.

| Package | Path | Purpose |
| --- | --- | --- |
| `denial_taskbar` | [`plugins/denial_taskbar`](plugins/denial_taskbar) | Bottom taskbar, application groups and previews, pins, tray, clock, and Show Desktop. |

`plugins.yaml` is the discovery catalog used by Denial's Plugin Manager.
It records Git sources and package paths. Dependencies and contribution metadata
belong in each package's `pubspec.yaml` and annotated Dart libraries.

## Install

In Denial's Plugins app, find Taskbar in Discover, select it, and Apply.
For direct Git installation, paste this repository URL and select the
`plugins/denial_taskbar` package. Check the current ShellWorkArea selection;
the taskbar supplies its own bottom work-area provider.

The CLI equivalent is:

```sh
denial-plugins prepare
denial-plugins inspect https://github.com/denialwm/denial-plugins.git
denial-plugins --path plugins/denial_taskbar add https://github.com/denialwm/denial-plugins.git
denial-plugins plan
denial-plugins build CANDIDATE_ID
denial-plugins activate CANDIDATE_ID
```

Replace `CANDIDATE_ID` with the ID returned by `plan`. Resolve exclusive-provider
choices reported by the manager before building. Apply records an exact Git
commit and package path; later builds retain that revision until an explicit
update. Catalog membership itself does not activate a plugin.

## Develop and contribute

Read [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the manual SDK and editor setup.
Add independently selectable plugins below `plugins/PACKAGE_NAME/`, each with its
own `pubspec.yaml` and public contribution library. Put ordinary shared libraries
below `packages/` when needed and declare package dependencies normally. Add one
`plugins.yaml` entry per installable plugin; do not list shared libraries or
fixtures in the catalog. The repository root is not a Dart package.

The current plugins target Denial's Flutter 3.47.5/Dart 3.13 generation. Original
source is GPL-3.0-or-later; third-party libraries retain their own licenses.
