import Testing
import Foundation
import ZeusDomain
@testable import ZeusUI

/// P3-C.2: the UI-side store that drives the real Hub level. It runs the pure `HubDataLoader`
/// (off-main) and publishes the laid-out `ConstellationHub` the view renders. Tested with stub
/// ports so it stays a fast unit test — no disk, no git.
@MainActor
struct HubDataStoreTests {

    private struct StubScanner: ProjectScanning {
        var repos: [URL]
        var entries: [String: Set<String>]
        func discoverRepositoryURLs(under roots: [URL]) async throws -> [URL] { repos }
        func rootEntryNames(at repo: URL) throws -> Set<String> { entries[repo.path] ?? [] }
    }

    private struct StubGit: GitReading {
        var statuses: [String: GitStatus] = [:]
        func status(at url: URL) async throws -> GitStatus { statuses[url.path] ?? .clean }
        func readRepository(at url: URL) async throws -> Repository { fatalError("unused") }
        func commits(forBranch: String, in repo: URL, limit: Int, skip: Int) async throws -> [Commit] {
            fatalError("unused")
        }
        func diff(forCommit sha: String, in repo: URL) async throws -> CommitDiff { fatalError("unused") }
        func headSHA(at url: URL) async throws -> String? { fatalError("unused") }
    }

    private struct FailingScanner: ProjectScanning {
        func discoverRepositoryURLs(under roots: [URL]) async throws -> [URL] { throw StubError.scanFailed }
        func rootEntryNames(at repo: URL) throws -> Set<String> { [] }
    }

    private enum StubError: Error { case scanFailed }

    private func makeStore() -> HubDataStore {
        let scanner = StubScanner(repos: [URL(fileURLWithPath: "/w/web")],
                                  entries: ["/w/web": ["package.json"]])
        let git = StubGit(statuses: ["/w/web": .dirty])
        return HubDataStore(loader: HubDataLoader(scanner: scanner, git: git), roots: [])
    }

    @Test func hubIsNilBeforeLoad() {
        #expect(makeStore().hub == nil)
    }

    @Test func loadPublishesLaidOutHubFromScannedRepos() async {
        let store = makeStore()
        await store.load()

        let hub = try! #require(store.hub)
        #expect(hub.stars.contains { $0.isHub && $0.name == "All Projects" })
        #expect(hub.stars.contains { $0.name == "web" && $0.status == .dirty && !$0.isHub })
    }

    @Test func loadShowsEmptyHubWhenScanFailsRatherThanSpinningForever() async {
        let store = HubDataStore(
            loader: HubDataLoader(scanner: FailingScanner(), git: StubGit()), roots: [])
        await store.load()

        // A failed scan publishes an empty hub (just the central star) so the scanning
        // indicator clears — never a permanent nil/spinner.
        let hub = try! #require(store.hub)
        #expect(hub.stars.allSatisfy { $0.isHub })
        #expect(hub.stars.count == 1)
    }
}
