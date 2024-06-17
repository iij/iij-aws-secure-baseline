#!/bin/bash
###################################################################################
# Title         : enable-macie-all-regions.sh
# Description   : 全リージョンのAmazon Macieを有効化する。
#               : なお、以下のセキュアベースラインが提供するS3バケットは自動検出対象から除外する。
#               : ・CloudTrailログ記録用S3バケット
#               : ・AWS Configログ保管用S3バケット
#               : ・CloudTrailログアクセスログ保管用S3バケット
#               : ・Athenaクエリ結果保管用S3バケット
# Author        : IIJ ytachiki
# Date          : 2024.05.28
###################################################################################
# 実行条件：Macieを有効化したいAWSアカウントのCloudShellで実行すること。
# 引数：なし
# リターンコード：0 (成功)、1 (失敗)
###################################################################################

# ログファイル
LOGFILE=$(pwd)/enable-macie-all-regions.log

######################
# 関数：INFOログ出力
######################
function info() {
    local fname=${BASH_SOURCE[1]##*/}
    echo -e "$(date '+%Y-%m-%dT%H:%M:%S') [INFO] (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $@" | tee -a ${LOGFILE}
}

######################
# 関数：ERRORログ出力
######################
function err() {
    local fname=${BASH_SOURCE[1]##*/}
    echo -e "$(date '+%Y-%m-%dT%H:%M:%S') [ERROR] (${fname}:${BASH_LINENO[0]}:${FUNCNAME[1]}) $@" | tee -a ${LOGFILE}
}

#######################################################
# メイン関数
# 引数：なし
# リターンコード：0 (成功)、1 (失敗)
#######################################################
function main(){
    # 環境変数DEBUG_MODEがonの場合、ステップ実行機能を有効にする。
    if [[ "${DEBUG_MODE}" = "on" ]]; then trap 'read -p "$0($LINENO) $BASH_COMMAND"' DEBUG ;fi
    
    ### 変数宣言 ###
    local regions # リージョン一覧
    local iijsecbase_buckets # セキュアベースライン提供S3バケット一覧
    local result # コマンド実行結果
    
    # cloudshell-userユーザで実行されていることの確認（CloudShellで実行されていることの確認）
    if [[ "$(whoami)" != "cloudshell-user" ]] ; then
        err '実行ユーザがcloudshell-userではありません。CloudShellで実行していることを確認して下さい。'
        return 1
    fi
    
    # リージョン一覧を取得
    info 'リージョン一覧を取得'
    info 'aws ec2 describe-regions --query Regions[].RegionName --output text'
    result=$(aws ec2 describe-regions --query Regions[].RegionName --output text 2>&1)
    if [[ $? -eq 0 ]]; then
        info "${result}"
        regions=${result}
    else
        err "${result}"
        err 'リージョン一覧の取得に失敗しました。'
        return 1
    fi
    
    # 全リージョンでMacie及び自動検出を有効化
    for region in ${regions}; do
        # Macieを有効化
        info "${region}リージョンのMacieを有効化"
        info "aws macie2 enable-macie --region ${region} --output text"
        result=$(aws macie2 enable-macie --region ${region} --output text 2>&1)
        if [[ $? -eq 0 ]]; then
            info "${region}リージョンのMacieの有効化に成功しました。"
        elif [[ "${result}" = *"Macie has already been enabled"* ]]; then
            info "${result}"
            info "${region}リージョンのMacieは既に有効化済みでした。"
        else
            err "${result}"
            err "${region}リージョンのMacieの有効化に失敗しました。"
            return 1
        fi

        # Macieの有効化を確認
        info "${region}リージョンのMacieの有効化を確認"
        info "aws macie2 get-macie-session --region ${region} --query "status" --output text"
        result=$(aws macie2 get-macie-session --region ${region} --query "status" --output text 2>&1)

        if [[ $? -eq 0 ]]; then
            if [ "$result" == "ENABLED" ]; then
                info "${result}"
                info "${region}リージョンのMacieの有効化を確認しました"
            else
                err "${result}"
                err "${region}リージョンのMacieが有効化されていません"
                return 1        
            fi
        else
            if [[ "${result}" = *"Macie is not enabled"* ]]; then
                err "${result}"
                err "${region}リージョンのMacieが有効化されていません"
                return 1
            else
                err "${result}"
                err "${region}リージョンのMacieの有効化の確認に失敗しました"
                return 1                
            fi
        fi   
    done

    # セキュアベースラインが提供するS3バケットを自動検出対象から除外
    info 'セキュアベースラインが提供するS3バケットを自動検出対象から除外'

    # セキュアベースラインが提供するS3バケット一覧を取得
    info 'セキュアベースラインが提供するS3バケット一覧を取得'
    info "aws s3api list-buckets --query \"Buckets[?contains(Name, 'iijsecbase')].Name\" --output text"
    result=$(aws s3api list-buckets --query "Buckets[?contains(Name, 'iijsecbase')].Name" --output text 2>&1)
    if [ $? -eq 0 ]; then
        info "${result}"
        iijsecbase_buckets=${result}
    else
        # エラーが発生した場合、エラーメッセージを表示
        err "${result}"
        err 'セキュアベースラインが提供するS3バケット一覧の取得に失敗しました。'
        return 1
    fi

    # S3バケット一覧の全S3バケットを自動検出対象から除外
    for bucket in ${iijsecbase_buckets}; do
        info "S3バケット ${bucket} を自動検出対象から除外"

        # S3バケットのリージョンを取得
        info "S3バケット ${bucket} のリージョンを取得"
        info "aws s3api head-bucket --bucket ${bucket} --query 'BucketRegion' --output text"
        result=$(aws s3api head-bucket --bucket ${bucket} --query 'BucketRegion' --output text)
        if [ $? -eq 0 ]; then
            info "${result}"
            region=${result}
        else
            err "${result}"
            err "S3バケット ${bucket} のリージョンを取得に失敗しました。"
            return 1
        fi

        # S3バケットが存在するリージョンのMacie自動検出のClassification Scope Idを取得
        info "${region}リージョンのMacie自動検出のClassification Scope Idを取得"
        info "aws macie2 get-automated-discovery-configuration --region ${region} --query 'classificationScopeId' --output text"
        result=$(aws macie2 get-automated-discovery-configuration --region ${region} --query 'classificationScopeId' --output text)
        if [ $? -eq 0 ]; then
            info "${result}"
            id=${result}
        else
            err "${result}"
            err "${region}リージョンのMacie自動検出のClassification Scope Id取得に失敗しました。"
            return 1
        fi

        # S3バケットを自動検出対象から除外
        info "S3バケット ${bucket} を自動検出対象から除外"
        info "aws macie2 update-classification-scope --id ${id} --region ${region} --s3 '{"excludes":{"bucketNames":["\'${bucket}\'"],"operation":"ADD"}}'"
        result=$(aws macie2 update-classification-scope --id ${id} --region ${region} --s3 '{"excludes":{"bucketNames":["'${bucket}'"],"operation":"ADD"}}' --output text)

        if [ $? -eq 0 ]; then
            info "S3バケット ${bucket} の自動検出対象除外に成功しました。"
        else
            err "${result}"
            err "S3バケット ${bucket} を自動検出対象から除外に失敗しました。"
            return 1
        fi

        # S3バケットの自動検出対象除外を確認
        info "Macieの自動検出対象除外S3バケットの一覧を取得"
        info "Macieの自動検出除外S3バケットの一覧を取得"
        info "aws macie2 get-classification-scope --id ${id} --region ${region} --query s3.excludes.bucketNames"
        result=$(aws macie2 get-classification-scope --id ${id} --region ${region} --query s3.excludes.bucketNames)
        if [ $? -eq 0 ]; then
            info "${result}"
            excludes_buckets=${result}
        else
            err "${result}"
            err "Macieの自動検出対象除外S3バケット一覧の取得に失敗しました。"
            return 1
        fi
        # 自動検出除外S3バケット一覧にセキュアベースライン提供バケットが含まれているか確認
        if [[ "${excludes_buckets}" =~ "${bucket}" ]]; then
            info "S3バケット ${bucket} は除外設定されています。"
        else
            err "S3バケット ${bucket} は除外設定されていません。"
            return 1
        fi  
    done

    return 0
}

###########################################################
# メイン関数へのエントリー
###########################################################
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    
    # 環境変数DEBUG_MODEがonの場合、ステップ実行機能を有効にする。
    if [[ "${DEBUG_MODE}" = "on" ]]; then trap 'read -p "$0($LINENO) $BASH_COMMAND"' DEBUG ;fi
    
    info '全リージョンのAmazon macieを有効化 開始'
    main $1 $2
    if [[ $? = 0 ]]; then
        info '全リージョンのAmazon macieを有効化 正常終了'
        exit 0
    else
        err '全リージョンのAmazon macieを有効化 異常終了'
        exit 1
    fi
    
fi
