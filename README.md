# PrivateGPT Overlay — macOS

A small native macOS floating ChatGPT window using your ordinary ChatGPT website account. No OpenAI API key or extra API usage fees.

> **Capture-exclusion caution:** The legacy AppKit `sharingType = .none` setting is best-effort. It is **not** a guarantee that every screen-sharing application will hide the overlay or Settings window. Always check the receiver's actual shared view before presenting confidential material.

## Install

Requires macOS 13+, Swift/Xcode Command Line Tools, and (for mixed audio) **BlackHole 2ch**, **BlackHole 16ch**, and **Ladiocast** with a Multi-Output Device.

From your project folder:

```bash
cd ~/Desktop/PrivateGPTOverlay
./install.sh
```

This builds locally and installs **PrivateGPT Overlay.app** into `/Applications`. It does not open the app during installation. Open it later from Finder → Applications.

For development-only builds: `./build.sh --no-open`. The installed app is signed locally, not notarized for distribution.

## Audio modes

**PrivateGPT Audio:**
- macOS output → **Périphérique à sortie multiple / Multi-Output Device** (Mac speakers + BlackHole 2ch)
- Ladiocast Input 1 → **BlackHole 2ch** (computer sound)
- Ladiocast Input 2 → **Micro MacBook Pro** (voice)
- Ladiocast Main Output → **BlackHole 16ch**
- macOS default input → **BlackHole 16ch** (the mixed signal received by ChatGPT)

**Normal Audio:** Restores the input/output devices used before the switch. If no saved devices exist (e.g. after a restart), it falls back to the MacBook built-in microphone and speakers.

Switching does not change applications that explicitly select a different microphone. Ladiocast remembers its mixer configuration and can be launched in the background when you enable PrivateGPT Audio.

## Controls and Settings

- **Control + Option + Space:** show/hide floating ChatGPT
- **Control + Option + M:** toggle Normal Audio ↔ PrivateGPT Audio
- **Control + Option + S:** Settings window (recommended; works more consistently with non-US keyboards)
- **Control + Option + , (comma):** Settings window (alternative)
- **Command + ,:** Settings when the PrivateGPT app is active
- **Menu bar icon → Settings…:** Another way to open Settings
- **Control + Option + Q:** quit
- **Menu bar icon:** audio mode, Settings, show ChatGPT, quit

Settings:
- Buttons to select audio mode.
- Optional automatic PrivateGPT Audio when showing the overlay (off by default).
- Optional restoration when hiding in automatic mode and when quitting (on by default).
- Optional menu bar icon (on by default). **The icon can be visible to screen-share viewers.** Hide it before presenting; all hotkeys continue to work.
- Current input/output device status, Ladiocast shortcut, refresh status.

The app never stores conversation audio. Its WebView requests unprocessed microphone audio to support virtual audio devices; the actual ChatGPT website handles normal chat and transcription.

## Troubleshooting

- If the app transcribes only YouTube but not your voice, open Ladiocast and verify the **Master** routing on both Input 1 and Input 2. Check the Master output meter when speaking with YouTube paused.
- If the mixer output goes silent, make sure Ladiocast Main Output is **BlackHole 16ch** and the Multi-Output Device contains the Mac speakers and **BlackHole 2ch**, not BlackHole 16ch.
- Keep your meeting application's microphone set to your **physical mic**, not the mixed loopback, to prevent broadcasting the meeting's own audio back into the call.
- If a shortcut is intercepted by another app, change its Carbon key binding in `PrivateGPTOverlay.swift`.
- Browser sessions and files are local to the WebKit container; do not commit application cookies, personal data, or build artifacts.

## Project source

- `PrivateGPTOverlay.swift`: floating window, embedded WebKit, hotkeys, microphone and file upload.
- `AudioRouting.swift`: native CoreAudio audio device selection and restoration.
- `AudioControls.swift`: menu bar mode switch and Settings UI.
- `Info.plist`, `Entitlements.plist`: native application configuration.
- `build.sh`, `install.sh`: local compilation, signing, installation.

This app is not affiliated with or endorsed by OpenAI.
