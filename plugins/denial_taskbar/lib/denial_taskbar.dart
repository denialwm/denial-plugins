@Plugin()
library;

import 'package:denial_flutter_sdk/surfaces.dart';
import 'package:denial_sdk/composition.dart';
import 'package:flutter/widgets.dart';

import 'src/taskbar.dart';

@Provides(ShellSurface)
final class TaskbarPlugin implements ShellSurface {
  const TaskbarPlugin();
  static const thickness = 52.0;
  @override
  String get id => 'denial_taskbar.panel';
  @override
  ShellSurfaceLayer get layer => ShellSurfaceLayer.desktopControls;
  @override
  ShellSurfacePlacement? place(ShellSurfaceEnvironment environment) {
    final layout = environment.settings.layout;
    if (layout.systemBarSide == PanelEdge.hidden ||
        !environment.outputSelected(layout.systemBarOutputNames)) {
      return null;
    }
    return ShellSurfacePlacement(
      fade: ShellSurfaceFade.custom,
      bounds: ShellSurfacePlacement.edgeBounds(
        environment.output.logicalRect,
        PanelEdge.bottom,
        thickness,
      ),
      visible:
          !environment.locked &&
          !environment.wallpaperSelectorVisible &&
          (!environment.fullscreen ||
              environment.overview ||
              environment.desktopVisible),
    );
  }

  // The desktop rebuilds its surfaces whenever any environment field changes,
  // such as an overview toggle. The taskbar depends only on its output and
  // services, so an unchanged pair returns the same widget and Flutter skips
  // the whole taskbar subtree.
  static final _taskbars = <int, WindowsTaskbar>{};

  @override
  Widget build(BuildContext context, {required ShellSurfaceContext surface}) {
    final monitorId = surface.environment.output.monitorId;
    final taskbar = _taskbars[monitorId];
    if (taskbar != null && identical(taskbar.services, surface.services)) {
      return taskbar;
    }
    return _taskbars[monitorId] = WindowsTaskbar(
      monitorId: monitorId,
      services: surface.services,
    );
  }
}

@Provides(ShellWorkArea)
final class TaskbarWorkArea implements ShellWorkArea {
  const TaskbarWorkArea();
  @override
  ShellWorkAreaReservation? reserve(ShellLayoutSettings settings) =>
      settings.systemBarSide == PanelEdge.hidden
      ? null
      : ShellWorkAreaReservation(
          edge: PanelEdge.bottom,
          thickness: TaskbarPlugin.thickness + settings.maximizePadding,
          outputNames: settings.systemBarOutputNames,
        );
}
