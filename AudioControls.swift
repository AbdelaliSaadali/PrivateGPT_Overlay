import AppKit

// Native menu bar + settings. Settings are only brought forward by a user click/hotkey.
final class AudioControls: NSObject, NSMenuDelegate {
    private let routing = AudioRouting.shared
    private let defaults = UserDefaults.standard
    private let autoKey = "privategpt.switchWhenShown"
    private let restoreKey = "privategpt.restoreWhenHidden"
    private let iconKey = "privategpt.showMenuBarIcon"

    private var item: NSStatusItem?
    private var menu = NSMenu()
    private var preferences: NSWindow?
    private var statusLabel: NSTextField?
    private var modeLabel: NSTextField?
    private var autoCheck: NSButton?
    private var restoreCheck: NSButton?
    private var iconCheck: NSButton?
    private var warningLabel: NSTextField?

    var autoSwitch: Bool { defaults.bool(forKey: autoKey) }
    var restoreWhenHidden: Bool { defaults.object(forKey: restoreKey) as? Bool ?? true }
    var iconVisible: Bool { defaults.object(forKey: iconKey) as? Bool ?? true }

    override init() {
        super.init()
        menu.delegate = self
        updateMenuBar()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func updateMenuBar() {
        if iconVisible {
            if item == nil {
                item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            }
            if let button = item?.button {
                button.image = NSImage(systemSymbolName: "waveform.circle",
                                       accessibilityDescription: "PrivateGPT Audio")
                if button.image == nil { button.title = "PG" }
                button.toolTip = "PrivateGPT Overlay (menu icon may appear in screen shares)"
            }
            item?.menu = menu
            rebuildMenu()
        } else if let old = item {
            NSStatusBar.system.removeStatusItem(old)
            item = nil
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let state = NSMenuItem(title: routing.privateEnabled ? "Audio: PrivateGPT" : "Audio: Normal",
                               action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)
        menu.addItem(NSMenuItem.separator())

        let privateItem = NSMenuItem(title: "Use PrivateGPT Audio", action: #selector(usePrivate),
                                     keyEquivalent: "")
        privateItem.target = self
        privateItem.state = routing.privateEnabled ? .on : .off
        menu.addItem(privateItem)

        let normalItem = NSMenuItem(title: "Restore Normal Audio", action: #selector(useNormal),
                                    keyEquivalent: "")
        normalItem.target = self
        normalItem.state = routing.privateEnabled ? .off : .on
        menu.addItem(normalItem)

        menu.addItem(NSMenuItem.separator())
        let settingItem = NSMenuItem(title: "Settings…", action: #selector(showSettings),
                                     keyEquivalent: "")
        settingItem.target = self
        menu.addItem(settingItem)

        let showItem = NSMenuItem(title: "Show ChatGPT Overlay", action: #selector(showOverlay),
                                 keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        let quitItem = NSMenuItem(title: "Quit PrivateGPT", action: #selector(quitApp),
                                 keyEquivalent: "")
        quitItem.target = self
        menu.addItem(NSMenuItem.separator())
        menu.addItem(quitItem)
    }

    func toggleAudioMode() {
        switchAudio(privateMode: !routing.privateEnabled)
    }

    func overlayShown() {
        if autoSwitch && !routing.privateEnabled {
            switchAudio(privateMode: true)
        }
    }
    func overlayHidden() {
        if autoSwitch && restoreWhenHidden && routing.privateEnabled {
            switchAudio(privateMode: false)
        }
    }
    func appWillQuit() {
        if restoreWhenHidden && routing.privateEnabled {
            _ = routing.enableNormal()
        }
    }

    @objc private func usePrivate() { switchAudio(privateMode: true) }
    @objc private func useNormal() { switchAudio(privateMode: false) }
    @objc private func showOverlay() { appDelegateInstance?.showOverlayFromMenu() }
    @objc private func quitApp() { NSApp.terminate(nil) }

    private func switchAudio(privateMode: Bool) {
        if privateMode { routing.ensureMixerRunning() }
        let success = privateMode ? routing.enablePrivate() : routing.enableNormal()
        if !success {
            let message = routing.lastError ?? "Audio switching failed."
            NSLog("PrivateGPT Audio: %@", message)
            warningLabel?.stringValue = message
            if preferences == nil || !preferences!.isVisible {
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

    @objc private func autoChanged(_ sender: NSButton) {
        defaults.set(sender.state == .on, forKey: autoKey)
        refreshSettings()
    }
    @objc private func restoreChanged(_ sender: NSButton) {
        defaults.set(sender.state == .on, forKey: restoreKey)
        refreshSettings()
    }
    @objc private func iconChanged(_ sender: NSButton) {
        defaults.set(sender.state == .on, forKey: iconKey)
        updateMenuBar()
        refreshSettings()
    }
    @objc private func openMixer() {
        let url = URL(fileURLWithPath: "/Applications/Ladiocast.app")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }
    @objc private func refreshClicked() { refreshSettings() }

    private func makeLabel(_ text: String, size: CGFloat = 13, bold: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    @objc func showSettings() {
        if preferences == nil {
            let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 540),
                               styleMask: [.titled, .closable], backing: .buffered, defer: false)
            win.title = "PrivateGPT Overlay — Settings"
            win.isReleasedWhenClosed = false
            win.center()
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            win.sharingType = .none // best effort only

            let content = NSView(frame: NSRect(x: 0, y: 0, width: 550, height: 540))
            let stack = NSStackView()
            stack.orientation = .vertical
            stack.alignment = .leading
            stack.spacing = 12
            stack.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22)
            ])

            stack.addArrangedSubview(makeLabel("Audio Mode", size: 20, bold: true))
            let intro = makeLabel("Switch the whole Mac between your everyday audio devices and PrivateGPT's mixed microphone + system audio.")
            intro.textColor = .secondaryLabelColor
            stack.addArrangedSubview(intro)

            let mode = makeLabel("")
            mode.font = .boldSystemFont(ofSize: 14)
            modeLabel = mode
            stack.addArrangedSubview(mode)

            let buttons = NSStackView()
            buttons.orientation = .horizontal
            buttons.spacing = 12
            let privateButton = NSButton(title: "PrivateGPT Audio", target: self, action: #selector(usePrivate))
            privateButton.bezelStyle = .rounded
            let normalButton = NSButton(title: "Normal Audio", target: self, action: #selector(useNormal))
            normalButton.bezelStyle = .rounded
            buttons.addArrangedSubview(privateButton)
            buttons.addArrangedSubview(normalButton)
            stack.addArrangedSubview(buttons)

            let status = makeLabel("")
            status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            status.textColor = .secondaryLabelColor
            statusLabel = status
            stack.addArrangedSubview(status)

            let separator = NSBox()
            separator.boxType = .separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.addArrangedSubview(separator)

            let a = NSButton(checkboxWithTitle: "Automatically enable PrivateGPT Audio when overlay opens",
                             target: self, action: #selector(autoChanged(_:)))
            let r = NSButton(checkboxWithTitle: "Restore normal audio when overlay hides (auto mode) or app quits",
                             target: self, action: #selector(restoreChanged(_:)))
            let i = NSButton(checkboxWithTitle: "Show menu bar control (may be visible in screen shares)",
                             target: self, action: #selector(iconChanged(_:)))
            autoCheck = a
            restoreCheck = r
            iconCheck = i
            stack.addArrangedSubview(a)
            stack.addArrangedSubview(r)
            stack.addArrangedSubview(i)

            let tips = makeLabel("Shortcuts: ⌃⌥Space = show/hide · ⌃⌥M = audio · ⌃⌥, = settings")
            tips.textColor = .secondaryLabelColor
            stack.addArrangedSubview(tips)

            let actions = NSStackView()
            actions.orientation = .horizontal
            actions.spacing = 12
            let mixer = NSButton(title: "Open Ladiocast", target: self, action: #selector(openMixer))
            let refresh = NSButton(title: "Refresh Status", target: self, action: #selector(refreshClicked))
            actions.addArrangedSubview(mixer)
            actions.addArrangedSubview(refresh)
            stack.addArrangedSubview(actions)

            let warning = makeLabel("")
            warning.textColor = .systemRed
            warningLabel = warning
            stack.addArrangedSubview(warning)

            let note = makeLabel("Requires BlackHole 2ch + 16ch, Ladiocast, and the macOS Multi-Output Device. Test screen sharing separately; window exclusion is not guaranteed.")
            note.textColor = .secondaryLabelColor
            stack.addArrangedSubview(note)
            win.contentView = content
            preferences = win
        }
        refreshSettings()
        preferences?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshSettings() {
        modeLabel?.stringValue = routing.privateEnabled ? "● PrivateGPT Audio enabled" : "● Normal / custom audio"
        statusLabel?.stringValue = routing.statusDescription
        autoCheck?.state = autoSwitch ? .on : .off
        restoreCheck?.state = restoreWhenHidden ? .on : .off
        restoreCheck?.isEnabled = true
        iconCheck?.state = iconVisible ? .on : .off
    }
}
