#if DEBUG
import SwiftUI

/// Debug-only visual check for Theme's colors/fonts against design/DESIGN_GUIDE.md §1/§2/§8 — a
/// design QA surface, not part of what ships. Not referenced anywhere outside Xcode's canvas.
struct ThemePreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                brandColorSection
                semanticColorSection
                fontSection
                logoSection
                menuBarIconSection
            }
            .padding(24)
        }
        .background(Theme.Semantic.panelBase)
    }

    // MARK: - Colors

    private var brandColorSection: some View {
        sectionBox(title: "Brand") {
            swatchRow([
                ("BrandOrange", Theme.Brand.orange),
                ("BrandNavy", Theme.Brand.navy),
                ("BrandDeepNavy", Theme.Brand.deepNavy),
                ("BrandBlack", Theme.Brand.black),
            ])
        }
    }

    private var semanticColorSection: some View {
        sectionBox(title: "Semantic") {
            VStack(alignment: .leading, spacing: 10) {
                swatchRow([
                    ("CardFrame", Theme.Semantic.cardFrame),
                    ("PanelHighlight", Theme.Semantic.panelHighlight),
                    ("PanelBase", Theme.Semantic.panelBase),
                    ("PanelEdge", Theme.Semantic.panelEdge),
                ])
                swatchRow([
                    ("TextPrimary", Theme.Semantic.textPrimary),
                    ("TextSecondary", Theme.Semantic.textSecondary),
                    ("GlassFill", Theme.Semantic.glassFill),
                    ("GlassStroke", Theme.Semantic.glassStroke),
                ])
                swatchRow([
                    ("ButtonFill", Theme.Semantic.buttonFill),
                    ("ButtonStroke", Theme.Semantic.buttonStroke),
                    ("ButtonStrokeHover", Theme.Semantic.buttonStrokeHover),
                    ("ButtonStrokeActive", Theme.Semantic.buttonStrokeActive),
                ])
                swatchRow([
                    ("ButtonStrokeDisabled", Theme.Semantic.buttonStrokeDisabled),
                    ("ModelNumberTop", Theme.Semantic.modelNumberTop),
                    ("ModelNumberBottom", Theme.Semantic.modelNumberBottom),
                    ("PillBackground", Theme.Semantic.pillBackground),
                ])
                swatchRow([
                    ("PillInk", Theme.Semantic.pillInk),
                    ("ChipFill", Theme.Semantic.chipFill),
                    ("ChipInk", Theme.Semantic.chipInk),
                ])
            }
        }
    }

    private func swatchRow(_ items: [(String, Color)]) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(items, id: \.0) { name, color in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(color)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15))
                        )
                        .frame(width: 64, height: 44)
                    Text(name)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(width: 70)
                }
            }
        }
    }

    // MARK: - Fonts

    private var fontSection: some View {
        sectionBox(title: "Type scale (§2)") {
            VStack(alignment: .leading, spacing: 10) {
                fontRow("Model number", Theme.Fonts.modelNumber(), sample: "770")
                fontRow("Device name", Theme.Fonts.deviceName, sample: "JBL Tune 770NC")
                fontRow("Battery value", Theme.Fonts.batteryValue, sample: "82%")
                fontRow("Tab wordmark", Theme.Fonts.tabWordmark, sample: "hush.")
                fontRow("Mode label", Theme.Fonts.modeLabel(), sample: "ANC")
                fontRow("Sub text", Theme.Fonts.subText, sample: "Connected")
                fontRow("Status mode name", Theme.Fonts.statusModeName, sample: "ANC")
                fontRow("Status detail", Theme.Fonts.statusDetail, sample: "is currently active")
                fontRow("Model chip", Theme.Fonts.modelChip, sample: "770NC")
                fontRow("Eyebrow", Theme.Fonts.eyebrow, sample: "BATTERY")
                fontRow("SOON tag", Theme.Fonts.soonTag(), sample: "SOON")
            }
        }
    }

    private func fontRow(_ label: String, _ font: Font, sample: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 120, alignment: .leading)
            Text(sample)
                .font(font)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Logo

    private var logoSection: some View {
        sectionBox(title: "Logo (§7)") {
            HStack(alignment: .center, spacing: 28) {
                labeledImage("HushMark", height: 40)
                labeledImage("HushWordmark", height: 24)
                labeledImage("HushLockup", height: 40)
            }
        }
    }

    // MARK: - Menu bar icons

    private var menuBarIconSection: some View {
        sectionBox(title: "Menu bar icons (§7)") {
            HStack(spacing: 24) {
                labeledImage("MenuBarANC", height: 18)
                labeledImage("MenuBarAmbient", height: 18)
                labeledImage("MenuBarOff", height: 18)
                labeledImage("MenuBarNoDevice", height: 18)
            }
        }
    }

    private func labeledImage(_ name: String, height: CGFloat) -> some View {
        VStack(spacing: 6) {
            Image(name)
                .resizable()
                .renderingMode(.original)
                .aspectRatio(contentMode: .fit)
                .frame(height: height)
                .foregroundStyle(.white)
            Text(name)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    // MARK: - Section chrome

    private func sectionBox<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.5))
            content()
        }
        .padding(16)
        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview("Theme - Light") {
    ThemePreview()
        .frame(width: 560, height: 900)
        .preferredColorScheme(.light)
}

#Preview("Theme - Dark") {
    ThemePreview()
        .frame(width: 560, height: 900)
        .preferredColorScheme(.dark)
}
#endif
