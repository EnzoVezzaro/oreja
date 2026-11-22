import Foundation

/// The running build's identity, read from the Info.plist that `scripts/build.sh` stamps from git.
/// Nothing here is hard-coded, so the number in Settings always matches the build you launched.
struct AppVersion: Equatable {
    var version: String
    var build: String?
    var commit: String?
    var commitsSinceTag: Int
    var buildDate: String?

    static let current = AppVersion(info: Bundle.main.infoDictionary ?? [:])

    init(info: [String: Any]) {
        version = info["CFBundleShortVersionString"] as? String ?? "Development"
        build = info["CFBundleVersion"] as? String
        commit = info["OrejaGitCommit"] as? String
        commitsSinceTag = Int(info["OrejaCommitsSinceTag"] as? String ?? "") ?? 0
        buildDate = info["OrejaBuildDate"] as? String
    }

    /// True for a build made from commits after the release tag, or from uncommitted changes.
    var isDevelopmentBuild: Bool {
        commitsSinceTag > 0 || commit?.hasSuffix("-modified") == true
    }

    /// "0.4.0" for a release, "0.4.0 · development build 42" otherwise.
    var title: String {
        guard isDevelopmentBuild, let build else { return "Version \(version)" }
        return "Version \(version) · development build \(build)"
    }

    /// Fits the sidebar: "Version 0.4.0", or "0.4.0 · build 42" for a development build.
    var shortTitle: String {
        guard isDevelopmentBuild, let build else { return "Version \(version)" }
        return "\(version) · build \(build)"
    }

    /// Commit and date, for the tooltip and for bug reports.
    var detail: String {
        var parts: [String] = []
        if let build { parts.append("Build \(build)") }
        if let commit { parts.append("commit \(commit)") }
        if commitsSinceTag > 0 { parts.append("\(commitsSinceTag) commit\(commitsSinceTag == 1 ? "" : "s") after \(version)") }
        if let buildDate { parts.append("built \(buildDate)") }
        return parts.joined(separator: " · ")
    }
}
