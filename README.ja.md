# swift-snapshot-guard

CI が記録した画像をベースラインにする運用で、[swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) の落とし穴をふさぐパッケージです。

[English](README.md)

スナップショットのベースラインは、記録した環境でしか一致しません。同じシミュレータのビルドでも、CI と手元の Mac では文字の描画が変わることがあります。そのため CI が描いた画像を正とする運用がよく取られますが、次の 3 つでつまずきます。

| 困りごと | このパッケージが用意するもの |
|---|---|
| ベースラインが無いと記録して失敗するが、再試行は今書かれたファイルと比べて**通ってしまう**。何も比べていないのに CI が緑になる。 | `assertGuardedSnapshot` は再試行でも失敗させる。 |
| 記録された画像は `.xcresult` の中に `test.Name_0_<UUID>.png` のような名前で埋もれている。 | `snapshot-guard fetch` がベースラインの名前に戻して置く。 |
| 描けなかった画面の真っ白な画像を、そのままベースラインにしてしまう。 | `snapshot-guard check` が同一バイトの画像を報告する。 |

## 導入

テストターゲットに追加します。

```swift
.package(url: "https://github.com/instantraaamen/swift-snapshot-guard", from: "0.1.0")
```

## ガード

`assertGuardedSnapshot` の引数は `assertSnapshot` と同じです。

```swift
@MainActor
@Test func profile() {
  assertGuardedSnapshot(of: ProfileView(), as: .keyWindowImage(layout: .device(config: .iPhone13)))
}
```

ガードはライブラリの失敗メッセージの文言を読んでいます。ライブラリを上げて文言が変わったときに気づけるよう、テストを 1 つ足してください。

```swift
@Test func snapshotGuardIsAlive() {
  #expect(SnapshotGuard.missingReferenceCheck() == nil)
}
```

知っておくこと:

- 失敗は Swift Testing に報告します。XCTest からは `verifyGuardedSnapshot` の戻り値を `XCTFail` に渡します。
- 覚えているのはプロセスの中だけです。テストプランの「失敗時に再試行」のような同じプロセスでの再試行に効きます。
- `.keyWindowImage` はホストアプリのキーウィンドウ経由で描きます(`glassEffect` が真っ白になるのを防ぐ)。テストターゲットにホストアプリが必要です。

## ベースラインが有効な環境でだけ実行する

```swift
let snapshots = SnapshotEnvironment(baselineOSVersion: "18.2", policy: .ciOnly)

@Suite(.enabled(if: snapshots.shouldRun, snapshots.skipReason))
struct ScreenSnapshotTests { ... }
```

## コマンドラインツール

```sh
swift run snapshot-guard fetch --xcresult Test.xcresult --snapshots-dir Tests/AppTests/__Snapshots__
swift run snapshot-guard fetch --xcode-cloud --workflow "Tests" --snapshots-dir ...
swift run snapshot-guard check --snapshots-dir Tests/AppTests/__Snapshots__ --strict
```

録り直すときは、置き換えたい画像を消す → CI でテストを回す → `fetch` → 1 枚ずつ目で見てコミット、の順です。Xcode Cloud から取るときの環境変数など、詳しくは [README.md](README.md) を見てください。

## ライセンス

MIT
