import SwiftUI

/// Color and Font helpers wrapping the asset catalog names and type scale from
/// design/DESIGN_GUIDE.md §1/§2 — views reach for `Theme.*`, never a hardcoded hex value or a
/// bare `Color("...")`/`Font.custom("...")` call, so the catalog stays the single source of truth
/// and a renamed/retired asset fails to compile here instead of silently misrendering in a view.
enum Theme {
    /// design/DESIGN_GUIDE.md §1, Colors / Brand — identical in light and dark.
    enum Brand {
        static let orange = Color("BrandOrange")
        static let navy = Color("BrandNavy")
        static let deepNavy = Color("BrandDeepNavy")
        static let black = Color("BrandBlack")
    }

    /// design/DESIGN_GUIDE.md §1, Colors / Semantic — each resolves differently per appearance;
    /// the catalog (not this file) owns the light/dark values.
    enum Semantic {
        static let cardFrame = Color("CardFrame")
        static let panelHighlight = Color("PanelHighlight")
        static let panelBase = Color("PanelBase")
        static let panelEdge = Color("PanelEdge")
        static let textPrimary = Color("TextPrimary")
        static let textSecondary = Color("TextSecondary")
        static let glassFill = Color("GlassFill")
        static let glassStroke = Color("GlassStroke")
        static let buttonFill = Color("ButtonFill")
        static let buttonStroke = Color("ButtonStroke")
        static let buttonStrokeHover = Color("ButtonStrokeHover")
        static let buttonStrokeActive = Color("ButtonStrokeActive")
        static let buttonStrokeDisabled = Color("ButtonStrokeDisabled")
        static let modelNumberTop = Color("ModelNumberTop")
        static let modelNumberBottom = Color("ModelNumberBottom")
        static let pillBackground = Color("PillBackground")
        static let pillInk = Color("PillInk")
        static let chipFill = Color("ChipFill")
        static let chipInk = Color("ChipInk")
    }

    /// design/DESIGN_GUIDE.md §2 type scale. PostScript names match RequiredFonts exactly —
    /// AppDelegate.verifyRequiredFonts warns at launch if any of them failed to register, in which
    /// case SwiftUI silently falls back to the system font rather than crashing.
    enum Fonts {
        static func modelNumber(sideDock: Bool = false) -> Font {
            .custom("Fredoka-Bold", size: sideDock ? 112 : 150)
        }
        static let deviceName = Font.custom("Fredoka-SemiBold", size: 19)
        static let batteryValue = Font.custom("Fredoka-SemiBold", size: 19)
        static let tabWordmark = Font.custom("Fredoka-Bold", size: 16)
        static func modeLabel(sideDock: Bool = false) -> Font {
            .custom("Nunito-Bold", size: sideDock ? 12 : 11)
        }
        static let subText = Font.custom("Nunito-SemiBold", size: 12.5)
        static let statusModeName = Font.custom("Nunito-ExtraBold", size: 12)
        static let statusDetail = Font.custom("Nunito-SemiBold", size: 12)
        static let modelChip = Font.custom("Nunito-ExtraBold", size: 11.5)
        static let eyebrow = Font.custom("Nunito-ExtraBold", size: 9.5)
        static func soonTag(sideDock: Bool = false) -> Font {
            .custom("Nunito-ExtraBold", size: sideDock ? 9 : 8.5)
        }
    }
}
