import Foundation

/// The only semantic color scale in the UI — drives constellation node fill (SPEC §7).
/// Presentation maps each case to a token hex; the domain stays color-free.
public enum GitStatus: String, Sendable, Hashable, CaseIterable {
    case clean, dirty, ahead, behind, untracked
}
