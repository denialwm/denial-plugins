import 'dart:async';
import 'dart:math' as math;

import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'window_groups.dart';
import 'taskbar_settings.dart';
import 'neutral_color.dart';
import 'preview_emphasis.dart';
import 'taskbar_actions.dart';

const _instanceUnderlineOffset = 4.0;
const _instanceHighlightOffset = 3.0;

String _keyFor(String id) => 'app:${normalizeApplicationId(id)}';

class WindowButtons extends ConsumerStatefulWidget {
  const WindowButtons({
    required this.monitorId,
    required this.centerX,
    required this.launcher,
    super.key,
  });
  final int monitorId;
  final double centerX;
  final Widget launcher;
  @override
  ConsumerState<WindowButtons> createState() => _WindowButtonsState();
}

class _WindowButtonsState extends ConsumerState<WindowButtons> {
  late final _groups = WindowGroups<ApplicationWindow>(
    idOf: (window) => window.id,
    appOf: (window) => _groupIdentity(window.appId),
  );
  final _order = TaskbarOrder();
  List<LaunchableApplication> _catalog = [];
  List<PinnedApplication> _pinnedApps = [];
  List<String> _keys = [];
  VoidCallback? _dismissVisible;
  bool _dragging = false;
  bool _saving = false;
  String? _error;

  LaunchableApplication? _applicationFor(String appId) {
    final id = normalizeApplicationId(appId);
    // Prefer exact desktop identities before executable/class aliases, which
    // can be shared by unrelated applications.
    for (final app in _catalog) {
      if (normalizeApplicationId(app.appId) == id) return app;
    }
    final matches = _catalog.where(
      (app) =>
          app.windowAppIds.any((alias) => normalizeApplicationId(alias) == id),
    );
    return matches.length == 1 ? matches.single : null;
  }

  String _groupIdentity(String appId) {
    final app = _applicationFor(appId);
    if (app != null) return app.id;
    for (final pin in _pinnedApps) {
      if (normalizeApplicationId(pin.appId) == normalizeApplicationId(appId)) {
        return pin.id;
      }
    }
    return appId;
  }

  void _show(VoidCallback dismiss) {
    _dismissVisible?.call();
    _dismissVisible = dismiss;
  }

  Future<void> _savePins(
    List<PinnedApplication> Function(List<PinnedApplication>) update,
  ) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(taskbarPreferencesProvider.notifier).updatePins(update);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = Localizations.localeOf(context).languageCode == 'zh'
              ? '无法保存任务栏更改。请重试。'
              : 'Could not save taskbar changes. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _reorder(int from, int to) {
    if (_saving) return;
    final prefs = ref.read(taskbarPreferencesProvider).value;
    setState(() => _keys = _order.reorder(from, to));
    if (prefs == null) return;
    final byKey = {for (final pin in prefs.pinned) _keyFor(pin.id): pin};
    final pins = [for (final key in _keys) ?byKey[key]];
    if (pins.map((p) => p.id).join('\n') !=
        prefs.pinned.map((p) => p.id).join('\n')) {
      final order = List<String>.of(_keys);
      unawaited(_savePins((current) => _sortPins(current, order)));
    }
  }

  List<PinnedApplication> _sortPins(
    List<PinnedApplication> pins,
    List<String> order,
  ) {
    int rank(PinnedApplication pin) {
      final index = order.indexOf(_keyFor(pin.id));
      return index < 0 ? order.length + pins.indexOf(pin) : index;
    }

    return List<PinnedApplication>.of(pins)
      ..sort((a, b) => rank(a).compareTo(rank(b)));
  }

  Future<void> _togglePin(
    LaunchableApplication? app,
    PinnedApplication? pin,
  ) async {
    if (!ref.read(taskbarPreferencesProvider).hasValue ||
        _saving ||
        (pin == null && app == null)) {
      return;
    }
    final order = List<String>.of(_keys);
    await _savePins((current) {
      final pins = List<PinnedApplication>.of(current);
      if (pin != null) {
        pins.removeWhere((p) => p.id == pin.id);
      } else if (app != null && !pins.any((p) => p.id == app.id)) {
        pins.add(
          PinnedApplication(id: app.id, appId: app.appId, name: app.name),
        );
      }
      return _sortPins(pins, order);
    });
  }

  @override
  Widget build(BuildContext context) {
    final services = ShellServicesScope.of(context);
    _catalog = ref.watch(services.applications);
    final desktopVisible = ref.watch(services.desktopVisible);
    final prefsState = ref.watch(taskbarPreferencesProvider);
    final prefs = prefsState.value ?? const TaskbarPreferences();
    _pinnedApps = prefs.pinned;
    final groups = _groups.update(
      ref.watch(services.windows(widget.monitorId)),
    );
    final pins = {for (final pin in prefs.pinned) _keyFor(pin.id): pin};
    _keys = _order.update(groups.keys, pins.keys);
    final bounds = ref.watch(services.monitorBounds(widget.monitorId));
    final error =
        _error ??
        (prefsState.hasError
            ? (Localizations.localeOf(context).languageCode == 'zh'
                  ? '无法读取任务栏配置。'
                  : 'Could not read taskbar preferences.')
            : null);
    final buttons = ReorderableListView.builder(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.zero,
      itemExtent: 52,
      itemCount: _keys.length,
      buildDefaultDragHandles: false,
      onReorderItem: _reorder,
      onReorderStart: (index) {
        _dismissVisible?.call();
        setState(() => _dragging = true);
      },
      onReorderEnd: (_) => setState(() => _dragging = false),
      proxyDecorator: (child, _, _) => ShellServicesScope(
        services: services,
        child: ShellTheme(
          data: context.shellTheme,
          child: IgnorePointer(child: ExcludeFocus(child: child)),
        ),
      ),
      itemBuilder: (context, index) {
        final key = _keys[index];
        final windows = groups[key] ?? const <ApplicationWindow>[];
        final pin = pins[key];
        final app = _catalog.where((app) => _keyFor(app.id) == key).firstOrNull;
        final appId = app?.appId ?? pin?.appId ?? windows.first.appId;
        return ReorderableDragStartListener(
          key: ValueKey(key),
          index: index,
          enabled: !_saving,
          child: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: _WindowButton(
              appId: appId,
              name: app?.name ?? pin?.name ?? windows.first.title,
              launchId: app?.id ?? pin?.id,
              monitorId: widget.monitorId,
              windows: windows,
              desktopVisible: desktopVisible,
              pinned: pin != null,
              dragging: _dragging,
              canPin:
                  prefsState.hasValue &&
                  !_saving &&
                  (app != null || pin != null),
              onTogglePin: () => _togglePin(app, pin),
              monitorBounds: bounds,
              show: _show,
            ),
          ),
        );
      },
    );
    // Keep both regions mounted. Switching a ShellInputRegion between
    // childBounds and fullScene changes its render wrapper and disposes the
    // reorder list during an active drag, losing the gesture and proxy.
    return Listener(
      onPointerUp: (_) => _endDrag(),
      onPointerCancel: (_) => _endDrag(),
      child: ShellInputRegion(
        debugLabel: 'Taskbar application reorder capture',
        active: _dragging,
        pointerPolicy: ShellPointerPolicy.fullScene,
        child: ShellInputRegion(
          debugLabel: 'Taskbar application buttons',
          child: LayoutBuilder(
            builder: (context, constraints) {
              const launcherWidth = 48.0;
              final errorWidth = error == null ? 0.0 : 24.0;
              final appWidth = _keys.length * 52.0;
              final contentWidth =
                  launcherWidth +
                  errorWidth +
                  (_keys.isEmpty ? 0 : 8 + appWidth);
              final width = math.min(contentWidth, constraints.maxWidth);
              final left = prefs.leftAligned
                  ? 0.0
                  : (widget.centerX - width / 2).clamp(
                      0.0,
                      constraints.maxWidth - width,
                    );
              return Padding(
                padding: EdgeInsets.only(left: left),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: width,
                    child: Row(
                      children: [
                        SizedBox(width: launcherWidth, child: widget.launcher),
                        if (error != null)
                          Tooltip(
                            message: error,
                            child: Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.error,
                              size: 24,
                            ),
                          ),
                        if (_keys.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Expanded(child: buttons),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // Flutter does not call onReorderEnd when an in-flight drag is cancelled,
  // for example because a window closes and changes the list length.
  void _endDrag() {
    if (_dragging) setState(() => _dragging = false);
  }
}

class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.appId,
    required this.name,
    required this.launchId,
    required this.monitorId,
    required this.windows,
    required this.desktopVisible,
    required this.pinned,
    required this.dragging,
    required this.canPin,
    required this.onTogglePin,
    required this.monitorBounds,
    required this.show,
  });
  final String appId;
  final String name;
  final String? launchId;
  final int monitorId;
  final List<ApplicationWindow> windows;
  final bool desktopVisible;
  final bool pinned;
  final bool dragging;
  final bool canPin;
  final Future<void> Function() onTogglePin;
  final Rect? monitorBounds;
  final void Function(VoidCallback) show;
  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton>
    with SingleTickerProviderStateMixin {
  final _portal = OverlayPortalController();
  final _focus = FocusNode(debugLabel: 'Taskbar application');
  late final AnimationController _animation;
  late final _emphasis = PreviewEmphasis(
    request: (id) {
      if (!mounted ||
          widget.dragging ||
          _menu ||
          !_portal.isShowing ||
          !widget.windows.any((window) => window.id == id)) {
        return () {};
      }
      return ShellServicesScope.of(context)
          .emphasizeWindow(id, monitorId: widget.monitorId);
    },
  );

  @override
  void initState() {
    super.initState();
    _animation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
          reverseDuration: const Duration(milliseconds: 120),
        )..addStatusListener((status) {
          if (status == AnimationStatus.dismissed && mounted && !_menu) {
            _portal.hide();
          }
        });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!ShellSurfacePresentation.visibleOf(context)) {
      _timer?.cancel();
      _emphasis.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !ShellSurfacePresentation.visibleOf(context)) {
          _hideImmediately();
        }
      });
    }
  }

  Timer? _timer;
  bool _menu = false;
  bool _launching = false;
  String? _launchError;

  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _openPreviews() {
    if (!mounted ||
        widget.dragging ||
        widget.windows.isEmpty ||
        _menu ||
        !ShellSurfacePresentation.visibleOf(context)) {
      return;
    }
    if (!_portal.isShowing) {
      widget.show(_hideImmediately);
      _portal.show();
    }
    if (_reduceMotion) {
      _animation.value = 1;
    } else {
      _animation.forward();
    }
  }

  void _enter() {
    _timer?.cancel();
    if (widget.dragging || _menu || widget.windows.isEmpty) return;
    if (_portal.isShowing) {
      _openPreviews();
      return;
    }
    _timer = Timer(const Duration(milliseconds: 200), _openPreviews);
  }

  void _leave() {
    _timer?.cancel();
    if (!_menu) _timer = Timer(const Duration(milliseconds: 180), _hide);
  }

  void _hide() {
    _emphasis.clear();
    _timer?.cancel();
    if (!mounted) return;
    if (_menu || _reduceMotion) {
      _hideImmediately();
    } else {
      _animation.reverse();
    }
  }

  void _hideImmediately() {
    _emphasis.clear();
    _timer?.cancel();
    if (!mounted) return;
    _portal.hide();
    _animation.value = 0;
    _menu = false;
  }

  void _openMenu() {
    if (widget.dragging || !ShellSurfacePresentation.visibleOf(context)) return;
    _emphasis.clear();
    widget.show(_hideImmediately);
    _timer?.cancel();
    _animation.value = 0;
    setState(() => _menu = true);
    _portal.show();
  }

  void _closeMenu() {
    _hideImmediately();
    if (_focus.context != null) _focus.requestFocus();
  }

  Future<void> _activate() async {
    if (widget.dragging || _launching) return;
    final services = ShellServicesScope.of(context);
    if (widget.windows.isEmpty) {
      final id = widget.launchId;
      if (id == null) return;
      _hideImmediately();
      setState(() {
        _launching = true;
        _launchError = null;
      });
      var started = false;
      try {
        started = await services.launchApplication(
          id,
          monitorId: widget.monitorId,
        );
      } catch (_) {
        /* Report through the menu. */
      }
      if (!mounted) return;
      setState(() {
        _launching = false;
        if (!started) {
          _launchError = Localizations.localeOf(context).languageCode == 'zh'
              ? '无法打开此应用。'
              : 'Could not open this application.';
        }
      });
      if (!started) _openMenu();
    } else if (widget.windows.length == 1 ||
        widget.windows.every((window) => window.tiled)) {
      _hideImmediately();
      _activateWindows(widget.windows);
    } else {
      _menu = false;
      _openPreviews();
    }
  }

  void _activateWindows(List<ApplicationWindow> windows) {
    final services = ShellServicesScope.of(context);
    if (shouldMinimizeTaskbarWindow(
      tiled: windows.every((window) => window.tiled),
      minimized: windows.every((window) => window.minimized),
      desktopVisible: widget.desktopVisible,
    )) {
      for (final window in windows) {
        if (!window.minimized) services.minimizeWindow(window.id);
      }
    } else {
      for (final window in windows) {
        services.activateWindow(window.id);
      }
    }
  }

  @override
  void didUpdateWidget(covariant _WindowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_emphasis.windowId != null &&
        !widget.windows.any((window) => window.id == _emphasis.windowId)) {
      _emphasis.clear();
    }
    if (widget.dragging || (!_menu && widget.windows.isEmpty)) {
      // OverlayPortal must not mutate the overlay during its parent's build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            (widget.dragging || (!_menu && widget.windows.isEmpty))) {
          _hideImmediately();
        }
      });
    }
  }

  @override
  void dispose() {
    _emphasis.dispose();
    _timer?.cancel();
    _animation.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ShellServicesScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final active = widget.windows.any((window) => window.active);
    final instanceLayers = math.min(2, widget.windows.length);
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _portal,
      overlayChildBuilder: (context, layout) =>
          _menu ? _buildMenu(context, layout) : _buildPreviews(context, layout),
      child: MouseRegion(
        onEnter: (_) => _enter(),
        onExit: (_) => _leave(),
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.contextMenu): _openMenu,
            const SingleActivator(LogicalKeyboardKey.f10, shift: true):
                _openMenu,
            const SingleActivator(LogicalKeyboardKey.escape): _hide,
          },
          child: Semantics(
            label: widget.name,
            value: '${widget.windows.length}',
            selected: active,
            button: true,
            child: SizedBox(
              width: 48,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: active
                          ? Stack(
                              clipBehavior: Clip.none,
                              children: [
                                for (
                                  var layer = instanceLayers - 1;
                                  layer >= 0;
                                  layer--
                                )
                                  Positioned.fill(
                                    left: layer * _instanceHighlightOffset,
                                    right: -layer * _instanceHighlightOffset,
                                    child: _ActiveWindowSurface(
                                      rear: layer > 0,
                                    ),
                                  ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      child: InkWell(
                        focusNode: _focus,
                        onFocusChange: (focused) =>
                            focused ? _enter() : _leave(),
                        onTap: _activate,
                        onSecondaryTap: _openMenu,
                        mouseCursor: services.linkCursor,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: ExcludeSemantics(
                            child: services.buildApplicationIcon(
                              context,
                              widget.appId,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.windows.isNotEmpty)
                    Positioned(
                      bottom: 0,
                      child: IgnorePointer(
                        child: AnimatedContainer(
                          duration: _reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 160),
                          width: active ? 22 : 6,
                          height: 6,
                          child: CustomPaint(
                            painter: _InstanceStackPainter(
                              count: instanceLayers,
                              color: active
                                  ? colors.primary
                                  : colors.onSurfaceVariant,
                            ),
                          ),
                        ),
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

  ({Rect anchor, Rect output}) _geometry(OverlayChildLayoutInfo layout) => (
    anchor: MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    ),
    output: (widget.monitorBounds ?? (Offset.zero & layout.overlaySize))
        .intersect(Offset.zero & layout.overlaySize),
  );

  Widget _buildMenu(BuildContext context, OverlayChildLayoutInfo layout) {
    final geometry = _geometry(layout);
    final width = math.min(244.0, math.max(0.0, geometry.output.width - 16));
    final maxHeight = math.max(
      0.0,
      geometry.anchor.top - geometry.output.top - 16,
    );
    if (width == 0 || maxHeight == 0) return const SizedBox.shrink();
    final left = (geometry.anchor.center.dx - width / 2).clamp(
      geometry.output.left + 8,
      geometry.output.right - width - 8,
    );
    final chinese = Localizations.localeOf(context).languageCode == 'zh';
    final colors = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(8));
    return ShellInputRegion(
      debugLabel: 'Taskbar application menu',
      pointerPolicy: ShellPointerPolicy.fullScene,
      keyboardPolicy: ShellKeyboardPolicy.capture,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _closeMenu,
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _closeMenu(),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              Positioned(
                left: left.toDouble(),
                bottom: layout.overlaySize.height - geometry.anchor.top + 8,
                width: width,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: ShellBackdropBlur(
                    blur: context.shellTheme.effectivePanelOpacity < 1,
                    separateChild: true,
                    borderRadius: radius,
                    child: Material(
                      color: context.shellTheme.panelColor(
                        colors.surfaceContainer,
                      ),
                      surfaceTintColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: colors.outlineVariant),
                        borderRadius: radius,
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(6),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                              child: Text(
                                widget.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: taskbarForeground(context),
                                    ),
                              ),
                            ),
                            TextButton.icon(
                              autofocus: true,
                              style: TextButton.styleFrom(
                                foregroundColor: taskbarForeground(context),
                                alignment: Alignment.centerLeft,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              onPressed: widget.canPin
                                  ? () {
                                      _closeMenu();
                                      unawaited(widget.onTogglePin());
                                    }
                                  : null,
                              icon: Icon(
                                widget.pinned
                                    ? Icons.push_pin
                                    : Icons.push_pin_outlined,
                                size: 18,
                              ),
                              label: Text(
                                chinese
                                    ? (widget.pinned ? '从任务栏取消固定' : '固定到任务栏')
                                    : (widget.pinned
                                          ? 'Unpin from taskbar'
                                          : 'Pin to taskbar'),
                              ),
                            ),
                            if (!widget.canPin && widget.launchId == null)
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  chinese ? '此窗口没有可用的启动项。' : 'No launcher entry is available for this window.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            if (_launchError != null)
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  _launchError!,
                                  style: TextStyle(color: colors.error),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviews(BuildContext context, OverlayChildLayoutInfo layout) {
    if (widget.windows.isEmpty || widget.dragging) {
      _emphasis.clear();
      return const SizedBox.shrink();
    }
    final geometry = _geometry(layout);
    final available = math.max(0.0, geometry.output.width - 16);
    final maxHeight = math.min(
      216.0,
      math.max(0.0, geometry.anchor.top - geometry.output.top - 16),
    );
    if (available == 0 || maxHeight == 0) {
      _emphasis.clear();
      return const SizedBox.shrink();
    }
    final sizes = [
      for (final window in widget.windows)
        _previewSize(window.previewSize, math.min(320.0, available), maxHeight),
    ];
    final height = sizes.map((size) => size.height).reduce(math.max);
    final width = math.min(
      available,
      sizes.fold(0.0, (sum, size) => sum + size.width) + (sizes.length - 1) * 8,
    );
    final left = (geometry.anchor.center.dx - width / 2).clamp(
      geometry.output.left + 8,
      math.max(geometry.output.left + 8, geometry.output.right - 8 - width),
    );
    return Stack(
      children: [
        Positioned(
          left: left.toDouble(),
          top: geometry.anchor.top - height - 8,
          width: width,
          height: height + 8,
          child: ShellInputRegion(
            debugLabel: 'Taskbar window previews',
            child: MouseRegion(
              onEnter: (_) => _enter(),
              onExit: (_) => _leave(),
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): _hide,
                },
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    final value = Curves.easeOutCubic.transform(
                      _animation.value,
                    );
                    return Transform.translate(
                      offset: Offset(0, 8 * (1 - value)),
                      child: Transform.scale(
                        scale: 0.97 + 0.03 * value,
                        alignment: Alignment.bottomCenter,
                        child: Opacity(opacity: value, child: child),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final (i, window) in widget.windows.indexed) ...[
                            if (i > 0) const SizedBox(width: 8),
                            SizedBox(
                              key: ValueKey(window.id),
                              width: sizes[i].width,
                              height: sizes[i].height,
                              child: MouseRegion(
                                onEnter: (_) => _emphasis.enter(window.id),
                                onExit: (_) => _emphasis.leave(window.id),
                                child: _Preview(
                                  window: window,
                                  onTap: () {
                                    _hideImmediately();
                                    _activateWindows([window]);
                                  },
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.window, required this.onTap});
  final ApplicationWindow window;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final services = ShellServicesScope.of(context);
    return Semantics(
      label: window.title,
      button: true,
      selected: window.active,
      child: Material(
        color: const Color(0xff202020),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            services.buildWindowPreview(context, window.id),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black87],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 22, 10, 8),
                  child: Text(
                    window.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
            Material(
              type: MaterialType.transparency,
              child: InkWell(onTap: onTap, mouseCursor: services.linkCursor),
            ),
          ],
        ),
      ),
    );
  }
}

// Fit each card inside the preview budget without letterboxing its content.
Size _previewSize(Size source, double maxWidth, double maxHeight) {
  final ratio = !source.isEmpty && source.isFinite ? source.aspectRatio : 1.5;
  final height = math.min(maxHeight, maxWidth / ratio);
  return Size(height * ratio, height);
}

/// A small glass selection lens; the foreground icon is painted separately so
/// it stays sharp. Opaque panel settings retain a solid selection fallback.
class _ActiveWindowSurface extends StatelessWidget {
  const _ActiveWindowSurface({this.rear = false});
  final bool rear;

  @override
  Widget build(BuildContext context) {
    final shell = context.shellTheme;
    final colors = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(4));
    final translucent = shell.effectivePanelOpacity < 1;
    Color tint(Color color) => rear
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.14), color)
        : color;
    return ShellBackdropBlur(
      blur: translucent,
      strength: 0.55,
      separateChild: true,
      borderRadius: radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: translucent ? null : tint(colors.secondaryContainer),
          gradient: translucent
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tint(
                      Color.alphaBlend(
                        Colors.white.withValues(alpha: 0.12),
                        shell.accent.withValues(alpha: 0.12),
                      ),
                    ),
                    tint(shell.accent.withValues(alpha: 0.08)),
                  ],
                )
              : null,
          border: Border.all(
            color: shell.accent.withValues(alpha: translucent ? 0.35 : 0.25),
            width: 1,
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// The front underline stays centered; at most one rear copy peeks out to the
/// right, extending slightly farther than the rear glass highlight.
class _InstanceStackPainter extends CustomPainter {
  const _InstanceStackPainter({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    for (var i = count - 1; i >= 0; i--) {
      final rect = Rect.fromLTWH(i * _instanceUnderlineOffset, 0, width, 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(1.5)),
        Paint()..color = color.withValues(alpha: color.a * (i == 0 ? 1 : 0.65)),
      );
    }
  }

  @override
  bool shouldRepaint(_InstanceStackPainter oldDelegate) =>
      count != oldDelegate.count || color != oldDelegate.color;
}
