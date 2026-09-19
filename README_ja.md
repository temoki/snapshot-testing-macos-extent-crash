# swift-snapshot-testing: 知覚差分比較が CIVector ではなく CGRect を渡している

> 確認用の日本語版です。上流に見せるのは [README.md](README.md)（英語）のほうです。

最小の再現パッケージです。渡している型が macOS では元々受け付けられず、macOS 27
ではライブラリ自身の呼び出し経路がその評価に到達するため、キャッチされない
Objective-C 例外でテストプロセスごと落ちます。

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

`compare` がこの知覚差分の経路に入るのは、バイト単位の比較が一致しなかったときだけ
です。だからスナップショットが完全一致しているあいだは何も起きません。表面化するの
は、画像が初めてずれたとき — つまり OS を上げた直後で、差分がいちばん見たい場面です。

## 中身

テスト対象を 2 つに分けてあります。SwiftPM が別プロセスで実行するので、片方の
クラッシュでもう片方の結果が消えません。

| 対象 | 示すもの |
|---|---|
| `PerceptualCompareTests` | 公開 API から見た症状。1 ピクセルだけ違う画像 2 枚を `Diffing<NSImage>.image(precision:perceptualPrecision:).diff` に渡します。スナップショットのファイルは使わず、画像はコードで作る決定的なビットマップです |
| `CoreImageExtentTests` | ライブラリに依存しない、パラメータ単体の挙動。`CIAreaAverage` に `CGRect` を渡す場合と `CIVector` を渡す場合を比べます |

## 実際に確認した結果

| | macOS 26.6 / Xcode 27.0（27A266a） | macOS 27 |
|---|---|---|
| `PerceptualCompareTests` | 通る（`The percentage of pixels that match 0.984375 is less than required 0.995` を返す） | 落ちる（TortoiseGraphics2 の CI、`xcode-27` ランナー、イメージ 20260912.0186.1、macOS 27.0 26A5406e で確認） |
| `CoreImageExtentTests` の `CGRect` 版 | **失敗**（同じ `-[NSConcreteValue CGRectValue]` の例外） | 失敗するはず |
| `CoreImageExtentTests` の `CIVector` 版 | 通る | 通るはず |

つまり `CGRect` を渡すこと自体は macOS 26 でも受け付けられません。macOS 27 で変わった
のは、ライブラリ自身の呼び出し経路がその評価に到達するようになった点です。

**未確認**：この再現パッケージを macOS 27 で走らせた結果はまだありません。上の
macOS 27 の欄は、同じライブラリのバージョン・同じ呼び出し経路で、別プロジェクト
（TortoiseGraphics2）の CI で観測したものです。`.github/workflows/ci.yml` を回せば
このパッケージ自体でも確認できます。

## 修正案

両方のヘルパーで `CIVector` を渡します。

```swift
applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: extent)])
```

## 実行方法

```bash
swift test
```

macOS 26 では `CoreImageExtentTests` の `CGRect` 版 2 件が失敗するので、コマンド
全体としては失敗で終わります（意図どおりです）。`.github/workflows/ci.yml` は
`xcode-27`（macOS 27）と対照の `macos-26` の両方で実行し、どちらも
`continue-on-error: true` にしてあります。

## 環境

| | |
|---|---|
| swift-snapshot-testing | 1.19.4 |
| クラッシュを観測 | macOS 27.0（26A5406e）、Xcode 27.0（27A266a）、arm64 |
| 対照 | macOS 26.6、Xcode 27.0（27A266a）、arm64（Apple M4） |
