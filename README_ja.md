# swift-snapshot-testing: 知覚差分比較が CIVector ではなく CGRect を渡している

> 確認用の日本語版です。上流に見せるのは [README.md](README.md)（英語）のほうです。

最小の再現パッケージです。macOS で `perceptualPrecision` を使った比較は、
**Xcode 27 でビルドすると** キャッチされない Objective-C 例外になります。

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

XCTest なら例外を捕まえてテスト 1 件の失敗として報告しますが、swift-testing では
誰も捕まえないので、プロセスが signal 6 で落ち、そのバンドルの他のテストの結果も
すべて失われます（TortoiseGraphics2 で起きたのはこちらです）。

## 原因

`applyingAreaAverage()` と `applyingAreaMaximum()` が、extent を `CGRect` のまま
パラメータ辞書に入れています。`CGRect` は `NSValue` にブリッジされます。

```swift
func applyingAreaAverage() -> CIImage {
  applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: extent])
}
```

`inputExtent` が受け取るのは `CIVector` です。Core Image がこの値を評価するとき、
渡された値に `CGRectValue` を送ります。macOS の `NSValue` はこれを実装しておらず
（あるのは `rectValue`）、例外になります。UIKit の `NSValue` には `CGRectValue` が
あるので、iOS では同じコードでも問題が出ません。

Xcode 26 でビルドした場合はこの `NSValue` が受け付けられ、Xcode 27 でビルドすると
受け付けられません。下の表から言えるのは「実行時の OS は変数ではなく、ツールチェーン
が変数である」ということまでで、ツールチェーンの何が変わったのかまでは分かりません。

`compare` がこの知覚差分の経路に入るのは、バイト単位の比較が一致しなかったときだけ
です。だからスナップショットが完全一致しているあいだは何も起きず、画像が初めて
ずれたとき — 差分がいちばん見たい場面 — に表面化します。

## 中身

テスト対象を 2 つに分けてあります。SwiftPM が別プロセスで実行するので、片方の
失敗でもう片方の結果が消えません。

| 対象 | 示すもの |
|---|---|
| `PerceptualCompareTests` | 公開 API から見た症状。1 ピクセルだけ違う画像 2 枚を `Diffing<NSImage>.image(precision:perceptualPrecision:).diff` に渡します。スナップショットのファイルは使わず、画像はコードで作る決定的なビットマップです |
| `CoreImageExtentTests` | ライブラリに依存しない、パラメータ単体の挙動。`CIAreaAverage` に `CGRect` を渡す場合と `CIVector` を渡す場合を比べます |

## 実際に確認した結果

| OS | ツールチェーン | `PerceptualCompareTests` | `CIAreaAverage` + `CGRect` | `CIAreaAverage` + `CIVector` |
|---|---|---|---|---|
| macOS 26.6.2（25G83） | Xcode 26.6 | 通る | 通る | 通る |
| macOS 26.6 | Xcode 27.0（27A266a） | 通る¹ | **例外** | 通る |
| macOS 27.0（26A5406e） | Xcode 27.0（27A266a） | **例外** | **例外** | 通る |

1 行目と 3 行目はこのリポジトリの CI（`macos-26` と `xcode-27` ランナー）です。
この 2 つのイメージにはそれぞれ Xcode 26.6 と 27.0 しか入っておらず、OS と Xcode が
セットで変わるため、CI だけでは原因を切り分けられません。2 行目は手元の Mac
（Apple M4）で、OS は 1 行目・ツールチェーンは 3 行目と同じ組み合わせです。これが
3 行目と同じく失敗することから、変数は OS ではなくツールチェーンだと分かります。

¹ macOS 26 + Xcode 27 では、ライブラリ自身の呼び出し経路が例外になる評価まで到達
しないため、直接 Core Image を叩くテストにしか現れません。macOS 27 ではライブラリ
経路も到達します。TortoiseGraphics2 で表面化したのもこれで、ゴールデン画像が
ずっと完全一致していたので気づかず、1 枚ずれた瞬間にテストプロセスごと落ちました。

## 修正案

両方のヘルパーで `CIVector` を渡します。

```swift
applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
```

`CoreImageExtentTests` は両方の書き方を試していて、`CIVector` 版は上の表のすべての
組み合わせで通っています。

## 実行方法

```bash
swift test
```

Xcode 27 でビルドすると、macOS のバージョンによらず `CoreImageExtentTests` が失敗
するので、コマンド全体としては失敗で終わります（意図どおりです）。
`.github/workflows/ci.yml` は `xcode-27`（macOS 27）と対照の `macos-26`（Xcode 26.6）
で実行し、どちらも `continue-on-error: true` にしてあります。

## 環境

| | |
|---|---|
| swift-snapshot-testing | 1.19.4 |
| ランナーイメージ | `xcode-27-arm64` 20260912.0186.1、`macos-26-arm64` |
