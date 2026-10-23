import 'dart:math' as math;

import 'package:denial_flutter_sdk/controls.dart';
import 'package:denial_flutter_sdk/effects.dart';
import 'package:denial_flutter_sdk/input.dart';
import 'package:denial_flutter_sdk/services.dart';
import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_flutter_sdk/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'neutral_color.dart';

String _percent(ShellStrings strings, double value) =>
    '${strings.numberValue((value * 100).round())}${strings.percentSign}';

class TaskbarNetwork extends ConsumerWidget {
  const TaskbarNetwork({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ShellServicesScope.of(context);
    final network = ref.watch(services.connectedWifi);
    final strings = services.strings(context);
    final label = [
      strings.wifiTitle,
      network?.ssid ?? strings.notConnected,
      if (network != null) _percent(strings, network.strength / 100),
    ].join(', ');
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        image: true,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: WifiStatusIcon(
              active: network != null,
              strength: network?.strength ?? 0,
              color: taskbarForeground(context),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }
}

class TaskbarVolume extends ConsumerStatefulWidget {
  const TaskbarVolume({required this.monitorId, super.key});

  final int monitorId;

  @override
  ConsumerState<TaskbarVolume> createState() => _TaskbarVolumeState();
}

class _TaskbarVolumeState extends ConsumerState<TaskbarVolume> {
  final _portal = OverlayPortalController();
  final _buttonFocus = FocusNode(debugLabel: 'Taskbar volume');
  ShellAudioServices? _audio;
  double? _pendingVolume;

  void _finishInteraction() {
    if (_pendingVolume case final value?) {
      _pendingVolume = null;
      _audio?.commitVolume(value);
    }
  }

  void _close() {
    if (!_portal.isShowing) return;
    _finishInteraction();
    setState(_portal.hide);
    if (_buttonFocus.context != null) _buttonFocus.requestFocus();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!ShellSurfacePresentation.visibleOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !ShellSurfacePresentation.visibleOf(context)) _close();
      });
    }
  }

  @override
  void dispose() {
    _finishInteraction();
    _buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = ShellServicesScope.of(context);
    _audio = services;
    final volume = ref.watch(services.volume);
    final bounds = ref.watch(services.monitorBounds(widget.monitorId));
    final strings = services.strings(context);
    final label = '${strings.volumeTitle}, ${_percent(strings, volume)}';
    return SizedBox(
      width: 44,
      height: 44,
      child: OverlayPortal.overlayChildLayoutBuilder(
        controller: _portal,
        overlayChildBuilder: (context, layout) =>
            _buildFlyout(context, layout, bounds, volume),
        child: Semantics(
          expanded: _portal.isShowing,
          child: IconButton(
            focusNode: _buttonFocus,
            tooltip: label,
            onPressed: () {
              if (_portal.isShowing) {
                _close();
              } else {
                setState(_portal.show);
              }
            },
            style: IconButton.styleFrom(
              minimumSize: const Size.square(44),
              shape: RoundedRectangleBorder(
                borderRadius: context.shellTheme.borderRadius(4),
              ),
            ),
            icon: Icon(
              volume <= .01
                  ? Icons.volume_off_rounded
                  : volume < .5
                  ? Icons.volume_down_rounded
                  : Icons.volume_up_rounded,
              color: taskbarForeground(context),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFlyout(
    BuildContext context,
    OverlayChildLayoutInfo layout,
    Rect? monitorBounds,
    double volume,
  ) {
    final anchor = MatrixUtils.transformRect(
      layout.childPaintTransform,
      Offset.zero & layout.childSize,
    );
    final output = (monitorBounds ?? (Offset.zero & layout.overlaySize))
        .intersect(Offset.zero & layout.overlaySize);
    final width = math.min(88.0, math.max(0.0, output.width - 16));
    final height = math.min(276.0, math.max(0.0, anchor.top - output.top - 16));
    if (width < 64 || height < 120) return const SizedBox.shrink();
    final left = (anchor.center.dx - width / 2).clamp(
      output.left + 8,
      output.right - 8 - width,
    );
    final services = ShellServicesScope.of(context);
    final strings = services.strings(context);
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(context.shellTheme.panelRadius);
    void adjust(double value) => services.commitVolume(value.clamp(0.0, 1.0));
    return ShellInputRegion(
      debugLabel: 'Taskbar volume flyout',
      pointerPolicy: ShellPointerPolicy.fullScene,
      keyboardPolicy: ShellKeyboardPolicy.capture,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _close,
          const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
              adjust(volume + .05),
          const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
              adjust(volume + .05),
          const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
              adjust(volume - .05),
          const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
              adjust(volume - .05),
          const SingleActivator(LogicalKeyboardKey.home): () => adjust(0),
          const SingleActivator(LogicalKeyboardKey.end): () => adjust(1),
        },
        child: Focus(
          autofocus: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => _close(),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
              Positioned(
                left: left,
                top: anchor.top - height - 8,
                width: width,
                height: height,
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
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _percent(strings, volume),
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(color: taskbarForeground(context)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: SizedBox(
                              width: 48,
                              child: Semantics(
                                slider: true,
                                label: strings.volumeTitle,
                                value: _percent(strings, volume),
                                onIncrease: () => adjust(volume + .05),
                                onDecrease: () => adjust(volume - .05),
                                child: RotatedBox(
                                  quarterTurns: 3,
                                  child: RangeBar(
                                    value: volume,
                                    activeColor: context.shellTheme.accent,
                                    inactiveColor:
                                        context.shellColors.volumeTrack,
                                    height: 48,
                                    onChangeStart: () {
                                      _pendingVolume = volume;
                                      services.beginVolumeInteraction();
                                    },
                                    onChanged: (value) {
                                      _pendingVolume = value;
                                      services.setVolume(value);
                                    },
                                    onChangeEnd: (value) {
                                      _pendingVolume = null;
                                      services.commitVolume(value);
                                    },
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
            ],
          ),
        ),
      ),
    );
  }
}
