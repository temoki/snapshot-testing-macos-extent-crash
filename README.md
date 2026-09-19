# swift-snapshot-testing: perceptual comparison crashes on macOS 27

A minimal reproduction for an uncaught Objective-C exception that kills the
whole test process when `perceptualPrecision` is used on macOS 27:

```
*** Terminating app due to uncaught exception 'NSInvalidArgumentException',
    reason: '-[NSConcreteValue CGRectValue]: unrecognized selector sent to instance ...'
	5   CoreImage        -[CIReductionFilter offsetAndCrop] + 56
	6   CoreImage        -[CIAreaAverage outputImage] + 56
	7   CoreImage        -[CIImage imageByApplyingFilter:withInputParameters:] + 300
	8   SnapshotTesting  CIImage.applyingAreaAverage()
	9   SnapshotTesting  perceptuallyCompare(_:_:pixelPrecision:perceptualPrecision:)
	10  SnapshotTesting  compare(_:_:precision:perceptualPrecision:)   // NSImage
```

Under XCTest the exception is caught and reported as a test failure. Under
swift-testing nothing catches it, so the test process aborts with signal 6 and
every other test in that bundle is lost.

## Cause

`applyingAreaAverage()` (and `applyingAreaMaximum()`) pass the extent as a
`CGRect`, which bridges into the parameter dictionary as an `NSValue`:

```swift
func applyingAreaAverage() -> CIImage {
  applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: extent])
}
```

`inputExtent` takes a `CIVector`. When Core Image evaluates that parameter it
sends the value `CGRectValue`, which macOS's `NSValue` does not implement — it
has `rectValue`. (UIKit's `NSValue` does have `CGRectValue`, which is why the
same code is fine on iOS.)

`compare` only reaches `perceptuallyCompare` when the byte comparison fails, so
nothing goes wrong while snapshots match exactly. The crash appears the first
time a snapshot differs — typically right after an OS upgrade, exactly when the
diff would have been useful.

## What this package contains

Two test targets, so that SwiftPM runs them as separate processes and a crash in
one does not hide the other's result.

| Target | What it shows |
|---|---|
| `PerceptualCompareTests` | The symptom through the public API: `Diffing<NSImage>.image(precision:perceptualPrecision:).diff` on two images that differ by one pixel. No snapshot files — the images are deterministic bitmaps. |
| `CoreImageExtentTests` | The parameter on its own, with no dependency on this library: `CIAreaAverage` with a `CGRect` extent versus a `CIVector` extent. |

## Observed results

| | macOS 26.6 / Xcode 27.0 (27A266a) | macOS 27 |
|---|---|---|
| `PerceptualCompareTests` | passes — the comparison returns `The percentage of pixels that match 0.984375 is less than required 0.995` | crashes (seen in CI on the `xcode-27` runner, image 20260912.0186.1, macOS 27.0 26A5406e) |
| `CoreImageExtentTests`, `CGRect` extent | **fails** with the same `-[NSConcreteValue CGRectValue]` exception | expected to fail |
| `CoreImageExtentTests`, `CIVector` extent | passes | expected to pass |

So the `CGRect` extent is already rejected on macOS 26 when Core Image evaluates
it. What changed on macOS 27 is that the library's own call path reaches that
evaluation; on macOS 26 the same call goes through without it.

**Note:** the macOS 27 column for this package is not verified yet — it was
observed in another project's CI with the same library version and call path.
Running `.github/workflows/ci.yml` here confirms it.

## Suggested fix

Pass a `CIVector` in both helpers:

```swift
applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
```

## Running it

```bash
swift test
```

`.github/workflows/ci.yml` runs the package on the `xcode-27` runner (macOS 27)
and on `macos-26` as a control.

## Environment

| | |
|---|---|
| swift-snapshot-testing | 1.19.4 |
| Crash seen on | macOS 27.0 (26A5406e), Xcode 27.0 (27A266a), arm64 |
| Control | macOS 26.6, Xcode 27.0 (27A266a), arm64 (Apple M4) |
