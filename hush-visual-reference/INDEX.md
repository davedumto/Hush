# hush. visual reference

Screenshots of the approved design for the JBL Tune 770NC / 670NC macOS companion app. Every value (sizes, colors, motion) is in DESIGN_GUIDE.md. When an image and the guide disagree, the guide wins.

All images are rendered at 2x (pill close-ups at 6x).

## Start here
- `00-overview.png` One sheet with the key screens.

## Expanded card (374 pt wide, docked top)
- `01-card-770NC-dark-ANC-active.png` Default state, dark theme. Black frame, navy panel, black headphones with orange glow, ANC active.
- `02-card-770NC-light-ANC-active.png` Same, light theme. White frame, brighter navy panel, white headphones, solid white model number.
- `03-card-670NC-dark-controls-unavailable.png` 670NC: all four modes disabled with SOON, note row "Controls not available for this model yet".
- `04-card-670NC-light-controls-unavailable.png` Same, light.

## Choosing a mode (headphones are the source of truth)
- `05-card-770NC-dark-Ambient-pending.png` User tapped Ambient. Ambient shows the orange progress ring and orange border, ANC stays orange until confirmed. Status: "Ambient waiting for headphones…".
- `06-card-770NC-light-Ambient-pending.png` Same, light.
- `07-card-770NC-dark-Ambient-unverified.png` Command accepted but not echoed back. Ambient is now active, status reads "(unverified)" with a hollow dot.
- `08-card-770NC-light-Ambient-unverified.png` Same, light.
- `09-card-770NC-dark-timed-out-kept-mode.png` User tapped Off, no reply within 2 s. Off returns to available, the previous mode (Ambient) stays orange, status "no response, kept current mode".

## In place under the notch
- `10-in-place-under-notch-expanded-dark-and-light.png` Card hanging from the notch on a desktop, dark and light.
- `11-in-place-under-notch-collapsed-dark-and-light.png` Collapsed: the black pill fused under the notch. The dashed outline is only an annotation showing where the card opens, it is not drawn in the app.

## Identity
- `12-logo-mark-and-wordmark.png` Mark on black, white, orange, and the "hush." wordmark.
- `13-menu-bar-icons-dark.png`, `14-menu-bar-icons-light.png` Menu bar icon per mode: solid dot ANC, ring Ambient, no dot Off, faint dot no device. Sizes 22, 18, 16.

## Collapsed pill (46 x 34)
- `15-collapsed-pill-variants-dark.png`, `16-collapsed-pill-variants-light.png` 770NC, 670NC, connecting, low battery, no device, side dock (34 x 46), notch.
- `17-pill-closeup-<theme>-<variant>.png` 6x close-ups of each pill. Note the photo flips for contrast: white headphones on the black pill, black headphones on the white pill. The notch pill is always black.

## Mode buttons
- `18-mode-button-states-dark.png`, `26-mode-button-states-light.png` Active, available, pending, disabled. Each mode is one standalone button with a thin outline. No shared track behind them.

## Conditions
- `19/27-condition-connecting-*.png` Greyed photo, skeleton buttons, spinner in the chip.
- `20/28-condition-no-headphones-*.png` Large faint mark, Reconnect + Bluetooth Settings buttons, no mode controls.
- `21/29-condition-low-battery-*.png` Battery chip turns solid orange and pulses, "Connected · battery low".

## Edge placement
- `22-edges-expanded-dark.png`, `25-edges-expanded-light.png` Top, bottom, left, right. The cut-out tab always faces the docked edge.
- `23-edges-collapsed-dark.png`, `24-edges-collapsed-light.png` The pill on each edge. Dashed outline = annotation only.
- `30-card-side-dock-vertical-light.png`, `31-card-side-dock-vertical-dark.png` 296 pt card used on left/right docks, buttons stacked, tab on the side.
- `32-card-bottom-dock-dark.png` Bottom dock: tab moves to the bottom edge.

## Motion
- `33-motion-timeline.png` Expand timeline: shape and photo flight, then staggered content (80 / 110 / 140 / 170 ms).
