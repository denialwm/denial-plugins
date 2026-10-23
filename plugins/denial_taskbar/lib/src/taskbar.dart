import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'tray.dart';
import 'window_buttons.dart';
import 'neutral_color.dart';
import 'taskbar_actions.dart';
import 'system_status.dart';

/// A continuous desktop panel. Native window surfaces remain host-owned.
class WindowsTaskbar extends StatelessWidget {
  const WindowsTaskbar({
    required this.monitorId,
    required this.services,
    super.key,
  });
  final int monitorId;
  final ShellServices services;

  // Deriving a scheme from a seed solves dozens of HCT colors (about 1 ms on
  // the Pad 4), so the theme is reused while the accent and brightness stay.
  static ThemeData? _theme;
  static (Color, Brightness)? _themeKey;

  static ThemeData _themeFor(Color accent, Brightness brightness) {
    final key = (accent, brightness);
    if (_themeKey == key) {
      return _theme!;
    }
    _themeKey = key;
    return _theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
      ),
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.compact,
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 600),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shell = context.shellTheme;
    return ShellServicesScope(
      services: services,
      child: Localizations.override(
        context: context,
        delegates: GlobalMaterialLocalizations.delegates,
        child: Theme(
          data: _themeFor(shell.accent, shell.brightness),
          // Desktop mouse drags belong to app reordering. The shell globally
          // enables mouse drag scrolling, which otherwise competes in both the
          // app list and the outer narrow-output scroll view. Wheel/trackpad
          // scrolling and reorder edge auto-scroll remain available.
          child: ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: ScrollConfiguration.of(context).dragDevices
                  .where((device) => device != PointerDeviceKind.mouse)
                  .toSet(),
            ),
            child: _TaskbarSurface(monitorId: monitorId),
          ),
        ),
      ),
    );
  }
}

class _TaskbarSurface extends ConsumerWidget {
  const _TaskbarSurface({required this.monitorId});
  final int monitorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).colorScheme;
    final services = ShellServicesScope.of(context);
    final workspace = ref.watch(services.workspacesEnabled)
        ? ref.watch(services.workspace(monitorId))
        : null;
    final battery = ref.watch(services.battery);
    return ShellInputRegion(
      debugLabel: 'Taskbar',
      child: _TaskbarBackdrop(
        child: Material(
          color: context.shellTheme.panelColor(colors.surfaceContainer),
          surfaceTintColor: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.outlineVariant)),
            ),
            child: FocusTraversalGroup(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        // Keep controls reachable on narrow outputs and with large text.
                        final clockWidth =
                            (106 * MediaQuery.textScalerOf(context).scale(1))
                                .clamp(106.0, 190.0);
                        final workspaceWidth = workspace == null
                            ? 0.0
                            : workspace.count * 44.0 + 8;
                        final batteryWidth = battery.capacity == null
                            ? 0.0
                            : 44.0;
                        final stripWidth =
                            (clockWidth +
                                    224 +
                                    workspaceWidth +
                                    batteryWidth +
                                    88)
                                .clamp(constraints.maxWidth, double.infinity);
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: stripWidth,
                            height: constraints.maxHeight,
                            child: Row(
                              children: [
                                if (workspace != null)
                                  SizedBox(
                                    width: workspaceWidth,
                                    child: _Workspaces(
                                      monitorId: monitorId,
                                      workspace: workspace,
                                    ),
                                  ),
                                Expanded(
                                  child: WindowButtons(
                                    monitorId: monitorId,
                                    centerX:
                                        stripWidth / 2 + 2 - workspaceWidth,
                                    launcher: const _StartButton(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TaskbarTray(monitorId: monitorId),
                                const TaskbarNetwork(),
                                TaskbarVolume(monitorId: monitorId),
                                if (battery.capacity case final capacity?)
                                  SizedBox(
                                    width: batteryWidth,
                                    child: _Battery(
                                      capacity: capacity,
                                      charging: battery.charging,
                                    ),
                                  ),
                                SizedBox(
                                  width: clockWidth,
                                  height: double.infinity,
                                  child: const _Clock(),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const Positioned(
                    top: 0,
                    bottom: 0,
                    right: 0,
                    width: 12,
                    child: _ShowDesktopButton(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Put the glass pane's side and bottom edges beyond this output, while its
/// visible paint and input stay within the taskbar's allocated monitor strip.
class _TaskbarBackdrop extends StatelessWidget {
  const _TaskbarBackdrop({required this.child});

  static const double _edgeBleed = 3;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth + _edgeBleed * 2;
      final height = constraints.maxHeight + _edgeBleed;
      return ClipRect(
        clipBehavior: Clip.hardEdge,
        child: OverflowBox(
          alignment: Alignment.topCenter,
          minWidth: width,
          maxWidth: width,
          minHeight: height,
          maxHeight: height,
          child: ShellBackdropBlur(
            opacity: ShellSurfacePresentation.opacityOf(context),
            blur: context.shellTheme.effectivePanelOpacity < 1,
            separateChild: true,
            child: Padding(
              // Keep controls, the top border and the 52px reservation in their
              // original positions; only the backdrop geometry extends outward.
              padding: const EdgeInsets.only(
                left: _edgeBleed,
                right: _edgeBleed,
                bottom: _edgeBleed,
              ),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

class _StartButton extends StatelessWidget {
  const _StartButton();
  @override
  Widget build(BuildContext context) => Semantics(
    label: MaterialLocalizations.of(context).openAppDrawerTooltip,
    child: IconButton(
      onPressed: ShellServicesScope.of(context).toggleLauncher,
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      icon: Icon(
        Icons.apps_rounded,
        color: taskbarForeground(context),
        size: 28,
      ),
    ),
  );
}

class _Workspaces extends StatelessWidget {
  const _Workspaces({required this.monitorId, required this.workspace});

  final int monitorId;
  final WorkspaceStatus workspace;

  @override
  Widget build(BuildContext context) {
    final services = ShellServicesScope.of(context);
    final strings = services.strings(context);
    final foreground = taskbarForeground(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var id = 1; id <= workspace.count; id++)
          SizedBox(
            width: 44,
            height: double.infinity,
            child: Builder(
              builder: (context) {
                final active = id == workspace.active;
                final occupied = workspace.occupied.contains(id);
                final label = [
                  strings.workspaceLabel(id),
                  if (active) strings.workspaceActive,
                  occupied ? strings.workspaceOccupied : strings.workspaceEmpty,
                ].join(', ');
                return Tooltip(
                  message: label,
                  excludeFromSemantics: true,
                  child: InkWell(
                    onTap: () => services.switchWorkspace(
                      monitorId: monitorId,
                      workspaceId: id,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    mouseCursor: services.linkCursor,
                    child: Semantics(
                      label: label,
                      selected: active,
                      button: true,
                      child: ExcludeSemantics(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: active
                                ? foreground.withValues(alpha: 0.14)
                                : null,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    strings.numberValue(id),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(color: foreground),
                                  ),
                                ),
                              ),
                              if (occupied)
                                Positioned(
                                  bottom: 4,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: foreground,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const SizedBox.square(dimension: 3),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _Battery extends StatelessWidget {
  const _Battery({required this.capacity, required this.charging});

  final int capacity;
  final bool charging;

  @override
  Widget build(BuildContext context) {
    final services = ShellServicesScope.of(context);
    final label = services
        .strings(context)
        .batteryLine(charging ? 'charging' : 'discharging', capacity);
    final icon = switch (taskbarBatteryBars(capacity)) {
      0 => Icons.battery_0_bar_rounded,
      1 => Icons.battery_1_bar_rounded,
      2 => Icons.battery_2_bar_rounded,
      3 => Icons.battery_3_bar_rounded,
      4 => Icons.battery_4_bar_rounded,
      5 => Icons.battery_5_bar_rounded,
      6 => Icons.battery_6_bar_rounded,
      _ => Icons.battery_full_rounded,
    };
    return IconButton(
      tooltip: label,
      onPressed: services.openPowerSettings,
      style: IconButton.styleFrom(
        padding: const EdgeInsets.all(4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: taskbarForeground(context), size: 24),
          if (charging)
            Icon(
              Icons.bolt_rounded,
              color: taskbarForeground(context),
              size: 12,
            ),
        ],
      ),
    );
  }
}

class _Clock extends ConsumerWidget {
  const _Clock();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ShellServicesScope.of(context);
    final now = ref.watch(services.clock).value ?? DateTime.now();
    final strings = services.strings(context);
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: strings.openDashboard,
      child: Tooltip(
        message: strings.openDashboard,
        child: InkWell(
          onTap: services.toggleDashboard,
          borderRadius: BorderRadius.circular(4),
          mouseCursor: services.linkCursor,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    strings.time(now),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: taskbarForeground(context),
                    ),
                  ),
                  Text(
                    strings.shortDate(now),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: taskbarForeground(context).withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-height edge target, with no icon or opaque backing.
class _ShowDesktopButton extends ConsumerWidget {
  const _ShowDesktopButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ShellServicesScope.of(context);
    final showing = ref.watch(services.desktopVisible);
    final foreground = taskbarForeground(context);
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    return Semantics(
      button: true,
      toggled: showing,
      label: chinese
          ? (showing ? '还原窗口' : '显示桌面')
          : (showing ? 'Restore windows' : 'Show desktop'),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: services.toggleDesktop,
          mouseCursor: services.linkCursor,
          hoverColor: foreground.withValues(alpha: 0.10),
          focusColor: foreground.withValues(alpha: 0.16),
          highlightColor: foreground.withValues(alpha: 0.14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: foreground.withValues(alpha: 0.18)),
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
