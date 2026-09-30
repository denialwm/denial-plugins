import 'dart:math' as math;

import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'neutral_color.dart';

/// First three tray icons stay in the panel. Overflow retains native menus.
class TaskbarTray extends ConsumerStatefulWidget {
  const TaskbarTray({required this.monitorId, super.key});
  final int monitorId;
  @override
  ConsumerState<TaskbarTray> createState() => _TaskbarTrayState();
}

class _TaskbarTrayState extends ConsumerState<TaskbarTray> {
  // Temporary: expose the overflow popup for visual validation.
  static const _inlineCount = 0;
  final _portal = OverlayPortalController();
  final _buttonFocus = FocusNode(debugLabel: 'Tray overflow toggle');
  final _orderedIds = <String>[];

  void _close() {
    if (!_portal.isShowing) return;
    setState(_portal.hide);
    if (_buttonFocus.context != null) _buttonFocus.requestFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!ShellSurfacePresentation.visibleOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !ShellSurfacePresentation.visibleOf(context) &&
            _portal.isShowing) {
          setState(_portal.hide);
        }
      });
    }
  }

  @override
  void dispose() {
    _buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ShellServicesScope.of(context);
    final ids = ref.watch(services.trayItemIds);
    final bounds = ref.watch(services.monitorBounds(widget.monitorId));
    // Status/attention changes must not shuffle icons between bar and popup.
    final live = ids.toSet();
    _orderedIds.removeWhere((id) => !live.contains(id));
    for (final id in ids) {
      if (!_orderedIds.contains(id)) _orderedIds.add(id);
    }
    final overflow = _orderedIds.skip(_inlineCount).toList(growable: false);
    ref.listen(services.trayItemIds, (_, next) {
      if (next.length <= _inlineCount && _portal.isShowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              ref.read(services.trayItemIds).length <= _inlineCount) {
            _close();
          }
        });
      }
    });
    if (_orderedIds.isEmpty) return const SizedBox.shrink();
    final label = _portal.isShowing
        ? MaterialLocalizations.of(context).closeButtonTooltip
        : MaterialLocalizations.of(context).moreButtonTooltip;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        services.buildSystemTray(
          context,
          horizontal: true,
          itemIds: _orderedIds.take(_inlineCount).toList(growable: false),
          foregroundColor: taskbarForeground(context),
        ),
        if (overflow.isNotEmpty) ...[
          const SizedBox(width: 4),
          OverlayPortal.overlayChildLayoutBuilder(
            controller: _portal,
            overlayChildBuilder: (context, layout) =>
                _buildFlyout(context, layout, bounds, overflow),
            child: Semantics(
              label: label,
              expanded: _portal.isShowing,
              child: IconButton(
                focusNode: _buttonFocus,
                onPressed: () => setState(_portal.toggle),
                icon: Icon(
                  _portal.isShowing
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_up,
                  color: taskbarForeground(context),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFlyout(
    BuildContext context,
    OverlayChildLayoutInfo layout,
    Rect? monitorBounds,
    List<String> overflow,
  ) {
    final anchor = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    );
    final output = (monitorBounds ?? (Offset.zero & layout.overlaySize))
        .intersect(Offset.zero & layout.overlaySize);
    final maxWidth = math.min(144.0, math.max(0.0, output.width - 16));
    final maxHeight = math.min(
      240.0,
      math.max(0.0, anchor.top - output.top - 16),
    );
    if (maxWidth == 0 || maxHeight == 0) return const SizedBox.shrink();
    final rightEdge = anchor.right.clamp(
      output.left + 8 + maxWidth,
      output.right - 8,
    );
    final services = ShellServicesScope.of(context);
    final colors = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(8));
    return ShellInputRegion(
      debugLabel: 'Taskbar tray flyout',
      pointerPolicy: ShellPointerPolicy.fullScene,
      keyboardPolicy: ShellKeyboardPolicy.capture,
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        child: Actions(
          actions: {
            DismissIntent: CallbackAction<DismissIntent>(
              onInvoke: (_) {
                _close();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                Positioned.fill(
                  // Dismiss on the press itself, before competing desktop
                  // gestures or a client can change the release route. This
                  // also handles secondary/middle clicks and touch presses.
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => _close(),
                    child: const ColoredBox(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  right: layout.overlaySize.width - rightEdge,
                  bottom: layout.overlaySize.height - anchor.top + 8,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: maxWidth,
                      maxHeight: maxHeight,
                    ),
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
                          child: services.buildSystemTray(
                            context,
                            horizontal: true,
                            wrap: true,
                            itemIds: overflow,
                            foregroundColor: taskbarForeground(context),
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
      ),
    );
  }
}
