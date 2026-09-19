# swift-snapshot-testing: perceptual comparison passes a `CGRect` where Core Image wants a `CIVector`

A minimal reproduction. `perceptualPrecision` comparisons on macOS break when
the tests are **built with Xcode 27**, with an uncaught Objective-C exception:

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

Built with Xcode 26 the `NSValue` is accepted; built with Xcode 27 it is not.
The observations below don't say which part of the toolchain changed, only that
the OS the tests run on is not the variable — the toolchain is.

`compare` only reaches `perceptuallyCompare` when the byte comparison fails, so
nothing goes wrong while snapshots match exactly. The failure appears the first
time a snapshot differs, which is exactly when the diff would have been useful.

## What this package contains

Two test targets, so that SwiftPM runs them as separate processes and a failure
in one does not hide the other's result.

| Target | What it shows |
|---|---|
| `PerceptualCompareTests` | The symptom through the public API: `Diffing<NSImage>.image(precision:perceptualPrecision:).diff` on two images that differ by one pixel. No snapshot files — the images are deterministic bitmaps. |
| `CoreImageExtentTests` | The parameter on its own, with no dependency on this library: `CIAreaAverage` with a `CGRect` extent versus a `CIVector` extent. |

## Observed results

| OS | Toolchain | `PerceptualCompareTests` | `CIAreaAverage` + `CGRect` | `CIAreaAverage` + `CIVector` |
|---|---|---|---|---|
| macOS 26.6.2 (25G83) | Xcode 26.6 | passes | passes | passes |
| macOS 26.6.2 (25G83) | Xcode 27.0 (27A266a) | passes¹ | **throws** | passes |
| macOS 27.0 (26A5406e) | Xcode 27.0 (27A266a) | **throws** | **throws** | passes |
| macOS 27.0 | Xcode 26.x | not observed — no such pairing available | | |

Rows 1 and 3 are this repository's CI (the `macos-26` and `xcode-27` runners in
`.github/workflows/ci.yml`). Those two images each carry only one Xcode — 26.6
and 27.0 respectively — so CI alone cannot separate the OS from the toolchain.
Row 2 is a local machine (Apple M4): same OS as row 1, same toolchain as row 3.

Row 2 is what pins the blame on the toolchain. Holding the OS at 26.6.2 and
moving only Xcode 26.6 → 27.0 turns a pass into a throw, so the OS the tests
run on is not the variable. Row 4 would be the mirror image, but the `xcode-27`
runner image ships no Xcode 26 and Apple does not support that pairing, so it
was not measured; rows 1 and 2 already settle the question.

¹ On macOS 26 with Xcode 27 the library's own call path does not reach the
evaluation that throws, so only the direct Core Image test shows it there. On
macOS 27 the library path reaches it too — which is how this surfaced: a
project whose canvas snapshots had always matched byte for byte started losing
the whole test process as soon as one image differed.

## Suggested fix

Pass a `CIVector` in both helpers:

```swift
applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
```

`CoreImageExtentTests` covers both spellings, and the `CIVector` one passes in
every combination above.

## Running it

```bash
swift test
```

Built with Xcode 27, `CoreImageExtentTests` fails on any macOS, so the command
exits non-zero — that is the point. `.github/workflows/ci.yml` runs the package
on the `xcode-27` runner (macOS 27) and on `macos-26` (Xcode 26.6) as a control,
with `continue-on-error` so both results are visible.

## Environment

| | |
|---|---|
| swift-snapshot-testing | 1.19.4 |
| Runner images | `xcode-27-arm64` 20260912.0186.1, `macos-26-arm64` |
