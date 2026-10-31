# HotShare: Design Guide

**Audience:** an AI coding agent building the UI of HotShare (Flutter, Android + Windows).
**Companion document:** `HOTSHARE_IMPLEMENTATION_GUIDE.md` (architecture, state, data, protocol, phases). This file says **what it should look and feel like**; that one says **how to build it**. Where they overlap, the implementation guide wins on technical decisions and this guide wins on visual and interaction decisions.

"HotShare" is a working name taken from the project folder. Keep the app name in one constant so it can be renamed later.

---

## 1. Product intent

HotShare moves files between the user's own devices (Windows PC and Android phone, later Android to Android and macOS) over a direct local link, usually the phone's hotspot. There is no cloud, no account, and nothing stored on a server.

The feeling to aim for is **AirDrop**: you do not "upload and wait". You drop a file on a device and it is simply *there*.

### Design principles

1. **Devices, not files, are the main characters.** The home screen is about *who is nearby*, not a file list.
2. **Zero-config after the first pairing.** Paired devices reconnect silently. No PIN, no IP, no "Connect" button in normal use.
3. **No traditional loading states.** Never show a blocking spinner or a full-width progress bar as the primary feedback. Progress lives *on the device bubble* (a ring) and in the history item. Content appears instantly (optimistic UI) and settles into place.
4. **One gesture to send.** Drop it, or share it. Either goes straight to the device when only one is online.
5. **Quiet when idle, alive when active.** Calm, dark, glassy surface at rest; motion only when something is happening or the user is interacting.
6. **Honest.** Do not fake proximity or distance. Do not claim "delivered" until the receiver has verified it.

---

## 2. Visual language: "Ember Glass"

Reference mood (from the user's chosen inspiration): **dark base, warm red-to-orange glow behind frosted-glass cards, large rounded corners, pill buttons and pill navigation, glowing red progress, floating file-type glyphs.** Use that language, adapted to HotShare's features.

### 2.1 Colour tokens

Define these once in a `HsColors` class (and a `ThemeExtension`). Dark theme is the primary design; light theme is a later phase (section 12).

| Token | Value | Use |
| --- | --- | --- |
| `bg.base` | `#0A0A0C` | App background under everything |
| `bg.raised` | `#141417` | Opaque fallback for glass surfaces |
| `glow.deep` | `#7A0A12` | Bottom/outer background glow |
| `glow.mid` | `#E5231B` | Main glow, primary accent |
| `glow.hot` | `#FF7A1A` | Top-edge warm highlight, secondary accent |
| `accent.primary` | `#E5231B` | Primary buttons, active ring |
| `accent.warm` | `#FF7A1A` | Secondary highlights, gradients |
| `success` | `#34D27B` | Delivered, connected |
| `warning` | `#FFC247` | Reconnecting, slow link |
| `danger` | `#FF4D4F` | Failed, forget device |
| `text.primary` | `#FFFFFF` at 95% | Titles, body |
| `text.secondary` | `#FFFFFF` at 62% | Captions, metadata |
| `text.tertiary` | `#FFFFFF` at 38% | Hints, disabled |
| `glass.fill` | `#FFFFFF` at 7% | Glass surface tint |
| `glass.fillStrong` | `#FFFFFF` at 12% | Pressed/selected glass |
| `glass.stroke` | `#FFFFFF` at 16% | 1 px border |

Background recipe: `bg.base` plus two large blurred radial gradients (a `glow.mid` blob bottom-left, a `glow.hot` blob top-right, each ~60% of screen width, ~35% opacity) that **drift very slowly** (30 to 60 s loop). Optional 2 to 3% film grain overlay to avoid banding.

### 2.2 Glass recipe (the one component everything builds on)

`GlassSurface` = stack of, bottom to top:

1. **Backdrop blur** (`BackdropFilter` with `ImageFilter.blur`). Sigma **24** for large panels on Windows, **16 to 20** on Android (performance), **10** for small elements.
2. **Tint fill**: `glass.fill` (add a faint vertical gradient: 10% at top to 5% at bottom).
3. **Border**: 1 px gradient stroke, brighter top-left (`#FFFFFF` 28%) fading to bottom-right (`#FFFFFF` 8%). This gives the "edge of glass" look.
4. **Specular highlight**: 1 px inner line along the top edge at `#FFFFFF` 22%.
5. **Shadow**: `#000000` at 35%, blur 30, offset y +12, spread -8 (never a hard shadow).

Shape: cards radius **28**, inputs **20**, chips and buttons **fully round (pill)**, bottom sheets radius **32** on top corners.

**Press feedback:** scale to 0.97 over 120 ms and raise `glass.fill` to `glass.fillStrong`. Release springs back (damping 0.7).

### 2.3 Liquid glass (optional enhancement layer)

True "liquid glass" (light refraction at the edges) is shader based and costly. Use it **only on a few hero elements**: the floating bubble, the primary "send" orb and the dock handle. Evaluate the `liquid_glass_renderer` package (verify it is maintained and works on Flutter's current stable with Impeller on both Android and Windows). Rules:

- Always wrap behind a `GlassStyle` switch: `frosted` (default, cheap) vs `liquid` (shader).
- Auto-fallback to `frosted` if frame time exceeds budget (section 11) or the user enables "Reduce transparency".
- Never use the shader version inside scrolling lists.

### 2.4 Typography

Bundle one family so Windows and Android match: **Inter** (or **Manrope**). Do not rely on system fonts.

| Style | Size / weight | Use |
| --- | --- | --- |
| `display` | 34 / 700, tracking -0.5 | Greeting, big numbers |
| `title` | 22 / 650 | Screen titles, sheet titles |
| `headline` | 17 / 600 | Card titles, device names |
| `body` | 15 / 450 | Default text |
| `caption` | 12.5 / 500, `text.secondary` | Metadata, sizes, times |
| `mono` | 12 / 450 (JetBrains Mono or system mono) | Codes, hashes, logs |

Use tabular figures for sizes, speeds and percentages so they do not jitter while updating.

### 2.5 Iconography and file glyphs

- UI icons: one consistent rounded line set (e.g. Phosphor or Lucide via a Flutter package). 1.75 px stroke.
- **File-type glyphs** are a signature element: small folded-corner "document" icons in colour (PDF red, DOCX blue, XLSX green, PPTX orange, ZIP amber, image/video use real thumbnails, other uses a neutral glass tile with the extension). Build them as vector widgets (`FileGlyph(kind, ext)`), not images, so they scale and animate.
- On the home screen, up to 3 recent file glyphs **float** above the "Recent" card with a slow parallax bob (reference: the floating XLSX/PDF/DOCX icons).

---

## 3. Platform treatment

### 3.1 Windows (11 primary, 10 supported)

- **Window material:** Mica (default) or Acrylic via `flutter_acrylic`, with a fully transparent Flutter background so the material shows through, then the glass layers sit on top. Test window dragging performance: acrylic can lag when moving the window on some Windows 11 builds, so default to **Mica**, and use acrylic only for the small Drop Dock window if it tests smooth.
- **Fallback:** if effects are unavailable (Windows 10 without effect support, remote desktop, effect init failure) use the opaque `bg.base` plus the animated gradient background and frosted glass. Never leave a transparent window with nothing behind it.
- **Title bar:** hidden native bar (`window_manager`), custom draggable top strip 40 px tall with app name, connection status dot, and min / max / close buttons styled as glass circles. Keep Windows 11 snap layouts working on the maximise button if feasible.
- **Layout:** left **navigation rail** (glass pill, vertical, 72 px wide) instead of a bottom bar. Content area max width 960 px, centred.
- **Window defaults:** 980 x 680, minimum 420 x 600 (must stay usable as a narrow companion window). Remember size and position.
- **Close = hide to tray.** Tray icon shows status (grey = no paired device online, accent = connected, pulsing = transferring). Tray menu: Open, Send file..., status line, Pause receiving, Quit.
- **Drop Dock** (see 7.2): a small always-on-top docked glass pill for drag-and-drop from anywhere.
- **Native feel:** Segoe-style window radius (follow OS), system accent colour is *not* used (brand colours win), but respect Windows light/dark for the *chrome* in the later light theme.

### 3.2 Android

- **Edge to edge**, transparent status and navigation bars, gradient background reaching behind them.
- No system blur is available to us, so glass is **frosted `BackdropFilter` over the animated gradient background**. Because the background is gradient-rich, the blur reads as glass.
- **Bottom pill navigation** (floating glass pill, 4 items) with the active item shown as a bright circular "lens" (reference: white circular selected state). Sits 16 dp above the gesture bar.
- Respect Android 12+ themed icon, predictive back, and per-app language later. Material 3 widgets may be used underneath but **restyled**; do not leave default Material surfaces visible.
- Large touch targets: minimum 48 dp.

### 3.3 Shared rules

- One design system (`/ui/design_system`), two shells (`MobileShell`, `DesktopShell`). Screens are shared widgets that take a layout hint (`compact` < 600 px wide, `regular` >= 600 px).
- **Reduce transparency** (user setting + OS accessibility signal): replaces every `BackdropFilter` with the opaque `bg.raised` tinted fill, keeps borders and shadows.

---

## 4. Navigation and information architecture

Four top-level destinations, same on both platforms:

| Tab | Purpose |
| --- | --- |
| **Nearby** (home) | Device bubbles, send/receive, recent activity |
| **History** | Everything sent and received, searchable |
| **Devices** | Paired devices, pairing flow, per-device settings |
| **Settings** | Storage, behaviour, appearance, about |

Android: floating pill bar. Windows: left rail. Navigation transitions are a short fade-through (180 ms) with a 8 px vertical shift; no heavy page slides.

---

## 5. Screens

### 5.1 Nearby (home)

**Purpose:** see who is reachable, send, and watch things arrive.

Elements, top to bottom (Android) / centre stage (Windows):

1. **Header:** "Hello, *{this device name}*" (`display`), small status line: "Connected to 1 device" / "Waiting for your devices" with a `StatusDot`. Settings gear (glass circle) top right on Android.
2. **Radar stage** (the hero):
   - Centre: **You orb**, a glass circle (96 dp) with this device's platform glyph, slow breathing glow.
   - 2 to 3 faint concentric rings pulsing outward every 3 s while idle-connected.
   - **Device bubbles** (72 dp glass circles with platform glyph + initial) positioned on an orbit around the orb. Position is **stable and by recency/trust**, not by distance (do not imply distance we cannot measure).
   - Bubble states (see 5.1.1).
3. **Recent card** (`GlassSurface`, radius 28): last 3 transfers as compact rows, a "See all" link, and the floating file glyphs above it.
4. **Primary action:** Android: a glass **Send** orb (64 dp, liquid style if enabled) docked centre above the nav pill; tap opens the system picker. Windows: the whole stage is a drop target and a "Choose files" pill sits under it.

#### 5.1.1 Device bubble states

| State | Visual | Behaviour |
| --- | --- | --- |
| **Online** | Full-brightness glass, soft accent glow, small green dot | Tap = pick files and send; drop = send |
| **Connecting / reconnecting** | Dim, ring pulsing warm (`warning`) | Not droppable; tooltip "Reconnecting..." |
| **Offline** | 40% opacity, no glow, "Last seen 10:42" caption | Tap opens a sheet: "Queue files to send when it's back" |
| **Transferring** | **Circular progress ring** hugging the bubble (accent gradient, round caps), file glyph or thumbnail at the centre, speed in `caption` under it | Tap = details sheet |
| **Success** | Ring completes, morphs into a check, brief green pulse, then returns to Online | Haptic (Android) |
| **Failed** | Ring turns `danger`, shakes once, shows "Retry" | Tap retries |

#### 5.1.2 Drag-over behaviour (Windows)

When files enter the window anywhere:

- Background dims 20%, radar rings accelerate.
- If **exactly one** paired device is online, the **entire window** becomes its target: that bubble grows 1.25x and glows, caption "Release to send to *{Name}*".
- If several are online, each bubble becomes an individual target (hover = grow and glow).
- If none online: bubbles stay dim, caption "No device online. Release to queue for {Name}" (queue only if a last-used device exists).
- On drop: the file's glyph/thumbnail shrinks and **flies along a curve into the bubble** (350 ms), ring begins.

### 5.2 Receive experience

- **Trusted device, auto-accept on (default after pairing):** nothing blocks the user. A **toast pill** slides from the top (Android) or bottom-right (Windows) with a thumbnail stack, "Receiving 3 files from *{Name}*" and a ring. On completion it turns into "Saved to Pictures/HotShare. **Open**". Auto-dismiss after 6 s, stays in History.
- **Auto-accept off for that device:** a glass bottom sheet (Android) or centred modal card (Windows) with preview (thumbnail for images/video, glyph otherwise), name, size, **Accept** (primary) and **Decline**. Auto-decline after 60 s.
- The incoming bubble on Nearby shows the ring for the receiver too. Both sides see the same story.
- **Never** show a modal "Transfer complete" dialog.

### 5.3 History

- Grouped headers: Today, Yesterday, then dates (sticky, glass).
- **Row:** thumbnail or `FileGlyph` (48 dp rounded), name (`headline`, one line, middle-ellipsis for extensions), caption "2.5 MB, to *Justin's PC*, 10:42", direction arrow icon, status chip only when not "done" (Failed, Cancelled, Queued, Sending).
- **Filters:** pill chips: All, Sent, Received, Images, Videos, Documents, Failed. Search field (glass, expands on tap).
- **Actions:** Windows: hover reveals Open, Show in folder, Send again, Delete. Android: swipe right = Send again, swipe left = Delete from history; long-press = multi-select.
- **Detail sheet** (tap): large preview, full name, size, device, direction, start time, duration, average speed, saved path, integrity badge ("Verified"), buttons Open / Show in folder (Windows) / Share (Android) / Send again / Delete (with a checkbox "also delete the file").
- **File missing** (moved or deleted): row dims and shows "File not found" with Remove from history.
- Empty state: floating glyphs with copy "Nothing sent yet. Drop a file on a device to start."

### 5.4 Devices and pairing

- **Device card** per paired device: platform glyph, name (editable inline), status, "Last connected", toggles: *Auto-accept files* and *Allow this device to start transfers*, optional *Save folder override*, and **Forget device** (danger, confirm sheet).
- **Pair new device** (primary pill button):
  1. **Phone (the listening side):** shows a glass sheet with a large **6-digit code** (mono, spaced), a QR code of the same pairing payload, countdown ring (60 s), caption "Enter this on the other device".
  2. **PC:** "Pair with a phone" dialog. IP is auto-detected from the hotspot gateway; user types the 6-digit code once.
  3. **Both screens** then show a **verification phrase** (4 emoji or 4 words, e.g. "rocket, maple, anchor, fox") derived from both public keys: "Do these match on both devices?" **Yes, they match / No**.
  4. Success: both bubbles fly together and merge, glow, "Paired with *{Name}*", then the new bubble appears on the radar. Haptic on Android.
  - Android to Android uses the QR instead of typing the code.
- Empty state: radar with a single dashed ghost bubble and "Pair your first device".

### 5.5 Settings

Grouped glass cards. See section 9 for the full list. Each row: label, optional caption, trailing control. Changing a setting applies immediately (no Save button).

### 5.6 Onboarding (first run, 3 steps max)

1. "Share between your devices, directly." (floating glyph animation)
2. **Permissions with reasons** (Android): notifications, "keep running in background" (battery exemption) and, on Xiaomi/MIUI/HyperOS, the autostart guidance. Skip is allowed; features degrade gracefully.
3. **Name this device** (prefilled from the system) and **Pair your first device**.

---

## 6. Motion and feedback

Default curve `Cubic(0.2, 0.8, 0.2, 1.0)` (fast out, soft landing); springs for anything "physical". Respect "Reduce motion": replace movement with a 120 ms fade, keep ring progress.

| Interaction | Motion | Duration | Extra |
| --- | --- | --- | --- |
| Press on glass | Scale 0.97 + fill up | 120 ms | Springs back |
| Drag enters window | Dim + target bubble scale 1.25 + glow | 180 ms | Rings speed up |
| Drop / send | Glyph shrinks and follows a curve into bubble | 350 ms | Ring fades in |
| Transfer progress | Ring sweep eased between updates (never jumps) | per update, 200 ms | Update UI at most 10 Hz |
| Transfer success | Ring completes, check draws, green pulse | 450 ms | Light haptic, optional soft sound |
| Transfer failure | Ring to `danger`, 6 px horizontal shake x2 | 300 ms | Error haptic |
| Receive toast | Slide + fade from edge, thumbnail stack fans out | 280 ms | Sits 6 s |
| Receive complete | Toast morphs to "Saved" | 200 ms | |
| Pairing success | Two bubbles glide together and merge, ripple | 700 ms | Success haptic |
| Bubble appears (device comes online) | Scale 0.6 to 1 with overshoot, glow in | 400 ms | |
| Bubble leaves (offline) | Fade to 40%, glow out | 300 ms | |
| Tab change | Fade-through + 8 px shift | 180 ms | |
| Background gradient | Slow drift | 30 to 60 s loop | Pauses when app not visible |

**Sound and haptics:** Android `HapticFeedback.lightImpact` on send start and success, `heavyImpact` on failure. Sounds are optional (Settings), short and soft, off by default.

**Optimistic UI rule:** the moment the user drops or shares, the history item exists in "Sending" state and the ring is visible. Do not wait for the receiver's accept before showing anything. If the receiver declines, animate the item to "Declined".

---

## 7. Entry points from outside the app

### 7.1 Android

- **Share sheet ("Share with")**: HotShare appears for any file type (single and multiple). Tapping it opens a **translucent quick-send sheet** over the previous app:
  - If exactly one paired device is online: **send immediately**, show the flight animation and a toast "Sending to *{Name}*", dismiss within about 1.2 s. The foreground service continues in the background with a progress notification.
  - If several are online: glass sheet with device bubbles, tap one.
  - If none online: sheet says "*{Name}* isn't reachable. Turn on your hotspot or open HotShare on it." with **Queue and send when connected** (primary) and **Cancel**.
  - Show a thumbnail strip of what is being shared and the count.
- **Direct Share** (optional later): each paired device appears as its own target in the share sheet ("My PC").
- **Floating bubble** (optional, user-enabled): 56 dp liquid-glass orb, snaps to the screen edge, idles at 60% opacity. Shows a progress ring during transfers. Tap expands it into a mini glass panel: device chips, **Send file**, last transfer. Long-press and drag to dismiss zone at the bottom. Requires the "Draw over other apps" permission; explain it before asking.
- **Notifications:** ongoing progress notification (title = file, text = "to *{Name}* 42%, 18 MB/s", action **Cancel**); completion notification with **Open** and **Share**. Group multi-file batches into one notification.
- **Quick Settings tile** (optional): "HotShare receiving" on/off.

### 7.2 Windows

- **Drop Dock:** a small always-on-top glass pill (about 72 x 220 px) docked to a screen edge, user-enabled. Idle: shows only a thin handle with the app glyph at 70% opacity. When a drag enters the screen edge zone or the pill itself, it expands (250 ms) into a 320 x 160 glass panel with device bubbles; dropping on a bubble sends. Shows a ring during transfer. Auto-collapses 2 s after leaving.
- **Explorer integration:** right-click any file, **Send with HotShare** (and **Send to > HotShare**). Behaves like the Android share sheet: if one device is online, it sends immediately and shows a small toast window; otherwise a small device picker window.
- **Tray:** see 3.1. Left click opens the window; the tray icon never blocks.
- **Windows toast** on receive: "*{Name}* sent *photo.jpg*" with buttons **Open** and **Show in folder**. Taskbar button shows transfer progress.

---

## 8. Component inventory

Build in `/ui/design_system`. Every component works on both platforms and honours Reduce transparency and Reduce motion.

| Component | Key props | Notes |
| --- | --- | --- |
| `AppBackground` | `intensity`, `animated` | Gradient glows + grain; pauses when hidden |
| `GlassSurface` | `radius`, `blur`, `tint`, `elevation`, `style` | The base of everything; `style` = frosted / liquid / opaque |
| `GlassButton` | `label`, `icon`, `kind` (primary, secondary, ghost, danger), `onPressed`, `loading` | Pill; primary uses accent gradient fill; **no spinner**, `loading` shows an inline shimmering ring |
| `GlassIconButton` | `icon`, `size`, `badge` | Circle |
| `GlassTextField` | `label`, `prefix`, `suffix` | Radius 20 |
| `GlassSwitch`, `GlassSlider`, `GlassChip` | | Matching accent |
| `PillNav` / `NavRail` | `items`, `index` | Android pill with circular "lens"; Windows rail |
| `GlassSheet` | `child`, `detents` | Bottom sheet (Android) / centred modal (Windows) |
| `DeviceBubble` | `device`, `state`, `progress`, `thumbnail`, `onTap`, `onDrop` | The most important widget; owns all states in 5.1.1 |
| `RadarStage` | `devices`, `selfDevice` | Lays out bubbles, draws rings; wrapped in `RepaintBoundary` |
| `TransferRing` | `progress`, `state`, `size` | Custom painter; eased; round caps; accent gradient |
| `FileGlyph` | `kind`, `ext`, `size` | Vector, animatable |
| `FileThumb` | `path`, `kind` | Cached <= 256 px thumbnail, falls back to `FileGlyph` |
| `TransferToast` | `transfers`, `onOpen` | Receive/send toast |
| `HistoryTile` | `transfer`, `actions` | Row in 5.3 |
| `PairingCodeView` | `code`, `expiresAt`, `qrData` | Large mono code + countdown ring + QR |
| `VerifyPhrase` | `words` | The matching check in pairing |
| `StatusDot` | `state` | Green, amber pulse, grey |
| `EmptyState` | `glyphs`, `title`, `body`, `cta` | Floating glyph composition |
| `Shimmer` | | Only for unknown-content placeholders (thumbnails), never for transfers |

---

## 9. Settings specification (UI)

| Group | Setting | Control | Default |
| --- | --- | --- | --- |
| **This device** | Device name | Text | System name |
| | Show pairing code | Button | |
| **Receiving** | Auto-accept from trusted devices | Switch | On |
| | Ask before saving from this device (per device, in Devices) | Switch | Off |
| | Pause receiving | Switch (also in tray / notification) | Off |
| **Storage** | **Save location** | Windows: folder picker, shows current path. Android: choice of **By file type** (Pictures, Movies, Music, Download under a `HotShare` folder) or **Everything in Downloads**; advanced "Choose folder..." (system folder picker) | Windows: `Downloads\HotShare`. Android: By file type |
| | Organise into sub-folders | None / By type / By date / By device | None |
| | Keep partial files after failure | Switch | Off |
| **History** | Keep history | 30 days / 90 days / Forever | 90 days |
| | Clear history | Button (confirm) | |
| | Also delete files when removing history items | Switch | Off |
| **Connection** | Run in background (Android) | Switch, plus battery and autostart help | On |
| | Start with Windows | Switch | Off |
| | Minimise to tray on close (Windows) | Switch | On |
| | Reconnect automatically | Switch | On |
| **Appearance** | Theme | Dark / Light / System | Dark |
| | Reduce transparency | Switch | Off (auto-on if OS says so) |
| | Reduce motion | Switch | Off (auto-on if OS says so) |
| | Glass style | Frosted / Liquid (experimental) | Frosted |
| | Haptics / Sounds | Switches | On / Off |
| **Shortcuts** | Floating bubble (Android), Drop Dock (Windows), Explorer "Send with HotShare" | Switches | Off |
| **Advanced** | Verify file integrity (checksum) | Switch | On |
| | Transfer chunk size | Auto / 256 KB / 512 KB / 1 MB | Auto |
| | Diagnostics log, Benchmark screen | Buttons | |
| **About** | Version, licences | | |

---

## 10. Copy and states

Short, friendly, no jargon. Examples:

- Idle, nothing paired: "Pair your first device to start sharing."
- Paired but offline: "*{Name}* isn't nearby. Turn on your hotspot or open HotShare there."
- Reconnecting: "Reconnecting to *{Name}*..."
- Sending: "Sending *photo.jpg* to *{Name}*"
- Done: "Delivered" (only after the receiver verified)
- Failed: "Couldn't send. *{Name}* went offline. **Retry**"
- Declined: "*{Name}* declined this file."
- Queued: "Will send when *{Name}* is back."
- Out of space (receiver): "*{Name}* doesn't have enough space."

Error states are always actionable (a button), never a dead-end dialog.

---

## 11. Accessibility and performance budget

**Accessibility**
- Text contrast >= 4.5:1 *on the glass*, tested over the brightest part of the background; if it fails, increase tint opacity.
- Every bubble, ring and glyph has a semantic label ("Justin's PC, online, sending photo.jpg, 42 percent"). Progress is announced at most every 10%.
- Full keyboard navigation on Windows (Tab order, focus ring in accent), Enter to send to the focused bubble, shortcuts: `Ctrl+O` choose files, `Ctrl+V` send clipboard files, `Ctrl+,` settings.
- Respect OS font scale up to 130% without clipping.

**Performance budget (measure on a mid-range Android phone and a modest Windows laptop)**
- Cold start to interactive: **under 1.0 s** (Android), **under 1.5 s** (Windows).
- Steady 60 fps (120 where the display supports it); no frame over 16 ms during idle animation.
- At most **3 simultaneous `BackdropFilter`s** on screen. **Never** inside list items; list items use the opaque tinted fallback.
- Animate only `transform` and `opacity`; wrap the radar, rings and background each in a `RepaintBoundary`.
- Progress state updates reach widgets at most **10 times per second**.
- Thumbnails decoded at <= 256 px and cached; no full-size images in lists.
- Background gradient animation pauses when the app is not visible or when Reduce motion is on.
- An in-app frame-time monitor (debug only) auto-downgrades `liquid` to `frosted` and `frosted` to `opaque` if the budget is blown repeatedly.

---

## 12. Later: Light theme

"Frosted Ice": `bg.base` `#F4F5F8`, glass tint white at 55% with a 1 px `#FFFFFF` 80% border and soft grey shadow, accent unchanged. Background glows become pale warm blobs at 20% opacity. Build all colours through tokens from day one so this is a token swap, not a rewrite.

---

## 13. Assets to produce

- App icon (adaptive on Android, multi-size ICO on Windows) in the Ember Glass style; monochrome version for Android themed icons and the tray (light and dark variants).
- Platform glyph set for device bubbles: phone, laptop, desktop, tablet, Mac.
- Vector file-type glyphs (section 2.5).
- Optional: 3 short UI sounds (send, received, error), under 300 ms each.
- Empty-state composition (floating glyphs), no raster art required.

---

## 14. Design acceptance checklist

- [ ] Home screen shows device bubbles with all six states from 5.1.1.
- [ ] Sending never shows a blocking spinner or full-width progress bar; progress is on the bubble ring and in History.
- [ ] Dropping a file on Windows with one device online sends with one gesture and the fly-in animation.
- [ ] Android share sheet to HotShare sends in one tap (or zero when one device is online).
- [ ] Receiving from a trusted device needs no taps and shows the toast.
- [ ] History supports search, filters, open, show in folder (Windows), resend and delete.
- [ ] Pairing completes with a code once, then future connections need nothing.
- [ ] Storage location is configurable in Settings and the chosen path is visible.
- [ ] Glass looks right on Windows (Mica/Acrylic) and Android (frosted), and degrades cleanly with Reduce transparency.
- [ ] Reduce motion and large font scale tested.
- [ ] Performance budget met on the target devices.
