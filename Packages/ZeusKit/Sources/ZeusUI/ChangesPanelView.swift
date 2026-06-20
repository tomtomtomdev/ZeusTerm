import SwiftUI
import ZeusDomain

/// The bottom panel for the branch-tree level (SPEC §7, View 3): a header (status dot · hash ·
/// message · author·time, plus a ● HEAD badge or a Checkout button) over a split of the changed
/// files list and a unified-diff preview. Replaces the terminal while exploring commits.
struct ChangesPanelView: View {
    let commit: CommitNode?          // the selected commit (nil before anything is picked)
    let diff: CommitDiff
    let isHead: Bool
    let theme: Theme
    let onCheckout: (String) -> Void

    /// The changed-files list takes ~46% of the panel width; the diff preview takes the rest.
    private static let filesColumnFraction = 0.46

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.accentSoft)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    changedFiles
                        .frame(width: geo.size.width * Self.filesColumnFraction, alignment: .leading)
                    Divider().overlay(theme.accentSoft)
                    diffPreview.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(theme.panel)
        .foregroundStyle(theme.textHi)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(commit.map { Theme.laneColor(forBranch: $0.branch) } ?? theme.textDim)
                .frame(width: 8, height: 8)
            Text(commit?.id ?? "—")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Text(commit?.summary ?? "No commit selected")
                .font(.system(size: 12))
                .foregroundStyle(theme.textMid)
                .lineLimit(1)
            Spacer()
            Text("you · just now")
                .font(.system(size: 11))
                .foregroundStyle(theme.textDim)
            headBadgeOrCheckout
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    @ViewBuilder private var headBadgeOrCheckout: some View {
        if let commit {
            if isHead {
                Label("HEAD", systemImage: "circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(theme.gold.opacity(0.18), in: Capsule())
                    .foregroundStyle(theme.gold)
            } else {
                Button("Checkout") { onCheckout(commit.id) }
                    .font(.system(size: 11, weight: .semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(theme.gold)
            }
        }
    }

    // MARK: Changed files

    private var changedFiles: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CHANGED FILES · \(diff.files.count)")
                .font(.system(size: 10, weight: .semibold)).tracking(1)
                .foregroundStyle(theme.textDim)
                .padding(.horizontal, 14).padding(.vertical, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(diff.files) { file in fileRow(file) }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    private func fileRow(_ file: FileChange) -> some View {
        HStack(spacing: 8) {
            Text(statusLetter(file.status))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(statusColor(file.status))
                .frame(width: 12)
            Text(file.path)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 6)
            Text("+\(file.additions)").font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.statusColor(.clean))
            Text("-\(file.deletions)").font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.statusColor(.behind))
        }
        .padding(.horizontal, 6).padding(.vertical, 4)
    }

    // MARK: Diff preview

    private var diffPreview: some View {
        ScrollView {
            Text(diff.patch.isEmpty ? "No changes." : diff.patch)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(theme.textMid)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    private func statusLetter(_ status: FileStatus) -> String {
        switch status {
        case .added:    return "A"
        case .modified: return "M"
        case .deleted:  return "D"
        }
    }

    private func statusColor(_ status: FileStatus) -> Color {
        switch status {
        case .added:    return theme.statusColor(.clean)
        case .modified: return theme.statusColor(.dirty)
        case .deleted:  return theme.statusColor(.behind)
        }
    }
}
