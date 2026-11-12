# swift-snapshot-guard

「たまたま通ってしまう」ことのない、Swift Testing 向けのスナップショットテストです。

[English](README.md)

スナップショットテストは、画面の今の見た目を、以前に記録した画像と比べます。価値があるのは、その比較が本当に行われているあいだだけです。ところが、比較は気づかないうちに止まります。

- 基準の無いテストが画像を記録して落ち、テストプランが再試行し、再試行は 1 回目が書いたばかりの画像と比べて通る。
- 画面が何も描けず、真っ白の画像が基準になり、以後ずっと真っ白どうしで一致する。
- 録り直すつもりで基準を消したまま忘れ、CI 以外ではスイートを飛ばしているので誰も気づかない。
- 同じ画面を別々の色空間で比べてしまい、目に見えない差で落ちる。

どれも、このパッケージの元になったアプリで実際に起きたことです。`swift-snapshot-guard` は、これらが起きないように作ったスナップショットテストのライブラリと、CI まわりの作業を受け持つコマンドです。

依存は、コマンドが使う [swift-argument-parser](https://github.com/apple/swift-argument-parser) だけです。

## 使い方

```swift
import SnapshotGuard
import Testing

@MainActor
@Suite(.snapshots(recording: .never))
struct ProfileSnapshotTests {
  @Test func profile() async {
    await expectSnapshot(
      of: ProfileView(user: .sample),
      as: .image(layout: .fixed(width: 390, height: 844), traits: { $0.userInterfaceStyle = .dark })
    )
  }
}
```

- 基準はテストの隣の `__Snapshots__/<ソースファイル名>/<テスト名>.<名前>.png` に置きます。
- 基準が無いテストは必ず落ちます。`recording` が `.never` なら何も書かず、撮った画像をテストに添付します(CI 向け)。`.missing` なら書きますが、同じプロセスが書いた基準では合格にしません。
- 画像は、どちらも sRGB・8bit にそろえてから画素ごとに比べます。許容は「違ってよい画素の割合」「1 チャンネルの許容差」「比べない領域」で指定します。
- 1 色だけの画像は、比べる前に弾きます(描けなかった画面の見た目だからです)。
- 画面は専用のウィンドウに載せ、実際の画面と同じ経路で描きます。ガラスなどの効果もそのまま写ります。ホストアプリのウィンドウには触りません。
- 落ちたときは、違う画素の数と最大の色差を伝え、撮った画像・基準・差分を添付します。基準を記録した環境(OS・機種・倍率)が今と違えば、それも伝えます。

## CI でだけ比べるスイート

画像は記録した環境でしか一致しません。そこで画像のスイートを CI 以外で飛ばすことが多いのですが、飛ばしたスイートは「基準が無くなった」ことに気づけません。

代わりに、どこでも実行して、できる検査だけをさせます。

```swift
@Suite(.snapshots(recording: .never, verifying: environment.shouldRun ? .comparison : .referenceExists))
```

`.referenceExists` では何も描かず、基準のファイルがあるかだけを確かめます。

## CI から基準を持ち帰る

```sh
swift run snapshot-guard fetch --xcresult Test.xcresult --snapshots-dir Tests/__Snapshots__
swift run snapshot-guard check --snapshots-dir Tests/__Snapshots__ --strict
```

- `fetch` は、落ちたテストに添付された画像を、基準の置き場へ正しい名前で置きます。`--include-mismatched` を付けると、一致しなかった画像も新しい基準として取り込みます(意図した変更のあとに、基準を消さずに採用できます)。
- `--xcode-cloud` は Xcode Cloud のビルドから結果を取ってきます。
- `check` は、同じ中身の画像・1 色だけの画像・名前の衝突・記録した環境の混在を報告します。

詳しくは [README.md](README.md) を見てください。

## ライセンス

Apache License 2.0
