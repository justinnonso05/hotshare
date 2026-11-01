# HotShare icon pack

Generated from `Glossy_Gradient_Document_Send_Icon.png`. The folders mirror a Flutter project, so you copy them into your project root and accept the merge. Open `preview.png` to see every variant.

## What is inside

| Folder | Contents |
|---|---|
| `android/app/src/main/res/` | Adaptive icon (background, foreground, monochrome layers for Android 13 themed icons), legacy square and round launcher PNGs for all five densities, status bar notification icon `ic_stat_hotshare` |
| `android/play_store_icon_512.png` | Google Play listing icon (square, no rounded corners, the store masks it) |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/` | Every iPhone and iPad size plus `Contents.json`, opaque PNGs as App Store requires |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/` | 16 to 1024 px in the macOS style (inset artwork with soft shadow) plus `Contents.json` |
| `windows/runner/resources/app_icon.ico` | 10 sizes from 16 to 256 px. Sizes up to 32 px use a tuned version with a larger glyph and a wider gap so the arrow stays readable |
| `assets/tray/` | System tray icons as `.ico` and `.png`: `tray_idle` (grey), `tray_connected`, and `tray_transfer_1` to `4` (pulse frames) |
| `assets/icon/` | Masters for in-app use: `icon_rounded_1024.png`, `icon_fullbleed_1024.png`, `icon_rounded_512.png` (Linux window icon), `glyph_1024.png` (document and arrow only, transparent, for splash and about screens) |

## Apply it

1. Unzip and copy `android/`, `ios/`, `macos/`, `windows/` and `assets/` into your Flutter project root. Overwrite when asked.
2. Add the assets to `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/icon/
    - assets/tray/
```

3. Run `flutter clean`, then `flutter pub get`, then build as usual.

The files replace the Flutter defaults in place, same names and folders.

## Android

- The manifest should already have `android:icon="@mipmap/ic_launcher"`. Optionally add `android:roundIcon="@mipmap/ic_launcher_round"`.
- `mipmap-anydpi-v26/ic_launcher.xml` wires the three layers. Devices on Android 8 and up get the adaptive icon (the launcher applies its own mask), older devices fall back to the PNGs.
- Themed icons (Android 13+) only show when the user turns on "Themed icons" in wallpaper and style settings. The monochrome layer is what the system tints.
- Notification icon: reference the drawable by name, without extension. With `flutter_local_notifications` that is `AndroidInitializationSettings('ic_stat_hotshare')`, and set the notification `color` to your accent so the small icon is tinted. For a foreground service notification (`flutter_foreground_task`), point the icon option at the `ic_stat_hotshare` drawable, the exact field name depends on the package version.

## Windows

- `app_icon.ico` is used by the exe, the taskbar and the title bar. If Explorer still shows the old icon after a rebuild, it is the icon cache: run `ie4uinit.exe -show` or restart Explorer.
- The Explorer context menu entry can reuse the same icon: set the `Icon` registry value to the path of your exe.
- Tray, with `tray_manager`:

```dart
await trayManager.setIcon('assets/tray/tray_connected.ico'); // or tray_idle.ico

// pulse while transferring
Timer? _pulse; int _i = 0;
void startPulse() {
  _pulse?.cancel();
  _pulse = Timer.periodic(const Duration(milliseconds: 220), (_) {
    trayManager.setIcon('assets/tray/tray_transfer_${_i++ % 4 + 1}.ico');
  });
}
void stopPulse(String state) { // 'idle' or 'connected'
  _pulse?.cancel();
  trayManager.setIcon('assets/tray/tray_$state.ico');
}
```

On macOS and Linux use the `.png` versions of the same files.

## iOS and macOS

- iOS icons have no alpha channel and no rounded corners on purpose, iOS masks them.
- macOS icons are inset with a shadow, as Big Sur and later expect. After replacing, run `flutter clean`. The Dock caches icons, so restart the Dock if you see the old one.

## Linux

Use `assets/icon/icon_rounded_512.png` as the window icon and in your `.desktop` entry.

## Notes

- The source image is about 850 px wide, so the 1024 px files are a slight upscale. Edges are rebuilt crisp from a separated glyph layer, so they hold up, but if you ever want a true vector master, redraw the document and arrow as SVG and regenerate from that.
- Corners of the full-bleed versions are extended from the original gradient, so platform masks never reveal black.
- Brand colours the artwork uses: dark `#200000`, red `#E5231B`, orange `#FF7A1A`.
