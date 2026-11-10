# PrivateGPT Overlay (macOS prototype)

This is a small native macOS application that embeds **https://chatgpt.com/** in a floating `WKWebView`. It uses your normal ChatGPT account and its normal website features. It does **not** use the OpenAI API or require an API key.

## Build and run on your Mac (macOS 15 supported)

1. Unzip this folder.
2. Open **Terminal** and run:

   ```bash
   cd ~/Desktop/PrivateGPTOverlay
   ./build.sh
   ```

   If you extracted it somewhere else, change the `cd` path.
3. If the Swift compiler isn't available, install Apple's Command Line Tools with `xcode-select --install`, then rerun `./build.sh`.
4. The compiled application lives at `build/PrivateGPTOverlay.app`. You can open it again from Finder.
5. Sign in to ChatGPT **inside the app**. This is a separate browser cookie store from Safari, Chrome, and the official ChatGPT app.

## Shortcuts

- **Control + Option + Space** — toggle the private window.
- **Control + Option + Q** — quit the app.

The app intentionally has no Dock icon or menubar item. If a shortcut conflicts with a system shortcut, you can quit it from Activity Monitor and change the key combination in `PrivateGPTOverlay.swift`.

## Test in this order

1. **Before sharing:** sign in, verify that text chat works, test a file/image upload, and test ChatGPT's microphone/dictation if present. Allow microphone permissions only if you choose to use the feature. ChatGPT web features can be limited inside embedded browsers.
2. **Before sharing:** start a local screen recording (QuickTime or macOS Screenshot), reveal the floating window, then review the recording. If it appears in the recording, do not assume the exclusion works.
3. **Before a real presentation:** test the exact Google Meet/Zoom/Teams full-desktop sharing mode and inspect the **receiver's view**, ideally using another device/account. A local recording isn't enough to prove other capture systems behave identically.
4. Do not screen share sensitive material until you verify that your specific capture pipeline excludes the window. Repeat testing after macOS, browser, or conferencing-app updates.

## Limitations

- `window.sharingType = .none` is a legacy, **best-effort** macOS property. Apple explicitly warns that it is not guaranteed to prevent capture. The app **cannot know** whether Zoom/Meet/Teams is capturing it.
- Google may block 'Continue with Google' in an embedded browser (`disallowed_useragent`). There is no supported bypass in this project. A different supported sign-in method may be needed, if available to your account.
- File picker dialogs, microphone permission prompts, notifications, the macOS menu bar, and the mouse cursor can still be recorded. Open/authorize them **before** presenting.
- Native ChatGPT website voice or speech-to-text can be unavailable in `WKWebView` even when they work in Chrome/Safari. The app requests permission correctly, but cannot force feature compatibility. macOS Dictation may be an alternative for text fields.
- ChatGPT spoken audio could be heard by participants or included in system-audio sharing. Use headphones or text-only mode if appropriate.
- The project has been compiled and launched successfully on an Intel Mac running macOS 15; screen-capture exclusion and audio behavior must still be verified for each meeting/capture setup.
- For system sound transcription, BlackHole 2ch can serve as a virtual input, with macOS Multi-Output Device sending sound to both BlackHole and the speakers. The audio script asks for echo cancellation, noise suppression, and automatic gain control to be disabled because these can interfere with virtual audio inputs.
- The experimental Ladiocast Loopback selection is **not** included in this working version: mixed microphone + system audio is still under test. Ladiocast or other routing tools require appropriate macOS permissions. Keep your meeting application's microphone set to the physical mic to avoid feedback.
- Never commit application cookies or WebKit storage, local `.app` builds, or `.bak` files; `.gitignore` excludes them.

## Project files

- `PrivateGPTOverlay.swift`: native window, webview, hotkeys, microphone/file-picker handling.
- `Info.plist`: app metadata and usage descriptions.
- `Entitlements.plist`: audio/camera signing entitlements.
- `build.sh`: compiles and locally signs the `.app` using Apple's Swift tools.

This is not affiliated with or endorsed by OpenAI.
