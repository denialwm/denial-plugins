# Denial taskbar

A Windows-style, full-width bottom panel using
[`material_ui` 1.4](https://pub.dev/packages/material_ui). Its annotated
`TaskbarPlugin` implements the public `ShellSurface` contract and declares its own
52-logical-pixel bottom bounds, output selection and visibility policy. A separate
`TaskbarWorkArea` contribution reserves native window space. Its reservation also
includes the configured window spacing on the inner edge, so tiles do not touch
the visible bar. The painted bar remains full-width and flush with the bottom. The
glass backdrop extends 3 logical pixels past the left, right, and bottom edges,
then clips to the allocated monitor strip. This hides the outer glass rim without
painting onto adjacent outputs or moving controls and work-area reservations.

- Launcher button opens the existing application launcher.
- Windows group by application ID. Group and instance ordering stays stable for
  the lifetime of the panel; new groups append and focus changes do not reorder.
  The list follows the output's current workspace, including minimized windows.
- Hover an icon to see animated live client previews with title overlays, centered above
  the group and bounded to its monitor. Large groups scroll horizontally. Click
  a preview to focus/restore that window; clicking a grouped icon opens its row.
  Client texture updates drive previews without screenshots or window resizing.
  Windows without client textures use the host's application-icon fallback.
- Right-click an application for a compact glass menu with Pin/Unpin. Pinned
  applications remain when closed; clicking an idle pin launches its catalog entry.
  Windows without a resolvable launcher entry cannot be pinned. Escape and any
  outside mouse-button press dismiss the menu; Shift+F10 opens it from the keyboard.
- Drag application icons to reorder them. Mouse dragging is reserved for reorder;
  wheel/trackpad scrolling and edge auto-scroll remain available. The launcher stays first and cannot be
  dragged. Pin identities and their relative order persist across shell reloads;
  unpinned positions last for the current shell session. New applications append.
- Holding the pointer over one preview for 300ms emphasizes that window
  by fading other windows on that bar's monitor and current workspace to 25% opacity. Both directions animate, preserving
  glass. Leaving, dismissing, or activating ends the temporary effect.
- Fullscreen and workspace visibility changes fade the panel in and out while
  retaining its session ordering. Hiding dismisses previews and tray flyouts.
- Running groups show at most two overlapping underline layers, with the rear
  layer offset horizontally to the right of the centered front stroke. Active
  groups use a slightly smaller offset and darker rear layer for their glass
  focus highlight.
  Closed pins have no running indicator. Preview motion respects reduced motion.
- Launcher, tray controls, clock, and date use neutral foreground colors.
- Clock and date use the shell's locale and sit at the right edge.
- A 12px transparent strip at the far-right edge toggles Show Desktop across
  outputs. It retains window geometry, stacking, and minimized state, and clicking
  again restores the presentation. It has a subtle divider and keyboard/hover
  feedback, without an icon or opaque fill.
- The first three tray icons appear inline. Additional icons go into a compact
  glass popup with 6px padding, sized to its contents. The chevron is hidden when
  there is no overflow. Icon order is retained for the panel lifetime, so status
  changes do not move icons between the bar and popup. New icons append and
  removal promotes the next icon into the bar.
- Native tray activation and context menus remain available. Escape or an outside
  click closes the popup; it also closes when no overflow icons remain.
- The bar uses Denial's shared glass backdrop filter and panel opacity;
  light/dark colors follow the shell theme. Window buttons scroll on crowded
  panels; the entire control strip can scroll on unusually narrow outputs.

The plugin has no shell implementation imports. `ShellServices` supplies window
projections, actions, icon rendering, clock, localization, and tray presentation.
Modern Material theme/localization delegates are scoped to the plugin subtree;
no second `MaterialApp` or navigator is created.

Install and select the package through Denial's Plugin Manager. The generated
composition supplies services and scene facts; the plugin decides its placement.
It does not require a shell
import or a hand-maintained provider list. Its bottom placement takes precedence over
edge/thickness settings, while configured output selection remains respected.

## Development and installation

This package lives at `plugins/denial_taskbar` in the
[Denial plugin collection](https://github.com/denialwm/denial-plugins).
The Dart package name is `denial_taskbar`; other packages in the collection
are independently selectable.

Follow the collection's [development guide](../../docs/DEVELOPMENT.md) for
manual SDK overrides, editor setup, checks, and installation. SDK sources come
from the matching Denial installation; no Denial SDK publication to pub.dev is
required. Plugin Manager supplies the installed SDK when compiling this package.

The pure Dart checks are `test/window_groups_test.dart`,
`test/preview_emphasis_test.dart`, and `test/taskbar_preferences_test.dart`.
Run each with Denial's matching `dart` executable. Visual validation belongs to
the user.

## Icon alignment (no settings UI yet)

The launcher and app icons are centered on the monitor by default. The clock
and tray stay at the right edge. Crowded groups use the available space and
retain horizontal scrolling.

To restore left alignment, put this in
`$XDG_CONFIG_HOME/denial/plugins/denial_taskbar.json` (normally
`~/.config/denial/plugins/denial_taskbar.json`):

```json
{"iconAlignment": "left"}
```

Use `"center"` or remove the option for the default. Missing, unreadable, or
invalid configuration falls back to centered. Preferences are read once per
shell lifetime; reload the existing shell bundle after editing, without a Rust
rebuild or compositor restart.

Pinning writes an ordered `pinnedApplications` array to the same configuration
file, preserving `iconAlignment` and other keys. Each item stores the host's
opaque launch `id`, icon `appId`, and fallback `name`. Writes are serialized and
atomic. A read/write error is shown in the Taskbar instead of silently claiming
the change was saved. Persisted entries contain no executable command lines.
