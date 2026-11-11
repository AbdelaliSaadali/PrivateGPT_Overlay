import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Captures the desktop in-process. No separate screencapture executable,
/// screenshot file, app window, shutter sound or thumbnail is created.
@MainActor
final class DesktopClipboardCapture {
    static let shared = DesktopClipboardCapture()

    private var inProgress = false

    private struct DisplayImage {
        let frame: CGRect
        let image: CGImage
    }

    func capture() {
        guard !inProgress else { return }
        inProgress = true
        Task {
            defer { inProgress = false }
            do {
                let displays: [DisplayImage]
                if #available(macOS 14.0, *) {
                    displays = try await screenCaptureKitImages()
                } else {
                    // Other overlay features still work on macOS 13.
                    NSLog("PrivateGPT Screenshot: requires macOS 14 or later")
                    return
                }
                guard let composite = compositeImage(displays) else {
                    NSLog("PrivateGPT Screenshot: no image available from the selected displays")
                    return
                }

                // Do not clear an existing clipboard unless we have a valid image.
                let bitmap = NSBitmapImageRep(cgImage: composite)
                guard let pngData = bitmap.representation(using: .png, properties: [:]),
                      let tiffData = bitmap.tiffRepresentation else {
                    NSLog("PrivateGPT Screenshot: image encoding failed")
                    return
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setData(pngData, forType: .png)
                pasteboard.setData(tiffData, forType: .tiff)
                NSLog("PrivateGPT Screenshot: copied %d x %d image to clipboard",
                      composite.width, composite.height)
            } catch {
                // Required macOS privacy prompts and capture errors are controlled by macOS.
                NSLog("PrivateGPT Screenshot: native capture unavailable: %@",
                      error.localizedDescription)
            }
        }
    }

    @available(macOS 14.0, *)
    private func screenCaptureKitImages() async throws -> [DisplayImage] {
        let available = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        let ownApp = available.applications.filter {
            $0.bundleIdentifier == Bundle.main.bundleIdentifier
        }
        var images: [DisplayImage] = []
        for display in available.displays {
            // Exclude this overlay from captured content without hiding or
            // changing any window on the shared desktop.
            let filter = SCContentFilter(display: display,
                                         excludingApplications: ownApp,
                                         exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = display.width
            configuration.height = display.height
            configuration.capturesAudio = false
            configuration.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: configuration)
            images.append(DisplayImage(frame: display.frame, image: image))
        }
        return images
    }

    private func compositeImage(_ displays: [DisplayImage]) -> CGImage? {
        guard let first = displays.first else { return nil }
        if displays.count == 1 { return first.image }

        // Each monitor can have a different scale and a negative desktop origin.
        // Preserve their relative layout in one clipboard image.
        let bounds = displays.dropFirst().reduce(first.frame) { $0.union($1.frame) }
        let scale = displays.reduce(CGFloat(1.0)) { current, display in
            max(current,
                CGFloat(display.image.width) / max(display.frame.width, 1),
                CGFloat(display.image.height) / max(display.frame.height, 1))
        }
        let width = Int(ceil(bounds.width * scale))
        let height = Int(ceil(bounds.height * scale))
        guard width > 0, height > 0, width <= 32768, height <= 32768,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for display in displays {
            let destination = CGRect(x: (display.frame.minX - bounds.minX) * scale,
                                     y: (bounds.maxY - display.frame.maxY) * scale,
                                     width: display.frame.width * scale,
                                     height: display.frame.height * scale)
            ctx.draw(display.image, in: destination)
        }
        return ctx.makeImage()
    }
}
