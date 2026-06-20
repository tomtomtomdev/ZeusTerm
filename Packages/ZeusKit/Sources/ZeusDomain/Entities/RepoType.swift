import Foundation

/// What kind of project a repo is — the constellation's clustering dimension (SPEC §7).
/// Types are spatial clusters, not a color scale (git status owns color). `other` is the
/// catch-all for repos that match no marker.
public enum RepoType: String, Sendable, Hashable, CaseIterable {
    case frontend, backend, ios, macos, mobile, scripts, other

    /// Display label shown as the floating cluster title.
    public var displayName: String {
        switch self {
        case .frontend: "Frontend"
        case .backend:  "Backend"
        case .ios:      "iOS"
        case .macos:    "macOS"
        case .mobile:   "Mobile"
        case .scripts:  "Scripts"
        case .other:    "Other"
        }
    }
}
