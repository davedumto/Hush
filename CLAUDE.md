# JBLCompanion: project rules

## What this is
macOS menu bar app for JBL Tune headphones (770NC, 670NC). Floating pill expands into a card. Noise mode status and control run over RFCOMM channel 21 (Airoha RACE protocol). Battery runs over BLE 180F.

## Design sources
- Exact values (colors, sizes, fonts, motion): design/DESIGN_GUIDE.md
- Visual references: design/reference/ (see design/reference/HOW_TO_USE.md for naming and which image goes with which task)
- If an image and the guide disagree, follow the guide.
- Dashed orange outlines, wallpapers, the fake menu bar and "Finder File Edit View" text in the reference images are staging, not UI. Never draw them.
- Use asset catalog names from the guide. No hardcoded hex values.
- Deliberate deviations from the guide (do not "fix" these back): the cut-out tab depth is 18 pt on all docks (guide says 32 top/bottom and 30 side). The confirmed status line reads "<Mode> is currently active" instead of "<Mode> set by headphones". Ambient is labeled "Ambient", not "Ambient Aware". The expanded card height is 500 pt (guide says about 470, which follows content). On left and right docks the mode buttons are a 2x2 grid, not the guide's stacked column. Do not "fix" these back.

## Hard safety rules (never change unless the task explicitly says so)
- Do NOT modify WriteGuard, allowlist contents, the 500ms rate limit, the 2s confirmation timeout, RFCOMMRaceLink, allowsRFCOMMWrites, or any Bluetooth behavior during UI work.
- isModeVerified and eventMapVerified semantics are fixed. Unknown and learned profiles never get a write allowlist.
- Never send bytes to the Charge 4 or any non-matched device.
- No hardware is available to you. Never claim hardware behavior was tested.

## Behavior rules (these override the design guide and images)
- A mode is shown as active only after a 5C status event. A 5B ack alone is never confirmation.
- No status event within the 2s timeout: show "no response, kept current mode" (shake, button returns to available, previous mode stays active). Do not implement the guide's "accepted but not echoed" path.
- "(unverified)" text is driven only by the profile's eventMapVerified (NoiseModeStatusText), never by an ack.
- Mode button enabled/disabled comes only from the profile's isModeVerified flags. No per-model lists in views. A mode with no verified command frame (currently Off on both models, unless the profile says otherwise) shows disabled with SOON, resolved from isModeVerified.
- Model names, photos and model numbers come from the matched profile. Unknown JBL models use the generic mark with no photo.
- The pending ring and shake are driven by NoiseModeRequestCoordinator state and its 2s timeout, not a separate timer.
- Hardware-initiated mode changes apply with no pending step.
- Controls availability and the "Controls not available for this model yet" note row are driven only by the matched profile's flags (supportsNoiseControl, isModeVerified, allowsRFCOMMWrites). Never hardcode per-model behavior in views. Today's per-model state is whatever the profile code says; read the profile files before assuming.
- The panel must never steal focus.
- Keep the Debug-only "Send test frame…" menu item and Copy Diagnostics working.

## Environment notes
- The user's main display is an external 1920x1200 with no notch, in clamshell mode. The non-notched top dock matters most.
- Another notch-style app (Vorssaint) runs alongside. Avoid colliding with it.

## Workflow
- XcodeGen: project.yml is the source of truth. Run xcodegen generate before building.
- Build and test with xcodebuild. All tests must pass before committing.
- Conventional commits. No AI attribution anywhere (commits, PRs, comments). Never put "claude" in a branch name. Do not push.
- Pure logic gets unit tests. Every visual state gets SwiftUI previews in light and dark.
- Final report: files changed, tests, anything not implemented, anything uncertain.
