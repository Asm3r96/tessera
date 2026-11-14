import AppKit
import Combine

final class AboutSettingsPage: SettingsPage {
    private let updater: Updater
    private let status = NSTextField(wrappingLabelWithString: "")
    private let updateButton = NSButton(title: "Check for updates", target: nil, action: nil)
    private let automatic = NSSwitch()
    private let progress = NSProgressIndicator()
    private var subscriptions = Set<AnyCancellable>()

    init(updater: Updater) {
        self.updater = updater
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        heading("About", detail: "Your windows, arranged into saved layouts.")
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 68).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 68).isActive = true
        let name = Self.text("Tessera", size: 26, weight: .semibold)
        let version = Self.text("Version \(MenuPanel.version)", size: 12, secondary: true)
        version.isSelectable = true
        let identity = NSStackView(views: [name, version])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 6
        let hero = NSStackView(views: [icon, identity, NSView()])
        hero.alignment = .centerY
        hero.spacing = 18
        hero.edgeInsets = NSEdgeInsets(top: 10, left: 0, bottom: 8, right: 0)
        add(hero)

        let website = Self.linkButton("App website", target: self, action: #selector(openAppSite))
        let author = Self.linkButton("Made by Moe", target: self, action: #selector(openAuthorSite))
        let links = NSStackView(views: [website, author])
        links.spacing = 24
        addLeading(links)

        updateButton.target = self
        updateButton.action = #selector(checkOrInstall)
        Self.styleButton(updateButton)
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        let controls = NSStackView(views: [progress, updateButton])
        controls.spacing = 8
        let updateRow = Self.row("Software updates", control: controls)
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.setContentCompressionResistancePriority(.required, for: .vertical)
        automatic.target = self
        automatic.action = #selector(toggleAutomatic)
        automatic.setAccessibilityLabel("Check for updates automatically")
        let updateContent = NSStackView(views: [updateRow, status])
        updateContent.orientation = .vertical
        updateContent.alignment = .leading
        updateContent.spacing = 4
        updateContent.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 14, right: 0)
        updateRow.widthAnchor.constraint(equalTo: updateContent.widthAnchor).isActive = true
        status.widthAnchor.constraint(equalTo: updateContent.widthAnchor).isActive = true
        let automaticRow = Self.row("Automatic updates", control: automatic)
        add(Self.group([updateContent, automaticRow]))
        updater.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        refresh()
    }

    private func refresh() {
        automatic.state = updater.isRelease && updater.enabled ? .on : .off
        automatic.isEnabled = updater.isRelease
        let busy = updater.manual == .checking || updater.installing
        updateButton.isEnabled = !busy
        updateButton.title = !updater.isRelease ? "View releases" : (updater.available == nil ? "Check for updates" : "Install update")
        if busy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        if !updater.isRelease {
            status.stringValue = "Source build. Automatic updates are off."
        } else if let failure = updater.failure {
            status.stringValue = failure
        } else if updater.installing {
            status.stringValue = "Downloading and verifying the update…"
        } else if let release = updater.available {
            status.stringValue = "Tessera \(release.version.description) is available."
        } else {
            switch updater.manual {
            case .checking: status.stringValue = "Checking for updates…"
            case .upToDate: status.stringValue = "You're up to date."
            case .failed: status.stringValue = "Could not check for updates. Try again."
            case .idle: status.stringValue = "Check for a new version of Tessera."
            }
        }
    }

    @objc private func checkOrInstall() {
        if !updater.isRelease { openReleases() }
        else if updater.available != nil { updater.install() }
        else { updater.checkNow() }
    }
    @objc private func toggleAutomatic() { updater.enabled = automatic.state == .on }
    @objc private func openAppSite() { NSWorkspace.shared.open(URL(string: "https://tessera.m-reschreiter.at")!) }
    @objc private func openAuthorSite() { NSWorkspace.shared.open(URL(string: "https://m-reschreiter.at")!) }
    @objc private func openReleases() { NSWorkspace.shared.open(URL(string: "https://github.com/Asm3r96/tessera/releases")!) }
}
