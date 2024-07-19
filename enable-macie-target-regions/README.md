# Amazon Macie 指定リージョン有効化スクリプト

指定したリージョンで Amazon Macie を有効にするスクリプトです。

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

1. cd でディレクトリ iij-aws-secure-baseline/enable-macie-target-regions/ へ移動します。
2. 引数に Amazon Macie を有効化したいリージョンを指定し、enable-macie-target-regions.sh を実行します。  
有効化したいリージョンは、カンマ区切りで複数指定することが可能です。  
例えば、ap-northeast-1(東京)、us-east-1(バージニア北部)、eu-west-2(ロンドン)の3つのリージョンで Amazon Macie を有効化したい場合、以下のように実行します。  

```sh
$ cd iij-aws-secure-baseline/enable-macie-target-regions/
$ ./enable-macie-target-regions.sh ap-northeast-1,us-east-1,eu-west-2
# 以下のINFOメッセージが表示されれば実行終了です。
2022-09-20T03:08:27 [INFO] (enable-macie-target-regions.sh:117:main) 指定リージョンのAmazon Macieを有効化 正常終了
```

### 4. ログ確認

- エラーが発生していないか、ログを確認します。

```sh
$ grep ERROR enable-macie-target-regions.log
$ # ERRORメッセージがヒットしなければ正常です。
```

### 5. クリーンアップ

- 最後にダウンロードしたスクリプトを削除します。

```sh
$ cd ~
$ rm -rf iij-aws-secure-baseline/
```
