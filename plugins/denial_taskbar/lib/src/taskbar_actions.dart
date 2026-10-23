/// Shared click policy for app buttons and grouped-window previews.
bool shouldMinimizeTaskbarWindow({
  required bool tiled,
  required bool minimized,
  bool desktopVisible = false,
}) => tiled && !minimized && !desktopVisible;

/// Maps charge levels to the Material battery icon steps.
int taskbarBatteryBars(int capacity) => switch (capacity.clamp(0, 100)) {
  < 15 => 0,
  < 30 => 1,
  < 45 => 2,
  < 60 => 3,
  < 75 => 4,
  < 90 => 5,
  < 100 => 6,
  _ => 7,
};
