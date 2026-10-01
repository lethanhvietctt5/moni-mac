import Darwin
import Foundation
import MoniMacCore

/// Whether Projects may look inside folders macOS guards with a privacy prompt (Documents, Desktop,
/// Downloads, iCloud Drive, other volumes).
///
/// Finding a project root means checking for `.git` and manifests, and inside those folders the
/// first check makes macOS ask for access. So it waits until the Projects tab is first shown, where
/// the prompt makes sense, rather than appearing at a random moment after launch. Until then, and
/// if access is denied, a server there is grouped by its working directory, with no branch.
public enum ProjectFolderAccess {
    static let key = "projects.protectedFoldersAllowed"

    /// Called when the Projects tab appears. Remembered across launches.
    public static func allow() {
        UserDefaults.standard.set(true, forKey: key)
    }

    static var isAllowed: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    /// Whether reading under `path` can raise a privacy prompt.
    static func isProtected(_ path: String, home: String) -> Bool {
        if path.hasPrefix("/Volumes/") { return true }
        let guarded = ["Documents", "Desktop", "Downloads", "Library/Mobile Documents", "Pictures", "Movies", "Music"]
        return guarded.contains { path == "\(home)/\($0)" || path.hasPrefix("\(home)/\($0)/") }
    }
}

/// Finds the project a working directory belongs to: the nearest enclosing folder with a git
/// repository or a package manifest, and the branch of the enclosing git repository.
///
/// Folder lookups are cached; only the branch (one small file) is re-read on each refresh.
final class ProjectRootResolver {
    static let markers = [
        ".git", "package.json", "pyproject.toml", "Cargo.toml", "go.mod", "Gemfile", "composer.json", "mix.exs",
        "Package.swift", "pom.xml", "build.gradle", "build.gradle.kts", "deno.json", "setup.py", "requirements.txt",
    ]

    private struct Entry {
        var root: String
        /// The enclosing repository's git directory, for the branch.
        var gitDirectory: String?
    }

    private let home: String
    private let ttl: TimeInterval
    private let allowProtected: () -> Bool
    private var cache: [String: (entry: Entry?, at: Date)] = [:]

    init(home: String = NSHomeDirectory(), ttl: TimeInterval = 600, allowProtected: @escaping () -> Bool = { ProjectFolderAccess.isAllowed }) {
        self.home = home
        self.ttl = ttl
        self.allowProtected = allowProtected
    }

    /// The project for `cwd`, or nil when it isn't inside one (e.g. "/", the home folder itself,
    /// or a folder with no markers up to the home folder).
    func project(for cwd: String, now: Date = Date()) -> ProjectRoot? {
        guard cwd != "/", cwd != home, !cwd.isEmpty else { return nil }
        if ProjectFolderAccess.isProtected(cwd, home: home), !allowProtected() {
            return ProjectRoot(path: cwd)
        }
        let entry: Entry?
        if let cached = cache[cwd], now.timeIntervalSince(cached.at) < ttl {
            entry = cached.entry
        } else {
            entry = resolve(cwd)
            cache[cwd] = (entry, now)
        }
        guard let entry else { return nil }
        return ProjectRoot(path: entry.root, branch: entry.gitDirectory.flatMap(Self.branch(gitDirectory:)))
    }

    /// Drops expired folders, so the cache doesn't grow without bound.
    func prune(now: Date = Date()) {
        cache = cache.filter { now.timeIntervalSince($0.value.at) < ttl }
    }

    private func resolve(_ cwd: String) -> Entry? {
        var root: String?
        var gitDirectory: String?
        var directory = cwd
        // Stop below the home folder and "/": neither is a project, even with a dotfiles repo.
        while directory != home, directory != "/", !directory.isEmpty {
            if root == nil, Self.markers.contains(where: { exists("\(directory)/\($0)") }) { root = directory }
            if gitDirectory == nil, exists("\(directory)/.git") {
                gitDirectory = Self.gitDirectory(at: "\(directory)/.git")
                break
            }
            directory = (directory as NSString).deletingLastPathComponent
        }
        return root.map { Entry(root: $0, gitDirectory: gitDirectory) }
    }

    private func exists(_ path: String) -> Bool {
        access(path, F_OK) == 0
    }

    /// `.git` is a directory, or for worktrees and submodules a file naming one ("gitdir: …").
    static func gitDirectory(at path: String) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        if isDirectory.boolValue { return path }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let line = text.split(separator: "\n").first, line.hasPrefix("gitdir:") else { return nil }
        let target = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        return target.hasPrefix("/") ? target : ((path as NSString).deletingLastPathComponent as NSString)
            .appendingPathComponent(target)
    }

    /// The checked-out branch, or nil when HEAD is detached.
    static func branch(gitDirectory: String) -> String? {
        guard let head = try? String(contentsOfFile: "\(gitDirectory)/HEAD", encoding: .utf8) else { return nil }
        return branch(head: head)
    }

    static func branch(head: String) -> String? {
        let line = head.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "ref: refs/heads/"
        return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : nil
    }
}
