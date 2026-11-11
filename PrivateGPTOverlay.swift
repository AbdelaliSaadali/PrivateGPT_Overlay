import AppKit
import WebKit
import Carbon

// Prototype: capture exclusion is best-effort, NOT a security guarantee.
// The application doesn't modify ChatGPT, read browser cookies, or use an API key.

var appDelegateInstance: PrivateGPTDelegate?

private func onGlobalHotkey(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event = event else { return OSStatus(eventNotHandledErr) }
    var key = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &key
    )
    if status == noErr {
        let hotkeyNumber = key.id
        DispatchQueue.main.async {
            appDelegateInstance?.handleHotkey(hotkeyNumber)
        }
    }
    return status
}

private final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class PrivateGPTDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    private var window: ChatPanel!
    private var browser: WKWebView!
    private var toggleHotkey: EventHotKeyRef?
    private var quitHotkey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var settingsHotkey: EventHotKeyRef?
    private var settingsAltHotkey: EventHotKeyRef?
    private var audioHotkey: EventHotKeyRef?
    private var screenshotHotkey: EventHotKeyRef?
    private var audioControls: AudioControls?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // No Dock icon while sharing.
        installEditMenu() // Native menu commands make Cmd+C / Cmd+V work in WebKit.

        let webConfig = WKWebViewConfiguration()
        webConfig.websiteDataStore = .default() // Persist signed-in session within this app.
        // For a virtual microphone carrying computer sound, WebRTC's default
        // echo cancellation/noise filtering can suppress almost all useful audio.
        // Request unprocessed audio while retaining the website's other constraints.
        // Log capture state only (never audio samples or spoken content).
        webConfig.userContentController.add(self, name: "privateGPTAudioStatus")
        let rawAudioScript = """
        (() => {
          const send = message => {
            try { window.webkit.messageHandlers.privateGPTAudioStatus.postMessage(message); }
            catch (_) {}
          };
          const proto = globalThis.MediaDevices && MediaDevices.prototype;
          if (!proto || typeof proto.getUserMedia !== "function") {
            send("getUserMedia not available at script start");
            return;
          }
          const original = proto.getUserMedia;
          proto.getUserMedia = function(request) {
            if (!request || !request.audio) return original.call(this, request);
            send("getUserMedia invoked (audio)");
            const existing = typeof request.audio === "object" ? request.audio : {};
            const adjusted = Object.assign({}, request, {
              audio: Object.assign({}, existing, {
                echoCancellation: false,
                noiseSuppression: false,
                autoGainControl: false
              })
            });
            return original.call(this, adjusted).then(
              stream => {
                for (const track of stream.getAudioTracks()) {
                  const settings = track.getSettings();
                  send("Audio track started: echoCancellation=" + settings.echoCancellation +
                    ", noiseSuppression=" + settings.noiseSuppression +
                    ", autoGainControl=" + settings.autoGainControl);
                  track.addEventListener("mute", () => send("Audio track muted"));
                  track.addEventListener("unmute", () => send("Audio track unmuted"));
                  track.addEventListener("ended", () => send("Audio track ended"));
                }
                return stream;
              },
              error => { send("getUserMedia failed: " + error.name); throw error; }
            );
          };
          send("Unprocessed-audio capture hook installed");
        })();
        """
        webConfig.userContentController.addUserScript(
            WKUserScript(source: rawAudioScript,
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: false,
                         in: .page)
        )
        browser = WKWebView(frame: .zero, configuration: webConfig)
        browser.uiDelegate = self
        browser.navigationDelegate = self
        browser.allowsBackForwardNavigationGestures = true

        window = ChatPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PrivateGPT Overlay"
        window.isFloatingPanel = true
        window.level = .floating
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 380, height: 400)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Legacy AppKit exclusion. The capture application may ignore this.
        window.sharingType = .none

        window.contentView = browser
        window.delegate = self
        audioControls = AudioControls()
        window.center()
        audioControls?.overlayShown()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let chatGPT = URL(string: "https://chatgpt.com/") {
            browser.load(URLRequest(url: chatGPT))
        }

        installHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let key = toggleHotkey { UnregisterEventHotKey(key) }
        if let key = quitHotkey { UnregisterEventHotKey(key) }
        if let key = settingsHotkey { UnregisterEventHotKey(key) }
        if let key = settingsAltHotkey { UnregisterEventHotKey(key) }
        if let key = audioHotkey { UnregisterEventHotKey(key) }
        if let key = screenshotHotkey { UnregisterEventHotKey(key) }
        if let handler = eventHandler { RemoveEventHandler(handler) }
        audioControls?.appWillQuit()
    }

    func windowWillClose(_ notification: Notification) {
        audioControls?.overlayHidden()
    }

    func showOverlayFromMenu() {
        if !window.isVisible {
            audioControls?.overlayShown()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // WebKit editing shortcuts are dispatched through the native menu.
    // The menu can still receive key equivalents in accessory (menu-bar-hidden) mode.
    private func installEditMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: "PrivateGPT Overlay")
        appItem.submenu = appMenu
        let settingsMenuItem = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: ",")
        settingsMenuItem.target = self
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit PrivateGPT Overlay", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        audioControls?.showSettings()
    }

    // Control + Option + Space: show / hide the floating window.
    // Control + Option + Q: quit the app (it has no Dock icon).
    private func installHotkeys() {
        var hotkeyEvent = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            onGlobalHotkey,
            1,
            &hotkeyEvent,
            nil,
            &eventHandler
        )
        guard handlerStatus == noErr else {
            NSLog("PrivateGPT: failed to register hotkey handler: %d", handlerStatus)
            return
        }

        let signature: OSType = 0x50475054 // PGPT
        var toggleID = EventHotKeyID()
        toggleID.signature = signature
        toggleID.id = 1
        var quitID = EventHotKeyID()
        quitID.signature = signature
        quitID.id = 2
        var settingsID = EventHotKeyID()
        settingsID.signature = signature
        settingsID.id = 3
        var settingsAltID = EventHotKeyID()
        settingsAltID.signature = signature
        settingsAltID.id = 5
        var audioID = EventHotKeyID()
        audioID.signature = signature
        audioID.id = 4
        var screenshotID = EventHotKeyID()
        screenshotID.signature = signature
        screenshotID.id = 6
        let modifierMask = UInt32(controlKey | optionKey)

        let showResult = RegisterEventHotKey(
            UInt32(kVK_Space), modifierMask, toggleID,
            GetApplicationEventTarget(), 0, &toggleHotkey
        )
        let quitResult = RegisterEventHotKey(
            UInt32(kVK_ANSI_Q), modifierMask, quitID,
            GetApplicationEventTarget(), 0, &quitHotkey
        )
        let settingsResult = RegisterEventHotKey(
            UInt32(kVK_ANSI_Comma), modifierMask, settingsID,
            GetApplicationEventTarget(), 0, &settingsHotkey
        )
        let settingsAltResult = RegisterEventHotKey(
            UInt32(kVK_ANSI_S), modifierMask, settingsAltID,
            GetApplicationEventTarget(), 0, &settingsAltHotkey
        )
        let audioResult = RegisterEventHotKey(
            UInt32(kVK_ANSI_M), modifierMask, audioID,
            GetApplicationEventTarget(), 0, &audioHotkey
        )
        let screenshotResult = RegisterEventHotKey(
            UInt32(kVK_ANSI_3), modifierMask, screenshotID,
            GetApplicationEventTarget(), 0, &screenshotHotkey
        )
        if showResult != noErr || quitResult != noErr || settingsResult != noErr || settingsAltResult != noErr || audioResult != noErr || screenshotResult != noErr {
            NSLog("PrivateGPT hotkey registrations: show=%d quit=%d comma=%d S=%d audio=%d screenshot=%d", showResult, quitResult, settingsResult, settingsAltResult, audioResult, screenshotResult)
        }
    }

    func handleHotkey(_ id: UInt32) {
        if id == 1 {
            if window.isVisible {
                audioControls?.overlayHidden()
                window.orderOut(nil)
            } else {
                audioControls?.overlayShown()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else if id == 2 {
            NSApp.terminate(nil)
        } else if id == 3 || id == 5 {
            NSLog("PrivateGPT: Settings hotkey received (%u)", id)
            audioControls?.showSettings()
        } else if id == 4 {
            audioControls?.toggleAudioMode()
        } else if id == 6 {
            captureDesktopToClipboard()
        }
    }

    // In-process macOS capture, reusing PrivateGPT's own screen-recording permission.
    // No screen UI, file or separate utility; required system indicators remain possible.
    private func captureDesktopToClipboard() {
        DesktopClipboardCapture.shared.capture()
    }

    // Capture diagnostic metadata only; never store or inspect the audio itself.
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "privateGPTAudioStatus",
              let status = message.body as? String else { return }
        NSLog("PrivateGPT Audio: %@", status)
    }

    // macOS WKWebView requires this delegate for file and image uploads.
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping ([URL]?) -> Void
    ) {
        let picker = NSOpenPanel()
        picker.canChooseFiles = true
        picker.canChooseDirectories = parameters.allowsDirectories
        picker.allowsMultipleSelection = parameters.allowsMultipleSelection
        picker.begin { result in
            completionHandler(result == .OK ? picker.urls : nil)
        }
    }

    // Let macOS ask for microphone/camera access; never silently grant it.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        decisionHandler(.prompt)
    }

    // A target=_blank pop-up (including some sign-in flows) stays inside the panel.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("PrivateGPT navigation error: %@", error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

@main
struct PrivateGPTMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = PrivateGPTDelegate()
        appDelegateInstance = delegate
        application.delegate = delegate
        application.run()
    }
}
