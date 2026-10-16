# hush. Design and Motion Guide

Companion app for the JBL Tune 770NC and 670NC. This guide covers every visual value and every animation so the Swift build matches the design exactly. All sizes are in points.

Open `Reference/hush-design.html` in a browser for the live, clickable version. The PNGs in `Reference/` are the static snapshots.

---

## 1. What is in this kit

| Folder | What it is | How to use it |
|---|---|---|
| `Assets.xcassets` | Colors (light and dark), headphone photos, logo, menu bar icons, UI icons, app icon | Drag the whole folder into Xcode, or copy the groups you need into your existing catalog |
| `Fonts/` | Fredoka (Medium, SemiBold, Bold) and Nunito (Medium, SemiBold, Bold, ExtraBold), static TTFs, plus OFL licences | Add to the target. Register them (section 2) |
| `SVG/` | Source vectors for the logo, lockups, menu bar icons, UI icons, app icon | For web, marketing, or re-exporting |
| `Photos/` | Full resolution transparent headphone photos and the 1024 app icon | Masters. The catalog already has 1x/2x/3x versions |
| `Reference/` | Offline design page and PNG snapshots of every state | Visual source of truth |
| `semantic-colors.json` | The semantic color table below, as data | Optional |

### Asset names

**Colors / Brand** (same in light and dark)

| Name | Hex |
|---|---|
| `BrandOrange` | #FF6500 |
| `BrandNavy` | #1E3E62 |
| `BrandDeepNavy` | #0B192C |
| `BrandBlack` | #000000 |

**Colors / Semantic** (light value / dark value)

| Name | Light | Dark | Used for |
|---|---|---|---|
| `CardFrame` | #FFFFFF | #000000 | Outer frame of the card and the cut-out tab |
| `PanelHighlight` | #3666A0 | #1E3E62 | Panel gradient, centre |
| `PanelBase` | #1E3E62 | #0B192C | Panel gradient, middle (56%) |
| `PanelEdge` | #132B47 | #03070D | Panel gradient, outside |
| `TextPrimary` | #FFFFFF | #FFFFFF | Titles, labels |
| `TextSecondary` | white 76% | #E6ECF4 66% | Sub text, status, footer |
| `GlassFill` | white 14% | white 7% | Battery chip, hotspot, note row |
| `GlassStroke` | white 32% | white 14% | Battery chip and round icon button borders |
| `ButtonFill` | white 3% | white 3% | Mode button resting fill |
| `ButtonStroke` | white 14% | white 14% | Mode button resting outline |
| `ButtonStrokeHover` | white 28% | white 28% | Mode button hover outline |
| `ButtonStrokeActive` | white 35% | white 35% | Outline on the orange active button |
| `ButtonStrokeDisabled` | white 7% | white 7% | Disabled outline |
| `ModelNumberTop` | #FFFFFF | #30609A | Giant model number, gradient top |
| `ModelNumberBottom` | white 75% | #1E3E62 25% | Giant model number, gradient bottom |
| `PillBackground` | #FFFFFF | #000000 | Collapsed pill |
| `PillInk` | #0B192C | #FFFFFF | Collapsed pill mark |
| `ChipFill` | #FFFFFF | white 10% | Model chip, top left |
| `ChipInk` | #1E3E62 | #FFFFFF | Model chip text |

The panel is navy in both themes. Light and dark only change the frame (white or black), the gradient depth, the photo, and the model number color.

**Headphones** (1x/2x/3x, 230 pt tall at 1x, transparent)

`Tune770Black`, `Tune770White`, `Tune670Black`, `Tune670White`

**Brand** (vector PDF, preserves vector data)

| Name | Notes |
|---|---|
| `HushMark` | Arch navy in light, white in dark, orange dot. Original rendering |
| `HushMarkWhite`, `HushMarkNavy` | Fixed color versions |
| `HushArchTemplate` | Arch only, template rendering, for tinting. Draw the dot yourself |
| `HushWordmark` | "hush." in Fredoka Bold, navy in light, white in dark, orange period |
| `HushLockup` | Mark plus wordmark |

**MenuBar** (template PDFs, 18 pt, for `NSStatusItem`)

| Name | Mode it represents |
|---|---|
| `MenuBarANC` | ANC (solid dot) |
| `MenuBarAmbient` | Ambient (ring) |
| `MenuBarOff` | Off (arch only) |
| `MenuBarNoDevice` | Nothing connected (faint dot) |

**Icons** (template PDFs, 24 grid, 1.9 stroke, round caps and joins)

`IconOff`, `IconANC`, `IconAmbient`, `IconTalkThru`, `IconLock`, `IconSettings`, `IconPower`, `IconPlus`, `IconInfo`, `IconChevronDown`

**AppIcon** is a full macOS set, 16 to 1024.

---

## 2. Fonts

| Role | Font | PostScript name |
|---|---|---|
| Giant model number, device name, battery value, wordmark | Fredoka | `Fredoka-Bold`, `Fredoka-SemiBold`, `Fredoka-Medium` |
| Everything else (labels, status, chips, buttons) | Nunito | `Nunito-ExtraBold`, `Nunito-Bold`, `Nunito-SemiBold`, `Nunito-Medium` |

Register them either way:

- Info.plist: `ATSApplicationFontsPath` = the folder name the TTFs sit in inside Resources (for example `Fonts`).
- Or at launch, for each TTF: `CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)`.

Then `Font.custom("Fredoka-Bold", size: 150)`.

### Type scale

| Element | Font | Size | Tracking | Color |
|---|---|---|---|---|
| Model number ("770") | Fredoka Bold | 150 (side docks 112) | -5% (-7.5) | Gradient `ModelNumberTop` to `ModelNumberBottom`, top to bottom |
| Device name | Fredoka SemiBold | 19 | -0.2 | `TextPrimary` |
| Battery value | Fredoka SemiBold | 19 | 0 | white |
| Tab wordmark | Fredoka Bold | 16 | -0.3 | navy in light, white in dark, period orange |
| Mode label | Nunito Bold | 11 (side docks 12) | 0.1 | white |
| Sub text ("Connected") | Nunito SemiBold | 12.5 | 0 | `TextSecondary` |
| Status line, mode name | Nunito ExtraBold | 12 | 0 | `TextPrimary` |
| Status line, detail | Nunito SemiBold | 12 | 0 | `TextSecondary` |
| Model chip | Nunito ExtraBold | 11.5 | 0.2 | `ChipInk` |
| Eyebrows (BATTERY, BLUETOOTH, SYNCED) | Nunito ExtraBold, uppercase | 9.5 | 1.5 | `TextSecondary` at 80% |
| SOON tag | Nunito ExtraBold, uppercase | 8.5 (side 9) | 1.2 | white at 55% |

---

## 3. Collapsed pill

Reference: `pills-dark.png`, `pills-light.png`, `edges-collapsed.png`.

| Property | Value |
|---|---|
| Size | 46 x 34, fully rounded (radius 17). Left and right docks: 34 x 46 |
| Fill | `PillBackground` (black in dark, white in light) |
| Border | inner 1 pt line: white 16% on black, `BrandDeepNavy` 8% on white |
| Shadow | y 10, blur 24, spread -8, black 70% (dark) or `BrandDeepNavy` 40% (light) |
| Hover | scale 1.06, spring (section 9) |

**Content when a 770NC or 670NC is detected:** the headphone photo plus a battery bar.

- Photo height 26 (side docks 22). The photo color flips for contrast: **white headphones on the black pill, black headphones on the white pill.**
- Battery bar: 3 x 14 (side docks 16 x 3, lying flat under the photo), radius 2, track grey at 35%, fill `BrandOrange` from the bottom (from the left on side docks). Fill height = battery %.
- Gap between photo and bar: 5 (side docks 4, stacked).

**Content when nothing is connected:** `HushMark` at 20 pt, dot dimmed to 40%. No battery bar.

**Under the notch (top dock on notched Macs):** always `BrandBlack` in both themes so it fuses with the notch. Square top corners, 17 radius bottom corners. Shadow becomes an orange glow: y 12, blur 26, spread -10, `BrandOrange` 60%. Photo is the white headphones.

**Conditions on the pill**

| Condition | Change |
|---|---|
| Connecting | Photo at 35% opacity. Battery bar replaced by a 10 pt orange spinner |
| Low battery (under 15%) | 1.5 pt inner `BrandOrange` outline, orange glow (blur 22, 80%), battery bar pulses |
| No device | Mark instead of photo, dot at 40% |

---

## 4. Expanded card, anatomy

Reference: `card-770-dark.png` and the other `card-*.png` files. Top to bottom:

```
┌ frame (7 pt, CardFrame) ───────────────────────────┐
│ ┌ panel (navy radial gradient) ──────────────────┐ │
│ │ [770NC chip]   ╰ tab: mark + hush. ╯  (⚙) (⏻) │ │  top row, 28 tall
│ │                                                │ │
│ │          7 7 0   (giant number)                │ │
│ │       [ headphone photo ]      ┌BATTERY┐       │ │  hero, 236 tall
│ │   (+)                          │ 82%   │       │ │
│ │                                └───────┘       │ │
│ │ JBL Tune 770NC                                 │ │  name, +10 gap
│ │ ● Connected                                    │ │
│ │ [ Off ][ ANC ][ Ambient ][ SOON TalkThru ]     │ │  mode buttons, +12 gap
│ │ ● ANC  set by headphones                       │ │  status, +10 gap
│ │ BLUETOOTH                              SYNCED  │ │  footer, +12 gap
│ └────────────────────────────────────────────────┘ │
└────────────────────────────────────────────────────┘
```

### Frame and panel

| Property | Value |
|---|---|
| Card width | 374 (side docks 296). Height follows content, about 470 |
| Frame | `CardFrame`, 7 inset on every side, corner radius 33 (continuous) |
| Panel | corner radius 27 (continuous), padding 14 |
| Panel padding on the docked side | left dock: leading 38, right dock: trailing 38, bottom dock: bottom 10 |
| Panel fill | Radial gradient. Centre at x 50%, y 28%. Stops: `PanelHighlight` 0, `PanelBase` 0.56, `PanelEdge` 1. End radius about the card height |
| Card shadow (light theme) | y 30, blur 60, spread -24, black 60%. Dark theme: no extra shadow needed, the black frame does the work |

### The cut-out tab

The tab is a piece of the frame that pushes into the panel, like the tab at the top of the forma reference. **It always sits on the docked edge**, centred along it. It holds the brand and works as the collapse button.

| Property | Top / bottom docks | Left / right docks |
|---|---|---|
| Body size | 116 wide x 32 deep | 30 deep x 92 long |
| Fill | `CardFrame` | `CardFrame` |
| Outer corners (the two corners inside the panel) | radius 18 | radius 18 |
| Fillets where it meets the panel edge | concave, radius 16, on both ends | same |
| Content | `HushMark` 18 + "hush." wordmark, gap 6 | `HushMark` 20 only |

Geometry for the top version (others are the same shape mirrored or rotated): the full shape is 116 + 2 x 16 wide. Start on the panel edge at the far left, run along the edge to the far right, then curve down and in with a quarter circle of radius 16 whose centre sits 16 below the edge at the outer end. That lands you on the tab's side wall. Go down the wall, round the bottom corner with radius 18, along the bottom, round the other corner, up the other wall, and mirror the 16 fillet back to the start. The fillets are what make it read as one cut piece, not a stuck-on badge.

Tap target: the whole tab. Action: collapse.

### Top row

| Element | Spec |
|---|---|
| Model chip | Height 26, capsule, `ChipFill`, horizontal padding 11. Contains a 7 pt orange dot (with orange glow, blur 9 at 85%) and "770NC". Gap 6 |
| Icon buttons | Two circles, 28 x 28, 1 pt `GlassStroke` border, no fill, `IconSettings` and `IconPower` at 14 pt, white. Gap 6 between them |
| Layout | chip on the left, buttons on the right, tab in the middle on top docks |

### Hero (236 tall, side docks 196)

| Layer (back to front) | Spec |
|---|---|
| Dark theme glow | Ellipse 220 x 130 centred at 58% of the hero height, radial `BrandOrange` 42% to 0%, blur 8. This is what lifts the black headphones off the navy |
| Light theme floor shadow | Ellipse 200 x 26 at the very bottom, radial black 45% to 0% |
| Model number | Centred, top aligned 4 above the hero top. See type scale |
| Photo | Centred, bottom aligned, height 206 (side docks 168). Shadow y 22, blur 26, black 55%. Dark theme uses the black photo, light theme the white photo |
| Hotspot | 22 circle, `GlassFill` + 1 pt `GlassStroke`, `IconPlus` 11 pt. At 22% from the left (side docks 14%), 62% from the top. Decorative now, can open a tip later |
| Battery chip | Bottom right, 18 above the hero bottom (side docks 6). See below |

**Battery chip:** padding 11 horizontal and 9 vertical, radius 15, min width 74, `GlassFill` with `GlassStroke` border and a background blur. Stack with 3 spacing: "BATTERY" eyebrow, the "82%" value, then a 4 pt bar (track white 18%, fill `BrandOrange`, radius 2).
Low battery: chip fills solid `BrandOrange` with an orange border, the eyebrow says "CHARGE", the bar track goes black 25% and its fill white, and the chip pulses (section 9).

### Name block

"JBL Tune 770NC" then, 4 below, a row with a 7 pt orange dot and "Connected" (gap 7). Low battery reads "Connected · battery low".

### Mode buttons

Four separate buttons in a row: Off, ANC, Ambient, TalkThru. Reference: `mode-button-states.png`.

| Property | Value |
|---|---|
| Layout | Row, each button equal width, gap 6. Side docks: column, gap 5 |
| Size | Height 52 (side docks 40). Radius 14, continuous |
| Content | Icon 16 above label, gap 5. Side docks: icon left, label, then anything trailing, gap 10, padding 12 |
| Border | 1 pt, inside the button |
| No container | There is no shared track behind the buttons. Each button stands alone |

| State | Fill | Border | Icon | Label |
|---|---|---|---|---|
| **Active** | `BrandOrange` | `ButtonStrokeActive` (white 35%) | white | white, 100% |
| **Available** | `ButtonFill` (white 3%) | `ButtonStroke` (white 14%) | white | white, 72% |
| **Available, hover** | white 8% | `ButtonStrokeHover` (white 28%) | white | white, 100% |
| **Pending** | `ButtonFill` | `BrandOrange` 55% | replaced by the progress ring | white, 100% |
| **Disabled** | none | `ButtonStrokeDisabled` (white 7%) | replaced by a lock + "SOON" row at 55% | white, 38% |

- Disabled, top and bottom docks: the icon slot becomes a small row: `IconLock` at 10 pt (stroke looks bolder at that size, fine) + "SOON", gap 3. Label below as usual.
- Disabled, side docks: `IconLock` 14 pt at 40% in the icon slot, label at 38%, "SOON" pushed to the trailing end at 50%.
- Pending ring: 16 pt circle, 2.2 stroke. Track grey at 30%, progress `BrandOrange` with round caps, starts at 12 o'clock.
- Which modes are disabled: TalkThru on the 770NC ("SOON"). Every mode on the 670NC.
- Not clickable while disabled or while another mode is pending.

### Status line (10 below the buttons)

A 7 pt dot, the mode name in ExtraBold, then the detail. Gap 7.

| Situation | Dot | Text |
|---|---|---|
| Confirmed | solid orange with glow | **ANC** set by headphones |
| Pending | orange ring (1.7 stroke), pulsing | **Ambient** waiting for headphones… |
| Unverified | orange ring, still | **Ambient** (unverified) |
| Timed out | orange ring, still | **ANC** no response, kept current mode |
| 670NC | replaced by a note row | Controls not available for this model yet |

Note row (670NC): padding 9 x 12, radius 14, `GlassFill` with `GlassStroke` border, `IconInfo` 16 + text in white, gap 7.

### Footer

12 below the status. "BLUETOOTH" on the left, "SYNCED" on the right (eyebrow style). "HANDSHAKE" while connecting, "IDLE" when disconnected. On the bottom dock the tab sits between the two words.

---

## 5. Conditions

Reference: `cond-*.png`.

**Connecting**
- Chip: 11 pt orange spinner + "Connecting".
- Hero: photo at 30% and fully desaturated, model number at 35%, no battery chip.
- Sub text: pulsing ring dot + "Connecting…".
- Buttons replaced by four skeleton blocks (same size and radius, no border) that shimmer.
- Status: pulsing ring + "Reading mode from headphones…".
- Nothing is tappable until the first mode report arrives.

**No headphones**
- Chip: "No device".
- Hero: no photo, no number. `HushMark` at 118 (side docks 92), arch white 32%, dot dimmed.
- Name: "No headphones", sub: grey dot + "Last seen: JBL Tune 770NC".
- A short line: "Turn your headphones on and they show up here. First time? Pair them in Bluetooth settings."
- Two buttons in a row (column on side docks), height 40, capsule: **Reconnect** (solid `BrandOrange`, white text, orange glow y 8 blur 20 at 70%) and **Bluetooth Settings** (no fill, 1.5 pt `GlassStroke` border, white text).
- No mode buttons, no status line.

**Low battery** (under 15%)
- Battery chip goes solid orange and pulses (section 4).
- Sub text: "Connected · battery low".
- Mode buttons work as normal.

**670NC**
- Photo and number switch to the 670NC.
- All four mode buttons disabled with SOON.
- Note row instead of the status line.
- Battery still shows.

---

## 6. Edge placement

Reference: `edges-expanded.png`, `edges-collapsed.png` and their `-light` versions.

The pill docks to the **middle** of an edge and can be dragged along it. The card always grows away from the edge, and the tab always faces the edge.

| Edge | Pill | Card position | Card layout |
|---|---|---|---|
| Top (notched) | Fused under the notch, black, 46 x 34 | Top edge 36 below the screen top (just under the notch), centred | 374 wide, buttons in a row, tab on top |
| Top (no notch) | 10 below the menu bar, capsule | Same, under the menu bar | Same |
| Bottom | 12 above the screen bottom, or above the Dock | 12 above the bottom, centred | 374 wide, buttons in a row, tab on the bottom. Content order unchanged |
| Left | Upright 34 x 46, 10 from the edge, vertically centred | 10 from the edge, vertically centred | 296 wide, buttons stacked, tab on the left |
| Right | Mirror of left | Mirror of left | Mirror of left. Text stays left aligned, only the tab and anchor flip |

Clamp the card 8 inside the visible screen frame so it never spills off.

---

## 7. Logo and menu bar

- **Mark:** a thick arch (a headband) over a dot. Draw it on a 32 grid: arch is a half circle centred at (16, 20.5), radius 10.5, stroke 4.6, round caps. Dot centred at (16, 20.5), radius 3.7, `BrandOrange`.
- **Dot states** (menu bar and tab): solid = ANC, ring (radius 2.9, stroke 1.9) = Ambient, no dot = Off, faint dot = no device. Swap `NSStatusItem.button.image` to the matching `MenuBar*` asset when the mode changes. They are template images, so macOS tints them for light and dark menu bars.
- **Wordmark:** "hush." in Fredoka Bold, period in `BrandOrange`.
- **Clear space:** at least the dot's diameter around the mark.
- **Do not** put the mark on orange with an orange dot. On orange use a navy arch with a white dot (`SVG/hush-mark-on-orange.svg`).

---

## 8. Light and dark summary

| | Dark | Light |
|---|---|---|
| Frame and tab | black | white |
| Panel | navy to near black | brighter navy |
| Model number | navy gradient, subtle | solid white |
| Hero photo | black headphones + orange glow | white headphones + floor shadow |
| Pill | black, white headphones | white, black headphones |
| Notch pill | black, white headphones | black, white headphones |
| Chip | translucent white, white text | white, navy text |
| Mode buttons | identical in both (they sit on the navy panel) | |

---

## 9. Motion

Everything springs out and settles quickly back. Orange only moves when the headphones confirm something.

### 9.1 Expand (pill to card)

1. **Window first.** Before the animation starts, grow your panel window to the expanded size so the card has room. The new area is transparent, so nothing visible jumps.
2. **Shape:** the card scales from 0.1 to 1 and fades from 0 to 1, anchored on the docked edge (top centre for top, bottom centre for bottom, leading centre for left, trailing centre for right). It also goes from blur 10 to blur 0.
3. **Spring:** response 0.42, damping 0.78. That gives about 460 ms with a small overshoot of about 3%.
4. **Pill:** fades out and scales to 0.5 at the same time.
5. **Photo flight (optional, recommended):** the headphone photo in the pill and the hero photo share a `matchedGeometryEffect` id, so the small photo flies and grows into the hero. Note the pill shows the opposite color photo for contrast, so in dark mode the white pill photo crossfades into the black hero photo during the flight.
6. **Content stagger:** inside the card, each block fades in and rises 6 pt, ease out 260 ms, with these delays from the start of the expand: top row 80 ms, hero 110 ms, name 140 ms, controls 170 ms.

```swift
// Card container
@Environment(\.accessibilityReduceMotion) private var reduceMotion
@Namespace private var photo

let expand   = Animation.spring(response: 0.42, dampingFraction: 0.78)
let collapse = Animation.spring(response: 0.28, dampingFraction: 1.0)
let reduced  = Animation.easeInOut(duration: 0.16)

ZStack(alignment: edge.alignment) {           // .top, .bottom, .leading, .trailing
    if isExpanded {
        ExpandedCard(...)
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.1, anchor: edge.unitPoint)
                        .combined(with: .opacity),
                    removal: .scale(scale: 0.1, anchor: edge.unitPoint)
                        .combined(with: .opacity)
                )
            )
    } else {
        CollapsedPill(...)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
    }
}

func open()  { withAnimation(reduceMotion ? reduced : expand)  { isExpanded = true } }
func close() { withAnimation(reduceMotion ? reduced : collapse) { isExpanded = false } }
```

Blur on the transition:

```swift
struct BlurModifier: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}
extension AnyTransition {
    static var blurIn: AnyTransition {
        .modifier(active: BlurModifier(radius: 10), identity: BlurModifier(radius: 0))
    }
}
// .combined(with: .blurIn) on the card transition
```

Staggered content:

```swift
struct StaggerIn: ViewModifier {
    let delay: Double
    @State private var shown = false
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 6)
            .onAppear {
                withAnimation(.easeOut(duration: 0.26).delay(delay)) { shown = true }
            }
    }
}
// topRow.modifier(StaggerIn(delay: 0.08))
// hero.modifier(StaggerIn(delay: 0.11))
// name.modifier(StaggerIn(delay: 0.14))
// controls.modifier(StaggerIn(delay: 0.17))
```

Photo flight:

```swift
// in the pill
photoImage.matchedGeometryEffect(id: "headphones", in: photo)
// in the hero
heroImage.matchedGeometryEffect(id: "headphones", in: photo)
```

### 9.2 Collapse (card to pill)

1. Content fades out first, 90 ms, no stagger.
2. The card scales back to 0.1 toward the docked edge, fades and blurs, critically damped spring (response 0.28, damping 1.0), about 280 ms, no overshoot.
3. The pill fades and scales back in from 0.5.
4. **Window last.** Shrink the panel window back to the pill size after the animation finishes (about 300 ms later), never before, or the card gets clipped mid animation.

Triggers: a click anywhere outside the card, the tab, or Esc. For outside clicks, use a global `NSEvent` monitor for left and right mouse down while expanded, and remove it once collapsed.

### 9.3 Choosing a mode

The headphones are the source of truth. The UI never shows a mode as active until they report it.

1. User clicks an **available** button.
2. That button goes **pending** right away: its border turns orange at 55% and its icon becomes the progress ring. The previously active mode **stays orange**. All other buttons stop accepting clicks.
3. The ring fills linearly over exactly 2 s. The status line dot becomes a pulsing ring and reads "Ambient waiting for headphones…".
4. Then one of three things happens:
   - **Headphones confirm** (any time within 2 s): the orange fill moves from the old button to the new one with a spring (response 0.30, damping 0.82). Old button fades to available at the same time. Status: "ANC set by headphones".
   - **Accepted but not echoed back:** same move, but the status reads "Ambient (unverified)" with a hollow ring dot.
   - **No reply after 2 s:** the pending button shakes (see below) and returns to available. The old mode stays orange. Status: "ANC no response, kept current mode".
5. If the headphones change mode on their own (button on the earcup), apply it the same way as a confirmation, with no pending step.

```swift
let modeChange = Animation.spring(response: 0.30, dampingFraction: 0.82)

func select(_ mode: NoiseMode) {
    guard pending == nil, mode != current, isAvailable(mode) else { return }
    pending = mode
    note = .none
    sendToHeadphones(mode)
    timeout?.cancel()
    timeout = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        guard !Task.isCancelled, pending == mode else { return }
        pending = nil
        note = .timedOut
        shakeTrigger += 1
    }
}

// Call this from your Bluetooth layer whenever the headphones report a mode
func headphonesReported(_ mode: NoiseMode, verified: Bool) {
    timeout?.cancel()
    withAnimation(modeChange) {
        current = mode
        pending = nil
        note = verified ? .none : .unverified
    }
}
```

The sliding orange fill: put the orange shape behind the four buttons and give it a `matchedGeometryEffect` so it travels between them:

```swift
@Namespace private var modeFill

ForEach(modes) { m in
    Button { select(m) } label: { ModeLabel(mode: m, state: state(for: m)) }
        .background {
            if m == current {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color("BrandOrange"))
                    .matchedGeometryEffect(id: "fill", in: modeFill)
            }
        }
}
```

Pending ring:

```swift
struct PendingRing: View {
    @State private var progress: CGFloat = 0
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.3), lineWidth: 2.2)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color("BrandOrange"), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
        .onAppear { withAnimation(.linear(duration: 2.0)) { progress = 1 } }
    }
}
```

Pending border pulse: in addition to the static 55% orange border, an extra 1.5 pt orange ring 3 pt outside the button fades between 0% and 60% opacity on a 1.1 s ease in out loop while pending.

Timeout shake: two swings of 4 pt over 240 ms.

```swift
struct Shake: GeometryEffect {
    var travel: CGFloat = 4
    var shakes: CGFloat = 2
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: travel * sin(animatableData * .pi * 2 * shakes), y: 0))
    }
}
// button.modifier(Shake(animatableData: CGFloat(shakeTrigger)))
// withAnimation(.linear(duration: 0.24)) { shakeTrigger += 1 }
```

### 9.4 Small loops

| Element | Motion |
|---|---|
| Pulsing status dot (pending, connecting) | Opacity 0.3 to 1 and back, 1.1 s full cycle, ease in out, repeat forever |
| Connecting spinner (chip and pill) | 11 pt (10 in the pill) ring, 1.7 stroke. Track orange 25%, a 28% arc in full orange. Rotates 360° every 0.8 s, linear, forever |
| Skeleton buttons | Light band sweeps right to left across each block, 1.5 s, ease in out, forever. A simple opacity pulse between white 7% and 16% at 0.75 s is an acceptable substitute |
| Low battery chip | Orange glow ring expands from 0 to 8 pt while fading from 50% to 0%, 1.8 s, forever |
| Low battery pill bar | Opacity 0.3 to 1, 1.2 s cycle, forever |
| Pill hover | Scale to 1.06, spring response 0.32, damping 0.6 |
| Mode button hover | Fill and border fade, 150 to 200 ms ease out |
| Pill idle | Nothing. The pill never animates on its own unless the battery is low or it is connecting |

```swift
// Pulsing dot
@State private var on = false
Circle().strokeBorder(Color("BrandOrange"), lineWidth: 1.7)
    .frame(width: 7, height: 7)
    .opacity(on ? 1 : 0.3)
    .onAppear { withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { on = true } }

// Spinner
@State private var spin = false
Circle().trim(from: 0, to: 0.28)
    .stroke(Color("BrandOrange"), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
    .background(Circle().stroke(Color("BrandOrange").opacity(0.25), lineWidth: 1.7))
    .frame(width: 11, height: 11)
    .rotationEffect(.degrees(spin ? 360 : 0))
    .onAppear { withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) { spin = true } }
```

### 9.5 State changes inside the card

| Change | Motion |
|---|---|
| Connecting to connected | Photo goes from 30% grey to full color, number to full opacity, skeletons crossfade into the real buttons. 300 ms ease out, buttons last |
| Connected to disconnected | Hero crossfades to the large mark, buttons collapse into the two action buttons. Use the collapse spring for any height change |
| Battery value | Number changes with `.contentTransition(.numericText())` on macOS 14, bar width animates 300 ms ease out |
| Battery crossing 15% | Chip color crossfades to orange over 250 ms, then the pulse starts |
| Model switch (770 to 670) | Photo and number crossfade 200 ms. Buttons switch to disabled together |
| Changing dock edge while expanded | Collapse first, move the pill, then expand from the new edge. Never animate the card across the screen |

### 9.6 Reduce Motion

When `accessibilityReduceMotion` is on:

- Expand, collapse and mode changes become a 160 ms ease in out crossfade. No scale, no blur, no overshoot.
- No photo flight, no stagger, no shake.
- Loops stop, except the pending ring fill and the connecting spinner, because they carry information. The pending ring can be replaced with "waiting…" text if you prefer zero motion.

---

## 10. Quick reference

| Token | Value |
|---|---|
| Pill | 46 x 34 (side 34 x 46), radius 17 |
| Card | 374 wide (side 296), frame 7, radius 33, panel radius 27, padding 14 |
| Tab | 116 x 32 (side 30 x 92), corner 18, fillet 16 |
| Hero | 236 tall (side 196), photo 206 (side 168) |
| Mode button | 52 tall (side 40), radius 14, gap 6 (side 5), border 1 |
| Icons | 16 in buttons, 14 in round buttons, 11 in hotspot |
| Expand | spring 0.42 / 0.78, ~460 ms |
| Collapse | spring 0.28 / 1.0, ~280 ms |
| Mode change | spring 0.30 / 0.82 |
| Pending timeout | 2.0 s |
| Stagger | 80 / 110 / 140 / 170 ms, 260 ms fade, 6 pt rise |
| Shake | 2 x 4 pt, 240 ms |
| Reduce Motion | 160 ms crossfade |
| Low battery threshold | under 15% |
