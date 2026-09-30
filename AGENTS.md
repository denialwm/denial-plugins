# Denial plugin collection

This repository contains multiple independently selectable Dart plugin packages.
Keep plugins under `plugins/PACKAGE_NAME/`; the repository root is not a package.
Ordinary shared libraries belong under `packages/` and are not catalog entries.

For plugin development refer to [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
Read Denial's [plugin-system contract](https://github.com/denialwm/denial/blob/dev/docs/PLUGIN_SYSTEM.md)
and [manager contract](https://github.com/denialwm/denial/blob/dev/docs/PLUGIN_MANAGER.md)
before changing contribution or distribution behavior.

Use public Denial SDK imports. Commit SDK version constraints, never machine-local
SDK paths or overrides. The matching Denial installation supplies the SDK and
compiler; neither needs pub.dev publication. Keep each plugin's metadata and
contributions in its package. Root `plugins.yaml` records only Git sources,
package paths, and optional refs. Adding a catalog entry must not activate it.

Preserve package names and independent selection. A collection is not one large
plugin and does not imply dependency relationships among sibling packages.

The user owns all visual validation. Do not capture or inspect screenshots,
launch visual QA applications, or trigger visible test events. Do not stop or
restart the user's local graphical session. Headless analysis, pure Dart checks,
repository inspection, and compilation are permitted. Follow the Denial
checkout's AGENTS.md when using its build, packaging, or deployment tools.
