<p align="center">
  <img src="assets/icon.png" width="128" alt="DockLens アプリアイコン">
</p>

<h1 align="center">DockLens</h1>

<p align="center">
  <b>Dockのアイコンにポインタを乗せると、そのアプリのすべてのウインドウが見えます。</b><br>
  ライブサムネイル。クリックで切り替え、プレビューからそのまま閉じる・最小化・フルスクリーンも可能。<br>
  無料・オープンソース（GPLv3）。
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-TW.md">繁體中文</a> · 日本語 · <a href="README.ko.md">한국어</a>
</p>

<p align="center">
  <a href="../../releases/latest"><img alt="最新リリース" src="https://img.shields.io/github/v/release/firstfu/DockLens-app?style=flat-square"></a>
  <img alt="macOS 26以降" src="https://img.shields.io/badge/macOS-26%2B-blue?style=flat-square">
  <a href="LICENSE"><img alt="GPLv3ライセンス" src="https://img.shields.io/github/license/firstfu/DockLens-app?style=flat-square"></a>
</p>

<p align="center">
  <a href="https://firstfu.github.io/DockLens-app/"><b>ウェブサイト</b></a>
  &nbsp;·&nbsp;
  <a href="../../releases/latest"><b>DockLens.zip をダウンロード</b></a>
  &nbsp;·&nbsp;
  <code>brew install --cask firstfu/tap/docklens</code>
</p>

> [!NOTE]
> DockLens は **macOS 26 以降**が必要です。**まだAppleの公証（notarize）を受けていない**ため、初回起動はmacOSにブロックされます。システム設定 → プライバシーとセキュリティを開き、**このまま開く**を一度クリックしてください（[手順](#インストール)）。コードはすべてここにあり、[各権限の用途](#プライバシー)も下に明記しています。

<p align="center">
  <img src="assets/hero.png" width="780" alt="Dockのアイコンにポインタを乗せると、そのアプリのすべてのウインドウのライブサムネイルがパネルに表示される">
</p>

## 動作を見る

<p align="center">
  <img src="assets/demo.gif" width="780" alt="ポインタをDockのアイコンに乗せると全ウインドウのライブサムネイルが表示され、サムネイルに乗せると閉じる・最小化・フルスクリーンのボタンが出る">
  <br>
  <sub>Dockのアイコンに乗せ、サムネイルをクリックして切り替え。プレビューから閉じる・最小化もできます。</sub>
</p>

<p align="center">
  <img src="assets/preview-panel.png" width="780" alt="5つのウインドウを表示したプレビューパネル。1つは「最小化」、1つは「別のデスクトップ」と表示されている">
  <br>
  <sub>最小化されたウインドウや別のデスクトップにあるウインドウにはラベルが付きます。クリックするとそのまま移動します。</sub>
</p>

<table>
  <tr>
    <td width="50%" align="center"><img src="assets/closed-window.png" alt="赤いボタンで閉じたウインドウも「閉じた」として一覧に残り、ワンクリックで再び開ける"><br><sub><b>✕で閉じたけれど、アプリは起動中？</b><br>NotionやSlackなどのウインドウは一覧に残り、ワンクリックで再び開けます。</sub></td>
    <td width="50%" align="center"><img src="assets/calendar.png" alt="今日の予定と、ビデオ通話用の「参加」ボタンを表示するカレンダーアジェンダ"><br><sub><b>カレンダーのアジェンダ。</b><br>今日、次に明日の予定。「今」「10分後に開始」、Zoom・Meet・Teamsのリンクには「参加」ボタンが出ます。</sub></td>
  </tr>
  <tr>
    <td align="center"><img src="assets/media-bar.png" alt="SpotifyとMusicの再生バー（再生・一時停止・前へ・次へ）"><br><sub>SpotifyとMusicの<b>再生バー</b>：再生／一時停止、前へ、次へ、現在の曲。</sub></td>
    <td align="center"><img src="assets/onboarding.png" alt="初回ウインドウ：アクセシビリティは必須、画面収録は任意"><br><sub><b>画面収録は任意です。</b><br>許可しなくても、プレビューにはアプリアイコンとタイトルで各ウインドウが並びます。</sub></td>
  </tr>
</table>

<p align="center">
  <img src="assets/no-screen-recording.png" width="780" alt="画面収録の権限がない場合のプレビュー：各ウインドウがアプリアイコンとタイトルで表示される">
  <br>
  <sub>画面収録がなくても、切り替え・閉じる・最小化は使えます。</sub>
</p>

## インストール

**Homebrew**（[個人のtap](https://github.com/firstfu/homebrew-tap)）：

```sh
brew install --cask firstfu/tap/docklens
```

**手動でダウンロードする場合：**

1. [Releases](../../releases/latest) から `DockLens.zip` をダウンロードして展開します。
2. `DockLens.app` を `/Applications` に移動します。
3. 開きます。DockLens はまだ公証を受けていないため、初回起動はmacOSにブロックされます。**システム設定 → プライバシーとセキュリティ**を開き、下へスクロールして*「DockLens」は、Macを保護するためブロックされました*の横にある**このまま開く**をクリックします。この操作はバージョンごとに一度だけです。
4. ようこそ画面で求められる権限を許可します（下の表を参照）。

**macOS 26 以降**が必要です。アプリはユニバーサルバイナリ（Apple シリコン／Intel）です。

### アップデート

新しい `DockLens.app` を `/Applications` に上書きするか、tapの更新後に `brew upgrade --cask docklens` を実行してください。1.0.4 以降はリリースがすべて同じ証明書で署名されているため、**権限は保持されます**。新しいバージョンで**このまま開く**を一度押すだけです。
新バージョンの通知を受け取るには、メニューバーのメニューで**アップデートを確認…**を選ぶか、設定で**毎週確認**をオンにするか、このページで **Watch → Custom → Releases** を使ってください。

## 権限の一覧

| 権限 | 必要？ | 用途 | 許可しない場合 |
|---|---|---|---|
| **アクセシビリティ** | 必須 | どのDockアイコンにポインタがあるかの把握、ウインドウの切り替えと閉じる操作 | DockLens は動作しません |
| **画面収録** | 任意 | ライブサムネイルの表示（処理はMac内のみ） | プレビューはアプリアイコンとタイトルの一覧になります |
| **オートメーション**（Spotify / Music） | 任意 | 再生バー | 再生バーは出ません。初めて再生を押したときだけ確認されます |
| **カレンダー** | 任意 | カレンダーアイコンに今日のアジェンダを表示 | アジェンダは出ません。そこで**許可**をクリックしたときだけ確認されます |

## 機能

- Dockのアイコンにポインタを乗せると、そのアプリの全ウインドウをライブサムネイルで表示。クリックで切り替え
- プレビューから閉じる、最小化／復元、フルスクリーン。ヘッダーのボタンで新規ウインドウ、アプリを隠す、アプリを終了
- 最小化されたウインドウと別のSpaceのウインドウも表示（クリックでそのSpaceへ切り替え）
- 起動中のアプリで✕により閉じられたウインドウ（Notion、Slackなど）も一覧に残り、クリックで再表示
- **最近閉じた項目**：アプリで閉じたばかりのドキュメント（テキストエディット、プレビューなどファイルベースのアプリ）をプレビュー下部に表示。クリックでファイルを開き直し
- カレンダーのアジェンダ（今日、次に明日）と「参加」ボタン。カレンダーが起動していなくても使えます
- SpotifyとMusicの再生バー
- 画面収録なしでも動作（アイコンとタイトルの一覧）
- Dockは下・左・右のどれでもOK。自動的に隠す、拡大、複数ディスプレイにも対応
- [34言語](#言語)に対応。macOSの言語設定に従います
- イベント駆動：アイドル時はCPU 0%、ウェイクアップなし（メモリ約20〜30 MB、Apple シリコンでの実測）

<details>
<summary>プレビュー上のワンキー操作</summary>

ポインタがプレビュー上にあるとき：**W** でポインタ下のウインドウを閉じる、**M** で最小化／復元、**H** でアプリを隠す、**Q** でアプリを終了。それ以外のキーや ⌘ の組み合わせはそのまま通ります。不要な場合は設定でオフにできます。
</details>

## プライバシー

DockLens は、アップデートの確認を頼まない限り**ネットワークに一切接続しません**。サムネイルはローカルで撮影・表示され、Macの外には出ません。
唯一の接続はアップデート確認で、最新バージョン番号を読むためのGitHub APIへの1回のリクエストです。**アップデートを確認**をクリックしたとき、または設定で**毎週確認**をオンにしたときだけ送信されます（デフォルトはオフ）。あなたに関するデータは送信されません。

**最近閉じた項目**（閉じたドキュメント名）はメモリ内にのみ保持され、ディスクへの書き込みも外部への送信もなく、DockLens を終了すると消えます。記憶されるのはファイルだけで、Webページは対象外です。設定でオフにすると、すぐに消去されます。

私の言葉を信じる必要はありません。各権限を使うコードは [`DockLens/Core`](DockLens/Core) にあります：`DockObserver.swift`（アクセシビリティ：どのDockアイコンに乗っているか）、`ThumbnailService.swift`（画面収録：サムネイル）、`MediaController.swift`（オートメーション：Spotify / Music）、`CalendarAgenda.swift`（カレンダー：読み取り専用のアジェンダ）、`ClosedWindowStore.swift` / `ClosedWindowWatcher.swift`（メモリ内の「最近閉じた項目」）、`UpdateChecker.swift`（アップデート確認）。Little SnitchやLuLuなどのファイアウォールで、他の通信がないことを確認することもできます。

## FAQ

<details>
<summary><b>Dockのアイコンに乗せてもプレビューが出ない</b></summary>

1. **アクセシビリティ**が許可されているか確認します：システム設定 → プライバシーとセキュリティ → アクセシビリティで、DockLens がオンになっていること。すでにオンなら、一度オフにしてからオンに戻してください。
2. メニューバーのDockLensアイコンを開き、**ウインドウのプレビューを有効にする**にチェックが入っているか確認します。
3. プレビューはウインドウのあるアプリにだけ表示されます（常に表示したい場合は、設定で*ウインドウがなくてもプレビューを表示*をオンにします）。
4. アイコンの上にもう少し長く留まってみてください。ホバーの遅延は設定で調整できます。
</details>

<details>
<summary><b>サムネイルがアイコンとタイトルに置き換わる</b></summary>

**画面収録**の権限がないモードです。システム設定 → プライバシーとセキュリティ → 画面とシステムオーディオの収録で許可するか、DockLensのメニューで*ウインドウのサムネイルを有効にする…*をクリックしてください。
</details>

<details>
<summary><b>macOSに「DockLens は、Macを保護するためブロックされました」と出る</b></summary>

DockLens はまだAppleの公証を受けていません。システム設定 → プライバシーとセキュリティを開き、下へスクロールしてメッセージの横の**このまま開く**をクリックします。バージョンごとに一度だけの操作です。
</details>

<details>
<summary><b>アップデートすると権限は失われますか？</b></summary>

1.0.4 以降は失われません。すべてのリリースが同じ証明書で署名されているため、macOSが権限を保持します。新しいバージョンで**このまま開く**を一度押すだけです。
</details>

<details>
<summary><b>アンインストールするには？</b></summary>

メニューバーからDockLensを終了し、`/Applications` から `DockLens.app` を削除します（または `brew uninstall --cask docklens`）。*ログイン時に開く*を有効にしていた場合は、システム設定 → 一般 → ログイン項目からも削除してください。設定も消すには、`defaults delete com.firstfu.DockLens` を実行し、`~/Library/Caches/com.firstfu.DockLens` を削除します。
</details>

## 似たツールとの違い

[DockDoor](https://github.com/ejbills/DockDoor) と [AltTab](https://github.com/lwouis/alt-tab-macos) は、実績のある優れたツールです。DockDoor は無料のオープンソースで、機能もより豊富です（Alt+Tab型のスイッチャー、ジェスチャー、macOS 13以降、Intel対応）。DockLens はより小さく、macOS 26 が必要です。DockLens が加えているのは、閉じられていてもアプリが起動中のウインドウを一覧に残すこと、「参加」ボタン付きのカレンダーアジェンダ、34のインターフェース言語です。Alt+Tab型のスイッチャー、ジェスチャー、古いmacOSが必要な場合は、そちらを使ってください。

## 言語

34のインターフェース言語に対応し、macOSの言語設定で選ばれます。翻訳は**AIの支援を受けたもので、すべてがネイティブスピーカーに確認されているわけではありません**。おかしな表現を見つけたら、[翻訳の修正を報告](../../issues/new?template=translation.yml)するか、プルリクエストを送ってください（文字列は `DockLens/Resources/Localizable.xcstrings` にあります）。**ネイティブスピーカー募集中：**[issue #6](../../issues/6) をご覧のうえ、あなたの言語の確認にご協力ください。

<p align="center">
  <img src="assets/languages.png" width="780" alt="英語、繁体字中国語、日本語、ドイツ語、フランス語、スペイン語、アラビア語、ロシア語で表示したようこそ画面">
</p>

<details>
<summary>すべての言語</summary>

العربية, Català, Čeština, Dansk, Deutsch, Ελληνικά, English, Español, Suomi, Français, עברית, हिन्दी, Hrvatski, Magyar, Bahasa Indonesia, Italiano, 日本語, 한국어, Bahasa Melayu, Norsk bokmål, Nederlands, Polski, Português (Brasil), Português (Portugal), Română, Русский, Slovenčina, Svenska, ไทย, Türkçe, Українська, Tiếng Việt, 简体中文, 繁體中文.
</details>

## 検討中：👍で投票してください

実際に求めてくれる人がいるまでは作りません。必要だと思うものがあれば、そのissueに👍を付け、コメントで**どう使いたいか**を教えてください。

- [Alt+Tab型のウインドウスイッチャー](../../issues?q=is%3Aissue+label%3Aconsidering)
- [3本指ジェスチャーでプレビューを開く](../../issues?q=is%3Aissue+label%3Aconsidering)
- [Windows風のタスクバー](../../issues?q=is%3Aissue+label%3Aconsidering)
- [macOS 26 より古いバージョンへの対応](../../issues?q=is%3Aissue+label%3Aconsidering)

私は一人で開発しており、皆さんが本当に必要としているものを知りたいと思っています。バグやアイデアは [Issue](../../issues/new/choose) でお知らせください。

## ソースからビルド

Xcode 26 と [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）が必要です。

```sh
git clone https://github.com/firstfu/DockLens-app.git && cd DockLens-app
xcodegen generate
xcodebuild -project DockLens.xcodeproj -scheme DockLens -configuration Release -derivedDataPath build build
open build/Build/Products/Release/DockLens.app
```

Appleアカウントは不要です。ビルドはデフォルトでアドホック署名されます。自分の証明書で署名する場合（再ビルドしてもmacOSが権限を保持するように）は、[`Config/Signing.xcconfig`](Config/Signing.xcconfig) を参照してください。
テスト：`xcodebuild` コマンドの `build` を `test` に置き換えます。

## 同じ作者の別アプリ

[Liftoff](https://github.com/firstfu/Liftoff) — macOS 26 で廃止されたLaunchpadのグリッドを復活させ、ライブウインドウプレビューとワンクリックのスマート整理を加えたアプリ。無料・オープンソース、macOS 26 以降対応。

## ライセンス

[GPLv3](LICENSE)。自由に使用、調査、改変、共有できます。配布する改変版は、同じライセンスのもとでオープンソースのままにする必要があります。
