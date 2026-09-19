import CoreImage
import XCTest

/// `CIAreaAverage`'s `inputExtent` is documented as taking a `CIVector`, but
/// swift-snapshot-testing passes a `CGRect`, which bridges to an `NSValue`.
///
/// These cases isolate that one parameter from the rest of the library. Each
/// applies the filter and renders the result, the way `applyingAreaAverage()`
/// and `renderSingleValue(in:)` do.
final class CoreImageExtentTests: XCTestCase {
    /// A CGImage-backed image, like the ones the perceptual comparison works on.
    private func bitmapBackedImage() -> CIImage {
        let side = 4
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return CIImage(cgImage: context.makeImage()!)
    }

    private func renderAreaAverage(of image: CIImage, extent: Any) {
        let output = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: extent])
        let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])
        var pixel = [UInt16](repeating: 0, count: 4)
        context.render(
            output, toBitmap: &pixel, rowBytes: 8,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAh, colorSpace: nil)
    }

    /// What the library does today.
    func testAreaAverageWithCGRectExtent() {
        let image = bitmapBackedImage()
        renderAreaAverage(of: image, extent: image.extent)
    }

    /// The suggested fix.
    func testAreaAverageWithCIVectorExtent() {
        let image = bitmapBackedImage()
        renderAreaAverage(of: image, extent: CIVector(cgRect: image.extent))
    }

    /// Asking the filtered image for its extent evaluates `-[CIAreaAverage
    /// outputImage]` eagerly. That is the call the macOS 27 stack trace shows,
    /// and it already throws on macOS 26 — which is why the rendering cases
    /// above are the ones that mirror the library.
    func testAreaAverageWithCGRectExtentEvaluatedEagerly() {
        let image = bitmapBackedImage()
        let output = image.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: image.extent])
        XCTAssertFalse(output.extent.isEmpty)
    }
}
