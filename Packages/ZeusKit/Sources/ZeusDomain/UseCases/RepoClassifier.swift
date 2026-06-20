import Foundation

/// Pure use case: decides a repo's `RepoType` from the entry names found at its root.
/// The scanner does the I/O (lists the root directory); this stays pure and testable.
public struct RepoClassifier: Sendable {
    public init() {}

    public func classify(rootEntries: Set<String>, name: String) -> RepoType {
        func has(_ entry: String) -> Bool { rootEntries.contains(entry) }
        func hasSuffix(_ suffix: String) -> Bool { rootEntries.contains { $0.hasSuffix(suffix) } }

        // Precedence (first match wins). Mobile and Apple-app markers are the most specific, so
        // they're checked before the broader Package.swift / package.json signals.
        if has("pubspec.yaml") { return .mobile }                          // Flutter
        // React Native: a package.json plus native android/+ios/ dirs (Xcode project nested
        // under ios/, so no root *.xcodeproj) or a Metro bundler config → a mobile app, not web.
        if has("package.json"), (has("android") && has("ios")) || has("metro.config.js") {
            return .mobile
        }
        if hasSuffix(".xcodeproj") || hasSuffix(".xcworkspace") { return .ios }  // app project
        if has("Package.swift") { return .macos }                          // SPM tool/lib
        if has("package.json") { return .frontend }                        // JS/TS web
        if Self.backendMarkers.contains(where: has) { return .backend }
        if hasSuffix(".sh") || name == "dotfiles" { return .scripts }
        return .other
    }

    /// Build-tool / dependency manifests that signal a backend service.
    private static let backendMarkers: Set<String> = [
        "go.mod", "Cargo.toml", "requirements.txt", "Pipfile", "pyproject.toml",
        "pom.xml", "build.gradle", "Gemfile", "composer.json",
    ]
}
