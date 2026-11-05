# Best practices: screen edges, safe areas, colour modes and adaptive layout (Flutter on Apple devices)

Research date: 2026-11-04. Web research only. Every URL below was fetched during this research.
Apple's HIG and docs pages are JavaScript-rendered; the text was read from Apple's own JSON endpoint for the same page
(`developer.apple.com/tutorials/data/...`). The links given are the normal pages.
Items marked **(unverified)** are from experience or secondary sources, not from a primary page, and need a device check.

## 1. Apple HIG Layout: safe areas, margins, the home indicator

- A safe area is the part of a window "not covered on the edge by a hardware feature or another view ... like a toolbar, tab bar, or status bar". Apple: "Respecting the safe area is essential to make sure system UI and hardware features like the Dynamic Island don't obstruct content and controls."
- Backgrounds go edge to edge, controls and text stay inside. HIG: "For full-screen background content, be sure to extend it underneath sidebars, toolbars, and tab bars to fit the entire screen or window." Artwork should be scaled to fill the screen, and its aspect ratio kept (cropping, letterboxing and pillarboxing are all to be avoided).
- Do not paint a solid or semi-opaque strip under floating controls. HIG: "Instead of applying a solid or semi-opaque background color beneath controls, use a scroll edge effect."
- Home indicator: the current HIG Layout page has no rule about placing content in the home-indicator band. The only home-indicator text I found is in Going full screen: by default the indicator "automatically hides shortly after someone switches to your app ... It reappears when someone interacts with the bottom portion of the screen, allowing them to swipe once to exit. Whenever possible, retain this behavior." So the bottom edge is a system-gesture zone. Keep interactive controls out of it (they would fight the swipe-home gesture); non-interactive status content in it is not prohibited anywhere I could find.
- Developer hooks: `prefersHomeIndicatorAutoHidden` only lets the system hide the indicator, "returning true is no guarantee". `preferredScreenEdgesDeferringSystemGestures` is for immersive apps; Apple: "Whenever possible, you should allow the system gestures to take precedence." A status/list app should use neither.
- `safeAreaInsets` for the root view "account for the status bar, other visible bars". Safe-area values for a child view are 0 when it already sits inside the parent's safe area.
- Adaptability: layout must follow "size classes, not device type or orientation". Include "Different device screen sizes ... System features like the Dynamic Island ... Display Zoom, and resizable windows on iPad ... Text-size changes".

Sources:
- https://developer.apple.com/design/human-interface-guidelines/layout
- https://developer.apple.com/design/human-interface-guidelines/going-full-screen
- https://developer.apple.com/documentation/uikit/uiviewcontroller/prefershomeindicatorautohidden
- https://developer.apple.com/documentation/uikit/uiviewcontroller/preferredscreenedgesdeferringsystemgestures
- https://developer.apple.com/documentation/uikit/positioning-content-relative-to-the-safe-area
- https://developer.apple.com/documentation/uikit/uiview/safeareainsets

## 2. Dynamic Island, notch and Live Activities

- Safe areas already keep content clear of the notch and Dynamic Island, so do not add custom avoidance. HIG Live Activities: "Don't add elements to your app that draw attention to the Dynamic Island."
- The status bar is transparent by default: "If controls are visible behind the status bar, people may attempt to interact with them and be unable to do so." Obscure content under it (blur or a scroll edge effect) and "avoid permanently hiding the status bar".
- Live Activities are the sanctioned way to show status in the Dynamic Island, on the Lock Screen, in StandBy and on a paired Watch. They fit "tasks and events that have a defined beginning and end ... that don't exceed eight hours". They are not for ads, and sensitive data should be redacted (they are visible to onlookers).
- What ActivityKit needs: a widget extension (SwiftUI) with an `ActivityConfiguration`; `NSSupportsLiveActivities = YES` in Info.plist; an `ActivityAttributes` type with a `ContentState`; support for all presentations (compact, minimal, expanded, Lock Screen); static plus dynamic data at most 4 KB combined; updates from the app or by ActivityKit push notifications (the activity can't use the network itself); iOS 16.1 or later; active for up to 8 hours, then up to 4 more hours on the Lock Screen.
- Consequence for Flutter: the UI of a Live Activity is native SwiftUI in a separate extension target. Flutter code cannot draw it; it can only start and update it through a plugin or platform channel. An "agent running" Live Activity is a separate feature, not the way to fill the home-indicator band.

Sources:
- https://developer.apple.com/design/human-interface-guidelines/live-activities
- https://developer.apple.com/design/human-interface-guidelines/status-bars
- https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- https://developer.apple.com/documentation/activitykit

## 3. iPad multitasking and windows in iPadOS 26 (exact versions)

- iPadOS 26.0 (Sept 2025): a new optional windowing system replaced Split View and Slide Over. Windows are freely resizable, with macOS-like "traffic light" controls; Stage Manager runs on the same architecture and works on all iPads that support iPadOS 26.
- iPadOS 26.1: Slide Over came back in a reworked form (single window, fixed vertical positions at either side). iPadOS 26.2 (12 Dec 2025): drag-to-tile gestures, which restore Split View-like half-screen tiling. These version facts come from Wikipedia, MacRumors and 9to5Mac, not from an Apple page; check against the final Apple release notes if exact wording matters.
- Apple HIG (Windows, iPadOS): the user picks "Full screen" or "Windowed" in Multitasking & Gestures settings. "Apps don't control multitasking configurations or receive any indication of the ones that people choose" (HIG Multitasking). When windowed, window controls sit at the leading edge of the toolbar, so leading toolbar buttons must move inward.
- `UIRequiresFullScreen` is deprecated since iOS/iPadOS 26.0. TN3192: it "will be ignored in a future release" and apps that keep it may get "broken layouts". Starting in iOS 27 and iPadOS 27, when built with the iOS 27 SDK, it no longer opts out of resizing; the scene is resized discretely instead. From iOS 27 SDK on, a launch screen is required for App Store submission. The note says to support resizing on both iPhone and iPad.
- To be exact: supporting all size classes, no `UIRequiresFullScreen`, a launch screen, and `UISceneSizeRestrictions` for a sensible minimum size. WWDC25 session 282 also says apps built with the iOS 26 SDK are no longer letterboxed on new screen sizes.
- Flutter note: `SystemChrome.setPreferredOrientations` is only honoured on iPad if multitasking is disabled, i.e. "Requires full screen" (Flutter source doc). That route is deprecated by Apple, so do not rely on it.
- Flutter's `MediaQuery.padding` does not account for the iPadOS 26 window controls (the pub.dev package `ios_window_control_layout` exists because of this and reads UIKit's corner-adapted layout margins). Test in a windowed iPad and add a small top-leading inset if the controls overlap.

Sources:
- https://developer.apple.com/documentation/technotes/tn3192-migrating-your-app-from-the-deprecated-uirequiresfullscreen-key
- https://developer.apple.com/documentation/bundleresources/information-property-list/uirequiresfullscreen
- https://developer.apple.com/videos/play/wwdc2025/282/ (Make your UIKit app more flexible)
- https://developer.apple.com/design/human-interface-guidelines/windows and https://developer.apple.com/design/human-interface-guidelines/multitasking
- https://en.wikipedia.org/wiki/IPadOS_26
- https://www.macrumors.com/2025/12/12/apple-releases-ipados-26-2/ (found by search, headline and summary only)
- https://9to5mac.com/2025/06/09/psa-ipados-26-removes-split-view-and-slide-over-multitasking-features/
- https://pub.dev/packages/ios_window_control_layout
- https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/services/system_chrome.dart

## 4. Dark Mode

- Support both. HIG: "Ensure that your app looks good in both appearance modes", including Auto, which can switch "while your app is running". Dark-only is for "rare cases", such as immersive media viewing. A dark-only app has to justify that exception; a status/dashboard app is not an obvious fit.
- Avoid an app-specific appearance setting; follow the system. An in-app override adds work for people and "they may think your app is broken".
- Use semantic or adaptive colours, not hard-coded values. Contrast: at least 4.5:1, aim for 7:1 for small text. Test Dark Mode with Increase Contrast and Reduce Transparency on.
- iOS uses base and elevated dark backgrounds to show depth (sheets and popovers get the elevated colour). Custom backgrounds make those distinctions harder to see.
- Launch screen: "nearly identical to the first screen"; it "matches the device's current orientation and appearance mode", to avoid "an unpleasant flash". Avoid text on it. Flutter's iOS template uses `LaunchScreen.storyboard` plus a `LaunchImage` set; give the storyboard background a named colour with Any and Dark variants.
- White flashes also come from the FlutterView's own background before the first frame and from `ThemeMode` mismatching the OS. Set the colour of the window or storyboard to the dark surface colour in dark mode.
- Status bar: choose icon colour from the actual background colour. Hiding it permanently is discouraged (HIG Status bars).

Sources:
- https://developer.apple.com/design/human-interface-guidelines/dark-mode
- https://developer.apple.com/design/human-interface-guidelines/launching
- https://docs.flutter.dev/platform-integration/ios/launch-screen
- https://developer.apple.com/design/human-interface-guidelines/status-bars

## 5. iOS 26 Liquid Glass: scroll edges, concentric corners, floating bars

- "The shape of the hardware informs the curvature of controls" and nested elements. Concentric means the inner radius is the outer radius minus the padding. WWDC25 356: "concentric shapes calculate their radius by subtracting padding from the parent's." Near device edges on phone layouts: "use a capsule with extra margin"; on iPad and Mac: "a concentric shape that aligns with the window edge".
- Public API (iOS 26): SwiftUI `ConcentricRectangle`, "to match a device's curved edges". Notes' format sheet has bottom corners concentric to the device corners. There is no Flutter equivalent; Flutter would need a platform plugin or a fixed fallback radius.
- Tab bars float above content at the bottom of the screen on iOS, resting on Liquid Glass so content peeks through. Content scrolls under bars; Apple wants controls kept visually distinct and "Reduce your use of custom backgrounds in controls and navigation elements".
- Scroll edge effects replace hard dividers with a soft blur where scrolling content meets floating UI. "Scroll edge effects aren't decorative. They don't block or darken like overlays" and should be used only "when a scroll view is behind floating interface elements", one per view. Soft is the default on iOS and iPadOS; hard is mostly macOS.
- Full-screen backgrounds extend under bars (HIG Layout), but a solid status strip pinned to the bottom edge is the opposite of the Liquid Glass direction: Apple floats controls over content and lets it show through.

Sources:
- https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
- https://developer.apple.com/design/human-interface-guidelines/scroll-views
- https://developer.apple.com/design/human-interface-guidelines/tab-bars and https://developer.apple.com/design/human-interface-guidelines/toolbars
- https://developer.apple.com/documentation/swiftui/concentricrectangle
- WWDC25 219 Meet Liquid Glass: https://developer.apple.com/videos/play/wwdc2025/219/
- WWDC25 356 Get to know the new design system: https://developer.apple.com/videos/play/wwdc2025/356/
- WWDC25 284 Build a UIKit app with the new design: https://developer.apple.com/videos/play/wwdc2025/284/
- (SwiftUI counterpart, not read in full) https://developer.apple.com/videos/play/wwdc2025/323/

## 6. Flutter specifics

**MediaQuery values** (Flutter source docs):
- `padding`: parts "partially obscured by system UI, typically by the hardware display notches or the system status bar", and it is derived from `viewPadding` minus `viewInsets`. It shrinks when the keyboard opens.
- `viewPadding`: the same hardware areas, but "remains the same regardless of ... a software keyboard" covering the area. This is the stable home-indicator and notch inset.
- `viewInsets`: "completely obscured by system UI, typically by the device's keyboard"; `viewInsets.bottom` is the top of the keyboard.
- Prefer the aspect-specific getters (`MediaQuery.paddingOf`, `viewPaddingOf`, `viewInsetsOf`, `sizeOf`, `textScalerOf`): they rebuild only when that attribute changes.
- `SafeArea`: has `top/bottom/left/right`, `minimum`, and `maintainBottomViewPadding` (use `viewPadding.bottom` instead of `padding.bottom`; avoids the bar jumping when the keyboard shows, which matters for a status band in the home-indicator area).

**Where bar colour goes (read in the framework source):**
- `NavigationBar` builds `Material(color: ...)` and puts `SafeArea` inside it, so the bar's background fills under the home indicator and its content is inset. This is the pattern wanted for the status band: paint the full-width band, then inset the text.
- `BottomAppBar` wraps its content in `SafeArea` inside the shape. `BottomNavigationBar` adds `MediaQuery.viewPaddingOf(context).bottom` as extra bottom padding inside its own background.
- Anything built as `SafeArea(child: Container(color: x))` leaves the inset area unpainted, showing the Scaffold background. Put the colour outside the `SafeArea`.
- `Scaffold.extendBody: true` lets the body extend behind the bottom bar and adds a `MediaQuery` bottom padding that matches the bar height. `extendBodyBehindAppBar` does the same for the top.

**System overlay style:**
- `statusBarBrightness`: "Only honored in iOS". It is the brightness of the status bar background, so a dark app uses `Brightness.dark` to get light icons (this is what `SystemUiOverlayStyle.light` sets).
- `statusBarIconBrightness`, `statusBarColor`, and all `systemNavigationBar*` fields: Android only.
- Set it with `AnnotatedRegion<SystemUiOverlayStyle>` around the screen or `AppBar.systemOverlayStyle`. `AppBar` wraps its descendants in an `AnnotatedRegion` already and computes the style from its background; "Apps should not enclose an AppBar with their own AnnotatedRegion".
- `SystemUiMode.edgeToEdge` is the default on iOS (status bar and home indicator visible). `immersive` modes hide the home indicator; do not use them here.

**Theme:** `ThemeMode.system` follows the OS; give `MaterialApp` both `theme` and `darkTheme`. Do not add an in-app override unless there is a product reason (see section 4). Recompute the overlay style from `Theme.of(context).brightness` so it follows live changes.

**Android edge-to-edge (for completeness):** targeting SDK 35 opts into edge-to-edge by default; from SDK 36 there is no opt-out. Flutter 3.27 and later targets it by default. Apps must handle insets themselves with `SafeArea` or `MediaQuery`, and Scaffold colours must reach the bars.

**Display corner radius on iOS:** Flutter has no core API for it. Apple publishes none ("Apple doesn't publish information on the corner radius of devices", Apple Frameworks Engineer, forums). Options found:
- `UIScreen._displayCornerRadius` (private selector): some packages use it, and apps using it "may be rejected" in App Review. Avoid, or obfuscate only at your own risk.
- `device_geometry`: hard-coded per-model map, deliberately avoids private API. Falls out of date with each new model.
- `corner_radius_plugin` 1.0.0: iOS via a bundled BezelKit JSON lookup by model identifier (it also mentions `UICornerConfiguration` on newer iOS). Depends on community data updates.
- Public iOS 26 route: UIKit corner-adapted layout margins (WWDC25 282), exposed to Flutter only by packages like `ios_window_control_layout` (`effectiveCornerRadii`, iOS 26+). Not reviewed in depth.
- Practical choice: a fixed fallback radius, or none, for this app. Painting full-bleed colour needs no radius at all because the display clips it.

Sources:
- https://api.flutter.dev/flutter/widgets/MediaQueryData/padding.html , .../viewPadding.html , .../viewInsets.html
- https://api.flutter.dev/flutter/widgets/SafeArea-class.html
- https://api.flutter.dev/flutter/material/Scaffold/extendBody.html
- https://api.flutter.dev/flutter/services/SystemUiOverlayStyle-class.html (field text read from https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/services/system_chrome.dart)
- https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/material/navigation_bar.dart , bottom_app_bar.dart , bottom_navigation_bar.dart , app_bar.dart , media_query.dart (same folder tree)
- https://api.flutter.dev/flutter/material/ThemeMode.html
- https://docs.flutter.dev/release/breaking-changes/default-systemuimode-edge-to-edge
- https://pub.dev/packages/corner_radius_plugin , https://pub.dev/documentation/device_geometry/latest/ , https://developer.apple.com/forums/thread/762419

## 7. Material 3 adaptive and window size classes

- Width classes (dp): compact < 600; medium 600 to < 840; expanded 840 to < 1200; large 1200 to < 1600; extra-large >= 1600. Height classes: compact < 480; medium 480 to < 900; expanded >= 900. Large and extra-large were added on top of Material's three.
- Size classes come from the window, not the device: "not intended for isTablet-type logic". They change at runtime (rotation, multitasking, resizing). Most apps can key off width alone, but check height for phones in landscape (compact height means a two-pane layout is not practical).
- Flutter's own guidance: use `MediaQuery.sizeOf` for app-level decisions and `LayoutBuilder` for local ones. "Your choice shouldn't depend on the type of device, but on the device's available window size." Below 600 logical pixels wide use a bottom navigation bar; at 600 and up use a navigation rail. "You should never portrait lock your app".
- Canonical layouts: list-detail (two panes at expanded width; one pane at compact/medium; state preserved across resize), supporting pane (about 70/30 at expanded, 50/50 at medium, bottom sheet at compact), feed (an adaptive grid with a minimum item width).
- `flutter_adaptive_scaffold` is discontinued (v0.3.3+1, "will not receive further updates"; discussion in flutter/flutter#162965). Build the switch by hand with `LayoutBuilder` plus `NavigationBar`/`NavigationRail` (a 600/840 breakpoint helper is a few lines).
- Apple's equivalent: size classes (compact/regular). HIG says to "keep functionality the same as size classes change", and to move from a tab bar to a sidebar in larger spaces.

Sources:
- https://developer.android.com/develop/ui/compose/layouts/adaptive/use-window-size-classes
- https://developer.android.com/develop/adaptive-apps/guides/canonical-layouts
- https://developer.android.com/develop/ui/compose/layouts/adaptive/support-different-display-sizes
- https://docs.flutter.dev/ui/adaptive-responsive/general
- https://pub.dev/packages/flutter_adaptive_scaffold
- (m3.material.io window-size-classes page returned 404 when fetched; the Android page states the same breakpoints and says they map to Material's.)

## 8. Dynamic Type and text scaling

- HIG Layout: apps that ignore text size "can be difficult or impossible to use". Horizontal groups may need to stack vertically, rows should grow in height, and single-line rows may need to become multi-line. HIG Typography: "aim to display as much useful text at the largest accessibility font size as you do at the largest standard font size"; avoid truncation in scrolling regions.
- Flutter text widgets follow the OS setting automatically (docs.flutter.dev, "Large fonts"). Test "on a small-screen device configured to use the largest font setting" (Settings > Accessibility > Display & Text Size on iOS).
- API: `MediaQuery.textScalerOf(context)` returns a `TextScaler`; `scale(fontSize)` computes the size. Prefer it to `textScaleFactor`, which is deprecated. `TextScaler.clamp(min, max)` and `MediaQuery.withClampedTextScaling` cap the range. Material's `NavigationBar` and `BottomNavigationBar` already clamp their label text, so do the same only for chrome that can't grow (the status band) rather than for content.
- Do not clamp body text or list rows to hide a layout problem; make them wrap or grow. Use `Flexible`/`Expanded`, `Wrap` and min-height constraints rather than fixed heights.

Sources:
- https://developer.apple.com/design/human-interface-guidelines/layout and https://developer.apple.com/design/human-interface-guidelines/typography
- https://docs.flutter.dev/ui/accessibility/ui-design-and-styling
- https://api.flutter.dev/flutter/widgets/MediaQuery/textScalerOf.html
- https://raw.githubusercontent.com/flutter/flutter/master/packages/flutter/lib/src/painting/text_scaler.dart

## Implications for this app

1. **Filling the home-indicator band is allowed, with limits.** No Apple page forbids non-interactive content there, but the bottom edge is a system-gesture zone. Put only passive text in it (host count, connection state, last-sync time), at low contrast, with no tap targets, and keep every button, row and tab above the safe-area bottom inset.
2. **Paint the band outside the `SafeArea`, put the text inside its own inset.** Follow the `NavigationBar` pattern: a full-width coloured `Container` whose child sits in `SafeArea`/`viewPaddingOf.bottom`. Use `maintainBottomViewPadding: true` (or `viewPadding`) so the band does not resize when the keyboard opens, and hide it while the keyboard is up.
3. **Do not read the inset to decide the band's content.** The band's height is the `viewPadding.bottom` value (about 34 pt in portrait on Face ID iPhones, smaller in landscape; **(unverified)**, read it at runtime). On iPhone SE 3 it is 0, so the band must collapse, or the status must move into a normal footer row.
4. **Extend bar colours to the corners.** Full-bleed background colour needs no corner radius; the display clips it. Give the top bar, the band and the Scaffold the same surface colour so no seam shows at the rounded corners. Do not add a custom corner radius (no public Flutter API; private `_displayCornerRadius` risks App Review rejection); use a fixed fallback radius for any floating card.
5. **Landscape and iPad sides.** Wrap scrolling content with `SafeArea(left/right)` (or `MediaQuery.paddingOf`) so rows clear the notch side inset, but let row backgrounds and dividers run to the edge. Re-read insets on rotation, and test the iPad windowed mode for the window-control overlap at the top leading corner.
6. **iPad windows.** Drop `UIRequiresFullScreen` if present, supply a launch screen, and drive the layout from `MediaQuery.sizeOf`/`LayoutBuilder`, not `Platform.isIOS`/device model. Use a rail at 600 dp and up and list-detail (computers and agents, then feed) at 840 dp and up. Do not use `flutter_adaptive_scaffold` (discontinued).
7. **Follow the OS colour mode.** Add a light theme and `darkTheme`, set `themeMode: ThemeMode.system`, derive colours from `ColorScheme`, and set the status-bar style from the active brightness (`AnnotatedRegion<SystemUiOverlayStyle>`; on iOS `statusBarBrightness` is what counts). Dark-only is permitted by Apple only in "rare cases" such as immersive media, so a light theme is the default expectation.
8. **No white flash.** Make the iOS launch storyboard colour adaptive (light and dark variants matching the first screen) and ensure the app's first frame uses the same background; check cold start in both modes.
9. **Dynamic Island and Live Activities are separate.** Don't draw anything near the island. If at-a-glance agent status outside the app is wanted, that is a native Live Activity (widget extension, `NSSupportsLiveActivities`, push updates, 8-hour cap), not a Flutter band.
10. **Text size.** Test the status band and bar labels at the largest accessibility size on iPhone SE 3. Let list rows grow and wrap; clamp (for example at 1.3) only the fixed-height band text, and never let it clip.
