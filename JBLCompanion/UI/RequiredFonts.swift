import Foundation

/// The exact PostScript names design/DESIGN_GUIDE.md §2 requires to be resolvable at runtime
/// (Fredoka for the giant model number/device name/wordmark, Nunito for everything else). The TTFs
/// themselves ship under JBLCompanion/Fonts and are registered process-wide via the
/// ATSApplicationFontsPath Info.plist key (project.yml) — nothing in code performs the
/// registration itself, only the verification below.
enum RequiredFonts {
    static let postScriptNames = [
        "Fredoka-Bold", "Fredoka-SemiBold", "Fredoka-Medium",
        "Nunito-ExtraBold", "Nunito-Bold", "Nunito-SemiBold", "Nunito-Medium",
    ]

    /// Returns the subset of `postScriptNames` that don't resolve, so a caller (AppDelegate) can
    /// log a warning for each. Pure and testable with a fake resolver — doesn't need the real
    /// fonts actually installed to verify the filtering logic itself.
    static func unresolved(resolves: (String) -> Bool) -> [String] {
        postScriptNames.filter { !resolves($0) }
    }
}
