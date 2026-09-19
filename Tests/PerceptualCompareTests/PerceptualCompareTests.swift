import AppKit
import SnapshotTesting
import XCTest

/// The symptom as a user meets it: a snapshot that no longer matches byte for
/// byte takes down the whole test process instead of failing one test.
final class PerceptualCompareTests: XCTestCase {
    /// `compare` only reaches `perceptuallyCompare` when the byte comparison
    /// fails, so this needs two images that differ — here by a single pixel.
    ///
    /// On macOS 26 this returns a failure message. On macOS 27 it never returns:
    /// it crashes inside `CIImage.applyingAreaAverage()`. Whether the diff
    /// reports a failure or nil is not the point; returning at all is.
    ///
    /// The printed message also tells you the comparison really got that far —
    /// two byte-identical images would return `nil` without ever entering the
    /// perceptual path.
    func testPerceptualComparisonOfDifferingImages() {
        let reference = makeImage(cornerPixelWhite: 0)
        let candidate = makeImage(cornerPixelWhite: 0.02)

        let diffing = Diffing<NSImage>.image(precision: 0.995, perceptualPrecision: 0.98)
        let result = diffing.diff(reference, candidate)
        print("DIFF RESULT: \(result?.0 ?? "nil (images considered matching)")")
    }

    /// A deterministic bitmap — no fonts, no layout, no OS-dependent rendering —
    /// so the only difference between the two images is the one corner pixel.
    private func makeImage(cornerPixelWhite: CGFloat) -> NSImage {
        let side = 8
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(gray: cornerPixelWhite, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))

        let cgImage = context.makeImage()!
        return NSImage(cgImage: cgImage, size: NSSize(width: side, height: side))
    }
}
