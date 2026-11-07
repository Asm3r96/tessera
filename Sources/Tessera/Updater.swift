import AppKit
import Foundation
import Security
import TesseraCore

/// Checks GitHub Releases for a newer version and installs it when the user asks.
/// Source builds skip all of this: their version is not a release version, and they update with git pull.
final class Updater: ObservableObject {
    static let shared = Updater()

    @Published private(set) var available: Release?
    @Published private(set) var installing = false
    @Published private(set) var failure: String?
    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Keys.enabled)
            if enabled { check() } else { available = nil }
        }
    }

    let current = Version(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
    var isRelease: Bool { current != nil }

    private static let latest = URL(string: "https://api.github.com/repos/Asm3r96/tessera/releases/latest")!
    private static let interval: TimeInterval = 24 * 60 * 60
    private let session = URLSession(configuration: .ephemeral)
    private var timer: Timer?

    private enum Keys {
        static let enabled = "checkForUpdates"
        static let lastCheck = "lastUpdateCheck"
    }

    private init() {
        enabled = UserDefaults.standard.object(forKey: Keys.enabled) as? Bool ?? true
    }

    func start() {
        guard isRelease else { return }
        // Check shortly after launch, then once a day. The hourly timer survives sleep better than a 24-hour timer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            guard let self else { return }
            let last = UserDefaults.standard.object(forKey: Keys.lastCheck) as? Date ?? .distantPast
            if Date().timeIntervalSince(last) >= Self.interval { self.check() }
        }
    }

    /// Asks GitHub for the latest release. Sends no data about the user.
    func check() {
        guard enabled, let current, !installing else { return }
        UserDefaults.standard.set(Date(), forKey: Keys.lastCheck)
        var request = URLRequest(url: Self.latest)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Tessera/\(current)", forHTTPHeaderField: "User-Agent")
        session.dataTask(with: request) { [weak self] data, response, _ in
            guard let data, (response as? HTTPURLResponse)?.statusCode == 200,
                  let release = Release.parse(data) else { return }
            DispatchQueue.main.async {
                guard let self, self.enabled else { return }
                self.available = release.version > current ? release : nil
            }
        }.resume()
    }

    /// Downloads the release, checks its signature, then replaces this app and starts the new one.
    func install() {
        guard let release = available, !installing else { return }
        let destination = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path) else {
            NSWorkspace.shared.open(release.page)
            return
        }
        installing = true
        failure = nil
        session.downloadTask(with: release.download) { [weak self] file, response, error in
            // The downloaded file is deleted when this closure returns, so unpack it here.
            let result = Result { try Self.unpack(file, response, error, expecting: release.version) }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success(let folder):
                    self.relaunch(destination, from: folder)
                case .failure(let error):
                    NSLog("Tessera: update failed: \(error)")
                    self.installing = false
                    self.failure = "The update failed. Try again later, or run the install command."
                }
            }
        }.resume()
    }

    private func relaunch(_ destination: URL, from folder: URL) {
        // Waits until Tessera quits, swaps the app, and starts the new one. On any error it restores the old app.
        let script = """
        while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
        rm -rf "$2.old"
        if mv "$2" "$2.old"; then
          if /usr/bin/ditto "$3/Tessera.app" "$2"; then rm -rf "$2.old"; else rm -rf "$2"; mv "$2.old" "$2"; fi
        fi
        rm -rf "$3"
        /usr/bin/open "$2"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "tessera-update", String(getpid()), destination.path, folder.path]
        do {
            try process.run()
        } catch {
            installing = false
            failure = "The update failed. Try again later, or run the install command."
            try? FileManager.default.removeItem(at: folder)
            return
        }
        NSApp.terminate(nil)
    }

    private static func unpack(_ file: URL?, _ response: URLResponse?, _ error: Error?, expecting version: Version) throws -> URL {
        if let error { throw error }
        guard let file, (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.download }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TesseraUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let zip = folder.appendingPathComponent("Tessera.zip")
            try FileManager.default.moveItem(at: file, to: zip)
            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-x", "-k", zip.path, folder.path]
            try ditto.run()
            ditto.waitUntilExit()
            guard ditto.terminationStatus == 0 else { throw UpdateError.unpack }
            try FileManager.default.removeItem(at: zip)
            let app = folder.appendingPathComponent("Tessera.app")
            guard let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                  let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  Version(shortVersion) == version else { throw UpdateError.contents }
            try verifySignature(app)
            return folder
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// The new app must meet this app's designated requirement: the same identifier and the same signing certificate.
    /// This also keeps the Accessibility permission valid after the update.
    private static func verifySignature(_ app: URL) throws {
        var running: SecCode?
        var runningStatic: SecStaticCode?
        var requirement: SecRequirement?
        var candidate: SecStaticCode?
        guard SecCodeCopySelf([], &running) == errSecSuccess, let running,
              SecCodeCopyStaticCode(running, [], &runningStatic) == errSecSuccess, let runningStatic,
              SecCodeCopyDesignatedRequirement(runningStatic, [], &requirement) == errSecSuccess, let requirement,
              SecStaticCodeCreateWithPath(app as CFURL, [], &candidate) == errSecSuccess, let candidate else {
            throw UpdateError.signature
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(candidate, flags, requirement) == errSecSuccess else {
            throw UpdateError.signature
        }
    }

    private enum UpdateError: Error {
        case download, unpack, contents, signature
    }
}
