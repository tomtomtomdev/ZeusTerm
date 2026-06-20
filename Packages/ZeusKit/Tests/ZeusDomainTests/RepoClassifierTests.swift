import Testing
@testable import ZeusDomain

/// P3-A: classifying a repo into a constellation cluster type from the entry names found at
/// its root (the scanner gathers those names; this decision stays pure). Marker-file driven
/// per the chosen approach — Package.swift/*.xcodeproj → Apple, package.json → Frontend, etc.
struct RepoClassifierTests {

    @Test func unknownRootClassifiesAsOther() {
        #expect(RepoClassifier().classify(rootEntries: [], name: "mystery") == .other)
    }

    @Test func packageJsonIsFrontend() {
        #expect(RepoClassifier().classify(rootEntries: ["package.json", "src"], name: "web") == .frontend)
    }

    @Test(arguments: ["go.mod", "Cargo.toml", "requirements.txt", "pom.xml", "Gemfile"])
    func backendMarkersAreBackend(_ marker: String) {
        #expect(RepoClassifier().classify(rootEntries: [marker], name: "svc") == .backend)
    }

    @Test func xcodeprojIsIOS() {
        #expect(RepoClassifier().classify(rootEntries: ["MyApp.xcodeproj", "MyApp"], name: "MyApp") == .ios)
    }

    @Test func packageSwiftWithoutXcodeprojIsMacOS() {
        #expect(RepoClassifier().classify(rootEntries: ["Package.swift", "Sources"], name: "tool") == .macos)
    }

    @Test func pubspecIsMobile() {
        #expect(RepoClassifier().classify(rootEntries: ["pubspec.yaml", "lib"], name: "app") == .mobile)
    }

    @Test func shellScriptsAreScripts() {
        #expect(RepoClassifier().classify(rootEntries: ["deploy.sh"], name: "deploy-kit") == .scripts)
    }

    @Test func dotfilesByNameAreScripts() {
        #expect(RepoClassifier().classify(rootEntries: [".zshrc", ".gitconfig"], name: "dotfiles") == .scripts)
    }

    // Precedence: an Xcode app that also vends SPM deps is still an app (iOS wins over the
    // Package.swift→macOS rule); a Flutter app (pubspec) wins over a stray package.json.
    @Test func xcodeprojWinsOverPackageSwift() {
        #expect(RepoClassifier().classify(rootEntries: ["Package.swift", "App.xcodeproj"], name: "App") == .ios)
    }

    // React Native ships a package.json alongside native android/ + ios/ dirs (the Xcode project
    // is nested under ios/, so there's no root *.xcodeproj). That's a mobile app, not web.
    @Test func reactNativeWithNativeDirsIsMobile() {
        #expect(RepoClassifier().classify(
            rootEntries: ["package.json", "android", "ios", "App.tsx"], name: "app") == .mobile)
    }

    @Test func metroConfigMakesPackageJsonMobile() {
        #expect(RepoClassifier().classify(
            rootEntries: ["package.json", "metro.config.js"], name: "app") == .mobile)
    }

    @Test func pubspecWinsOverPackageJson() {
        #expect(RepoClassifier().classify(rootEntries: ["pubspec.yaml", "package.json"], name: "x") == .mobile)
    }
}
