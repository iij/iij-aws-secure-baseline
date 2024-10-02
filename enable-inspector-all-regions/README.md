# Amazon Inspector 全リージョン有効化スクリプト

Amazon Inspector を全リージョンで有効にするスクリプトです。

## 前提条件

- AWS管理ポリシー「AdministratorAccess」がアタッチされたユーザでAWS環境へログインして下さい。

## 実行方法

このスクリプトは CloudShell にて実行することが可能です。

### 1. CloudShell 起動

- AWS マネジメントコンソールの [>_] アイコン(画面右上のアカウント名の隣)をクリックして CloudShell を起動します。

### 2. スクリプトダウンロード

- 「git clone」でスクリプトをダウンロードします。

```sh
$ git clone https://github.com/iij/iij-aws-secure-baseline
```

### 3. スクリプト実行

1. cd でディレクトリ iij-aws-secure-baseline/enable-Inspector-all-regions/ へ移動します。
2. enable-Inspector-all-regions.sh を実行します。

```sh
$ cd iij-aws-secure-baseline/enable-Inspector-all-regions/
$ ./enable-Inspector-all-regions.sh
# 以下のINFOメッセージが表示されれば実行終了です。
2022-09-20T03:08:27 [INFO] (enable-Inspector-all-regions.sh:117:main) 全リージョンのAmazon Inspectorを有効化 正常終了
```

### 4. ログ確認

- エラーが発生していないか、ログを確認します。

```sh
$ grep ERROR enable-Inspector-all-regions.log
$ # ERRORメッセージがヒットしなければ正常です。
```

### 5. クリーンアップ

- 最後にダウンロードしたスクリプトを削除します。

```sh
$ cd ~
$ rm -rf iij-aws-secure-baseline/
```