import AppKit
import SwiftUI
import XCTest
@testable import CodexBridgerUI

/// Rendering and pixel-measurement helpers for the UI suite.
///
/// ImageRenderer gives deterministic, headless output: the same assertions run without
/// launching the app or moving the mouse, and the PNGs it produces are the review
/// artefacts committed under docs/ui/after/.
@MainActor
enum Snapshot {

    static var packageRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static var artifactDirectory: URL {
        packageRoot.appendingPathComponent("docs/ui/after", isDirectory: true)
    }

    /// Renders a view at a fixed width and returns the image plus its point size.
    static func render<V: View>(
        _ view: V,
        width: CGFloat = 720,
        appearance: NSAppearance.Name = .aqua,
        scale: CGFloat = 2
    ) -> (image: CGImage, size: CGSize)? {
        let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
        let content = view
            .environment(\.colorScheme, scheme)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width)
            .background(Color.white.opacity(0.001))
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        var image: CGImage?
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            image = renderer.cgImage
        }
        guard let image else { return nil }
        return (image, CGSize(width: CGFloat(image.width) / scale,
                              height: CGFloat(image.height) / scale))
    }

    /// Writes a rendered view to docs/ui/after/<name>.png and returns its size.
    @discardableResult
    static func writeArtifact<V: View>(
        _ view: V,
        named name: String,
        width: CGFloat = 720,
        appearance: NSAppearance.Name = .aqua,
        scale: CGFloat = 2
    ) throws -> CGSize {
        guard let rendered = render(view, width: width, appearance: appearance, scale: scale) else {
            throw XCTSkip("renderer produced no image for " + name)
        }
        let rep = NSBitmapImageRep(cgImage: rendered.image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw XCTSkip("could not encode " + name)
        }
        try FileManager.default.createDirectory(
            at: artifactDirectory, withIntermediateDirectories: true
        )
        let suffix = appearance == .darkAqua ? "-dark" : ""
        let url = artifactDirectory.appendingPathComponent("\(name)\(suffix).png")
        try data.write(to: url)
        return rendered.size
    }

    /// Renders without writing anything, for assertions only.
    static func size<V: View>(
        _ view: V,
        width: CGFloat = 720,
        appearance: NSAppearance.Name = .aqua
    ) -> CGSize? {
        render(view, width: width, appearance: appearance)?.size
    }
}

// MARK: - Pixel probing

struct PixelBuffer {
    let pixels: [UInt8]
    let width: Int
    let height: Int
    let scale: CGFloat

    init?(image: CGImage, scale: CGFloat) {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        self.pixels = pixels
        self.width = width
        self.height = height
        self.scale = scale
    }

    /// Bounding box (in points) of everything matching a predicate.
    func boundingBox(where matches: (UInt8, UInt8, UInt8) -> Bool) -> CGRect? {
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let r = pixels[offset]
                let g = pixels[offset + 1]
                let b = pixels[offset + 2]
                if matches(r, g, b) {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        return CGRect(
            x: CGFloat(minX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(maxX - minX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
    }

    /// Bounding boxes of horizontally separated runs matching a predicate.
    ///
    /// Used to find each magenta fixture control independently so their x positions can
    /// be compared.
    func horizontalRuns(where matches: (UInt8, UInt8, UInt8) -> Bool) -> [CGRect] {
        var columnHasMatch = [Bool](repeating: false, count: width)
        for x in 0..<width {
            for y in 0..<height {
                let offset = (y * width + x) * 4
                if matches(pixels[offset], pixels[offset + 1], pixels[offset + 2]) {
                    columnHasMatch[x] = true
                    break
                }
            }
        }
        var runs: [CGRect] = []
        var start: Int?
        for x in 0..<width {
            if columnHasMatch[x], start == nil { start = x }
            if !columnHasMatch[x], let s = start {
                runs.append(columnRect(from: s, to: x - 1))
                start = nil
            }
        }
        if let s = start { runs.append(columnRect(from: s, to: width - 1)) }
        return runs
    }

    private func columnRect(from startX: Int, to endX: Int) -> CGRect {
        var minY = height, maxY = -1
        for x in startX...endX {
            for y in 0..<height {
                let offset = (y * width + x) * 4
                if isMagenta(pixels[offset], pixels[offset + 1], pixels[offset + 2]) {
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        return CGRect(
            x: CGFloat(startX) / scale,
            y: CGFloat(minY) / scale,
            width: CGFloat(endX - startX + 1) / scale,
            height: CGFloat(maxY - minY + 1) / scale
        )
    }

    private func isMagenta(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool {
        r > 200 && b > 200 && g < 80
    }
}

/// A control that occupies a known box, used to measure alignment.
struct MeasurementProbe: View {
    var height: CGFloat = 30
    var body: some View {
        Color(red: 1, green: 0, blue: 1)
            .frame(width: 200, height: height)
    }
}
