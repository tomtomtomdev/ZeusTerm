import Testing
import ZeusDomain
@testable import ZeusUI

struct ThemeTests {
    @Test func darkSurfaceTokensMatchSpec() {
        let t = Theme.dark
        #expect(t.appBackgroundHex == "#0A0B10")
        #expect(t.railHex == "#0C0E13")
        #expect(t.panelHex == "#080A0E")
        #expect(t.controlHex == "#14171F")
        #expect(t.accentSoftHex == "#2A3350")
        #expect(t.textHiHex == "#E7EAF2")
        #expect(t.textMidHex == "#9AA3B8")
        #expect(t.textDimHex == "#646C80")
        #expect(t.goldHex == "#F5C451")
    }

    @Test func lightSurfaceTokensMatchStaticFrame() {
        let t = Theme.light
        #expect(t.appBackgroundHex == "#F6F7FB")
        #expect(t.railHex == "#FFFFFF")
        #expect(t.controlHex == "#F1F3F7")
        #expect(t.textHiHex == "#1A1D24")
        #expect(t.textMidHex == "#4B5563")
        #expect(t.textDimHex == "#9AA1AD")
        #expect(t.goldHex == "#E0A21A")
    }

    @Test func toggleSwapsMode() {
        #expect(Theme.dark.toggled == .light)
        #expect(Theme.light.toggled == .dark)
    }

    /// The UI token table bridges to the pure domain `ThemeMode` persisted in ZeusSettings (P7-D).
    @Test func bridgesToAndFromTheDomainThemeMode() {
        #expect(Theme(mode: .dark) == .dark)
        #expect(Theme(mode: .light) == .light)
        #expect(Theme.dark.mode == ThemeMode.dark)
        #expect(Theme.light.mode == ThemeMode.light)
    }

    @Test func gitStatusIsTheSemanticColorScale() {
        #expect(Theme.dark.statusHex(.clean) == "#35D08B")
        #expect(Theme.dark.statusHex(.dirty) == "#F5A623")
        #expect(Theme.dark.statusHex(.ahead) == "#6E8BFF")
        #expect(Theme.dark.statusHex(.behind) == "#FF6B6B")
        #expect(Theme.dark.statusHex(.untracked) == "#8B93A7")
        // Light theme darkens the scale for contrast on light surfaces (static frame ③).
        #expect(Theme.light.statusHex(.clean) == "#1FA971")
        #expect(Theme.light.statusHex(.behind) == "#E0524F")
    }

    @Test func everyStatusHasANonEmptyTokenInBothThemes() {
        for theme in Theme.allCases {
            for status in GitStatus.allCases {
                #expect(theme.statusHex(status).hasPrefix("#"))
            }
        }
    }

    // Differentiate Without Color (WCAG 1.4.1): status is color-only on the map, so each status also
    // maps to a shape-distinct SF Symbol drawn on nodes when the accessibility setting is on.
    @Test func everyStatusHasADistinctGlyphSymbol() {
        let symbols = GitStatus.allCases.map(Theme.statusSymbol)
        #expect(symbols == ["checkmark", "pencil", "arrow.up", "arrow.down", "questionmark"])
        #expect(Set(symbols).count == GitStatus.allCases.count)   // all distinct
    }

    // The constellation map's line + label hues (Design/HANDOFF "Layout & motion algorithms":
    // lines rgba(150,170,255,·), cluster labels #CFD5E6, repo labels rgba(180,190,215,·),
    // planet labels #AEB6C8). Previously scattered as grey `textDim` literals in the view; promoted
    // into the Theme token table (the canonical, testable form) so they match spec exactly.
    @Test func constellationPaletteMatchesSpecDark() {
        let t = Theme.dark
        #expect(t.constellationLineHex == "#96AAFF")   // rgba(150,170,255)
        #expect(t.clusterLabelHex == "#CFD5E6")
        #expect(t.repoLabelHex == "#B4BED7")           // rgba(180,190,215), drawn at 62% opacity
        #expect(t.orbitLabelHex == "#AEB6C8")
    }

    @Test func constellationPaletteIsDefinedInBothThemes() {
        for theme in Theme.allCases {
            #expect(theme.constellationLineHex.hasPrefix("#"))
            #expect(theme.clusterLabelHex.hasPrefix("#"))
            #expect(theme.repoLabelHex.hasPrefix("#"))
            #expect(theme.orbitLabelHex.hasPrefix("#"))
        }
    }

    // Borders are translucent white over the dark surfaces, not the opaque `accentSoft` fill they
    // used to borrow (Design/HANDOFF "Color — dark theme": border/hairline rgba(255,255,255,0.06),
    // border/control rgba(255,255,255,0.07–0.08)). 0.06·255≈0x0F, 0.08·255≈0x14 (8-digit #RRGGBBAA).
    @Test func hairlineAndControlBordersAreTranslucentWhiteInDark() {
        let t = Theme.dark
        #expect(t.hairlineHex == "#FFFFFF0F")       // section dividers, white 6%
        #expect(t.controlBorderHex == "#FFFFFF14")  // control borders, white 8%
    }

    @Test func hairlineAndControlBordersAreDefinedInBothThemes() {
        for theme in Theme.allCases {
            #expect(theme.hairlineHex.hasPrefix("#"))
            #expect(theme.controlBorderHex.hasPrefix("#"))
        }
    }

    // Per-line diff coloring (Design/HANDOFF "Color — diff / file status"): added text #7BD4A8 over a
    // 10% green tint, deleted text #FF9D9D over a 10% red tint, context #AEB6C8, hunk header #646C80,
    // file header #7C8597. Promoted from a single flat `textMid` blob into testable tokens.
    @Test func diffPaletteMatchesSpecDark() {
        let t = Theme.dark
        #expect(t.diffAddTextHex == "#7BD4A8")
        #expect(t.diffAddBgHex == "#35D08B1A")    // rgba(53,208,139,0.10)
        #expect(t.diffDelTextHex == "#FF9D9D")
        #expect(t.diffDelBgHex == "#FF6B6B1A")     // rgba(255,107,107,0.10)
        #expect(t.diffContextHex == "#AEB6C8")
        #expect(t.diffHunkHex == "#646C80")
        #expect(t.diffFileHeaderHex == "#7C8597")
    }

    @Test func diffPaletteIsDefinedInBothThemes() {
        for theme in Theme.allCases {
            #expect(theme.diffAddTextHex.hasPrefix("#"))
            #expect(theme.diffAddBgHex.hasPrefix("#"))
            #expect(theme.diffDelTextHex.hasPrefix("#"))
            #expect(theme.diffDelBgHex.hasPrefix("#"))
            #expect(theme.diffContextHex.hasPrefix("#"))
            #expect(theme.diffHunkHex.hasPrefix("#"))
            #expect(theme.diffFileHeaderHex.hasPrefix("#"))
        }
    }

    @Test func branchLanesAreColoredByName() {
        #expect(Theme.laneHex(forBranch: "main") == "#F5C451")        // Zeus gold
        #expect(Theme.laneHex(forBranch: "develop") == "#6E8BFF")
        #expect(Theme.laneHex(forBranch: "feature/oauth-pkce") == "#B98BFF")
        #expect(Theme.laneHex(forBranch: "fix/cache-ttl") == "#57E0FF")
        #expect(Theme.laneHex(forBranch: "auth") == "#B98BFF")        // sample-data lane alias
        #expect(Theme.laneHex(forBranch: "cache") == "#57E0FF")
    }
}
