import AppKit

// Native macOS status item and settings UI. Audio changes remain in AudioRouting.
final class AudioControls: NSObject, NSMenuDelegate {
    private let routing = AudioRouting.shared
    private let defaults = UserDefaults.standard

    private let autoKey = "privategpt.switchWhenShown"
    private let restoreKey = "privategpt.restoreWhenHidden"
    private let iconKey = "privategpt.showMenuBarIcon"

    private var item: NSStatusItem?
    private let menu = NSMenu()
    private var preferences: NSWindow?
    private var statusLabel: NSTextField?
    private var modeLabel: NSTextField?
    private var modePicker: NSSegmentedControl?
    private var autoSwitchControl: NSSwitch?
    private var restoreSwitchControl: NSSwitch?
    private var menuBarSwitchControl: NSSwitch?
    private var warningLabel: NSTextField?

    var autoSwitch: Bool { defaults.bool(forKey: autoKey) }
    var restoreWhenHidden: Bool { defaults.object(forKey: restoreKey) as? Bool ?? true }
    var iconVisible: Bool { defaults.object(forKey: iconKey) as? Bool ?? true }

    override init() {
        super.init()
        menu.delegate = self
        updateMenuBar()
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func brandImage(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Brand")
        else { return nil }
        return NSImage(contentsOf: url)
    }

    private func updateMenuBar() {
        if iconVisible {
            if item == nil {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            }
            if let button = item?.button {
                if let image = brandImage("MenuBarTemplate@2x") {
                    image.size = NSSize(width: 18, height: 18)
                    image.isTemplate = true
                    button.image = image
                    button.title = ""
                } else {
                    button.image = NSImage(systemSymbolName: "bubble.left",
                                           accessibilityDescription: "PrivateGPT Overlay")
                    if button.image == nil { button.title = "PG" }
                }
                button.toolTip = "PrivateGPT Overlay — settings and audio modes"
                button.imagePosition = .imageOnly
            }
            item?.menu = menu
            rebuildMenu()
        } else if let current = item {
            NSStatusBar.system.removeStatusItem(current)
            item = nil
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let status = NSMenuItem(title: routing.privateEnabled ? "PrivateGPT Audio Active" : "Normal Audio",
                                action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        let privateItem = NSMenuItem(title: "Use PrivateGPT Audio",
                                     action: #selector(usePrivate), keyEquivalent: "")
        privateItem.target = self
        privateItem.state = routing.privateEnabled ? .on : .off
        menu.addItem(privateItem)

        let normalItem = NSMenuItem(title: "Restore Normal Audio",
                                    action: #selector(useNormal), keyEquivalent: "")
        normalItem.target = self
        normalItem.state = routing.privateEnabled ? .off : .on
        menu.addItem(normalItem)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings),
                                   keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let overlay = NSMenuItem(title: "Show ChatGPT Overlay",
                                  action: #selector(showOverlay), keyEquivalent: "")
        overlay.target = self
        menu.addItem(overlay)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PrivateGPT", action: #selector(quitApp),
                               keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    func toggleAudioMode() { switchAudio(privateMode: !routing.privateEnabled) }

    func overlayShown() {
        if autoSwitch && !routing.privateEnabled { switchAudio(privateMode: true) }
    }

    func overlayHidden() {
        if autoSwitch && restoreWhenHidden && routing.privateEnabled {
            switchAudio(privateMode: false)
        }
    }

    func appWillQuit() {
        if restoreWhenHidden && routing.privateEnabled { _ = routing.enableNormal() }
    }

    @objc private func usePrivate() { switchAudio(privateMode: true) }
    @objc private func useNormal() { switchAudio(privateMode: false) }
    @objc private func showOverlay() { appDelegateInstance?.showOverlayFromMenu() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    @objc private func modeChanged(_ sender: NSSegmentedControl) {
        let privateMode = sender.selectedSegment == 1
        switchAudio(privateMode: privateMode)
    }

    private func switchAudio(privateMode: Bool) {
        if privateMode { routing.ensureMixerRunning() }
        let success = privateMode ? routing.enablePrivate() : routing.enableNormal()
        if !success {
            let message = routing.lastError ?? "Unable to switch audio devices."
            warningLabel?.stringValue = message
            NSLog("PrivateGPT Audio: %@", message)
            if preferences?.isVisible != true {
                let alert = NSAlert()
                alert.messageText = "Audio switching incomplete"
                alert.informativeText = message
                alert.runModal()
            }
        } else {
            warningLabel?.stringValue = ""
        }
        refreshSettings()
        rebuildMenu()
    }

    @objc private func autoChanged(_ sender: NSSwitch) {
        defaults.set(sender.state == .on, forKey: autoKey)
        refreshSettings()
    }
    @objc private func restoreChanged(_ sender: NSSwitch) {
        defaults.set(sender.state == .on, forKey: restoreKey)
        refreshSettings()
    }
    @objc private func iconChanged(_ sender: NSSwitch) {
        defaults.set(sender.state == .on, forKey: iconKey)
        updateMenuBar()
        refreshSettings()
    }
    @objc private func openMixer() {
        let path = "/Applications/Ladiocast.app"
        guard FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
    @objc private func refreshClicked() { refreshSettings() }

    private func label(_ text: String, size: CGFloat = 13,
                       weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
        let result = NSTextField(labelWithString: text)
        result.font = .systemFont(ofSize: size, weight: weight)
        result.textColor = color
        result.lineBreakMode = .byWordWrapping
        result.maximumNumberOfLines = 0
        return result
    }

    private func stack(_ spacing: CGFloat = 10, vertical: Bool = true) -> NSStackView {
        let result = NSStackView()
        result.orientation = vertical ? .vertical : .horizontal
        result.alignment = vertical ? .leading : .centerY
        result.spacing = spacing
        result.distribution = .fill
        result.translatesAutoresizingMaskIntoConstraints = false
        return result
    }

    private func section(_ title: String, detail: String?,
                         in parent: NSStackView) -> NSStackView {
        let card = NSVisualEffectView()
        card.material = .contentBackground
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.translatesAutoresizingMaskIntoConstraints = false

        let content = stack(10)
        card.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 17),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -17)
        ])
        content.addArrangedSubview(label(title, size: 14, weight: .semibold))
        if let detail = detail {
            content.addArrangedSubview(label(detail, size: 12, color: .secondaryLabelColor))
        }
        parent.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        return content
    }

    private func switchRow(_ title: String, subtitle: String,
                           action: Selector, in parent: NSStackView) -> NSSwitch {
        let row = stack(8, vertical: false)
        let text = stack(3)
        text.addArrangedSubview(label(title, size: 13, weight: .medium))
        text.addArrangedSubview(label(subtitle, size: 11, color: .secondaryLabelColor))
        let toggle = NSSwitch(frame: .zero)
        toggle.target = self
        toggle.action = action
        let flexible = NSView()
        flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(text)
        row.addArrangedSubview(flexible)
        row.addArrangedSubview(toggle)
        parent.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        return toggle
    }

    @objc func showSettings() {
        if preferences == nil { createSettings() }
        refreshSettings()
        // Only user-initiated Settings interactions activate the window.
        NSApp.activate(ignoringOtherApps: true)
        preferences?.orderFrontRegardless()
        preferences?.makeKeyAndOrderFront(nil)
    }

    private func createSettings() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 690),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        win.title = "PrivateGPT Overlay — Settings"
        win.titleVisibility = .hidden
        win.titlebarAppearsTransparent = true
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.tabbingMode = .disallowed
        win.level = .floating
        win.isOpaque = false
        win.backgroundColor = .clear
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        win.sharingType = .none // Legacy, best effort; not a capture guarantee.

        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        win.contentView = background

        let content = stack(14)
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 25),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -25),
            content.topAnchor.constraint(equalTo: background.topAnchor, constant: 55),
            content.bottomAnchor.constraint(lessThanOrEqualTo: background.bottomAnchor, constant: -21)
        ])

        let header = stack(14, vertical: false)
        if let art = brandImage("InApp_Badge") {
            let icon = NSImageView(image: art)
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 59).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 59).isActive = true
            header.addArrangedSubview(icon)
        }
        let headerText = stack(4)
        headerText.addArrangedSubview(label("PrivateGPT Overlay", size: 23, weight: .semibold))
        headerText.addArrangedSubview(label("Settings", size: 13, color: .secondaryLabelColor))
        header.addArrangedSubview(headerText)
        content.addArrangedSubview(header)

        let audio = section("Audio", detail: "Choose what ChatGPT can hear.", in: content)
        let selector = NSSegmentedControl(labels: ["Normal", "PrivateGPT"],
                                          trackingMode: .selectOne,
                                          target: self, action: #selector(modeChanged(_:)))
        selector.segmentStyle = .rounded
        selector.translatesAutoresizingMaskIntoConstraints = false
        selector.widthAnchor.constraint(equalToConstant: 285).isActive = true
        selector.heightAnchor.constraint(equalToConstant: 29).isActive = true
        modePicker = selector
        audio.addArrangedSubview(selector)
        modeLabel = label("", size: 12, weight: .medium, color: .secondaryLabelColor)
        audio.addArrangedSubview(modeLabel!)
        statusLabel = label("", size: 11, color: .tertiaryLabelColor)
        statusLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        if let statusLabel = statusLabel { audio.addArrangedSubview(statusLabel) }

        let behavior = section("Behavior", detail: nil, in: content)
        autoSwitchControl = switchRow("Automatic audio mode",
                                      subtitle: "Use PrivateGPT audio when the overlay opens.",
                                      action: #selector(autoChanged(_:)), in: behavior)
        restoreSwitchControl = switchRow("Restore everyday audio",
                                         subtitle: "Return to normal when hidden or when quitting.",
                                         action: #selector(restoreChanged(_:)), in: behavior)

        let appearance = section("Appearance", detail: nil, in: content)
        menuBarSwitchControl = switchRow("Menu bar icon",
                                         subtitle: "May be visible to others during screen sharing.",
                                         action: #selector(iconChanged(_:)), in: appearance)

        let footer = stack(10)
        let actions = stack(10, vertical: false)
        let mixer = NSButton(title: "Open Ladiocast", target: self, action: #selector(openMixer))
        mixer.bezelStyle = .rounded
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshClicked))
        refresh.bezelStyle = .rounded
        actions.addArrangedSubview(mixer)
        actions.addArrangedSubview(refresh)
        footer.addArrangedSubview(actions)

        footer.addArrangedSubview(label("⌃⌥Space  Show   ·   ⌃⌥M  Audio   ·   ⌃⌥S  Settings",
                                         size: 11, color: .secondaryLabelColor))
        warningLabel = label("", size: 11, color: .systemRed)
        if let warningLabel = warningLabel { footer.addArrangedSubview(warningLabel) }
        footer.addArrangedSubview(label("Capture exclusion depends on the screen-sharing app.",
                                         size: 11, color: .tertiaryLabelColor))
        content.addArrangedSubview(footer)

        win.center()
        preferences = win
    }

    private func refreshSettings() {
        let active = routing.privateEnabled
        modePicker?.selectedSegment = active ? 1 : 0
        modeLabel?.stringValue = active ? "PrivateGPT audio is active" : "Normal or custom audio"
        statusLabel?.stringValue = routing.statusDescription
        autoSwitchControl?.state = autoSwitch ? .on : .off
        restoreSwitchControl?.state = restoreWhenHidden ? .on : .off
        menuBarSwitchControl?.state = iconVisible ? .on : .off
    }
}
