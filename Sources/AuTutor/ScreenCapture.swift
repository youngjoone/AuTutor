import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import StudyCore

@MainActor final class ScreenCapture: ScreenCapturing {
    func capture() async throws -> Data {
        guard CGPreflightScreenCaptureAccess() else { throw StudyError.screenPermission }
        // Resolve the monitor before the first suspension, while the pointer is at the trigger location.
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw StudyError.captureFailed
        }
        let displayID = CGDirectDisplayID(number.uint32Value)
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                throw StudyError.captureFailed
            }
            let configuration = SCStreamConfiguration()
            configuration.width = CGDisplayPixelsWide(displayID)
            configuration.height = CGDisplayPixelsHigh(displayID)
            configuration.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            try Task.checkCancellation()
            // Encode off the main thread. Preserve all screen text at native resolution.
            return try await Task.detached(priority: .userInitiated) {
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
                    throw StudyError.captureFailed
                }
                CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw StudyError.captureFailed }
                return data as Data
            }.value
        } catch is CancellationError { throw CancellationError() }
        catch {
            if !CGPreflightScreenCaptureAccess() { throw StudyError.screenPermission }
            throw StudyError.captureFailed
        }
    }
}
