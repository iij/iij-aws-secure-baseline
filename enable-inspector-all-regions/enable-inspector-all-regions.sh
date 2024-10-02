#!/bin/bash
###################################################################################
# Title         : enable-inspector-all-regions.sh
# Description   : 全リージョンのAmazon Inspectorを有効化する。
# Author        : IIJ ytachiki
# Date          : 2024.08.22
###################################################################################
# 実行条件：Inspectorを有効化したいAWSアカウントのCloudShellで実行すること。
# 引数：なし
# リターンコード：0 (成功)、1 (失敗)
###################################################################################

# ログファイル
LOGFILE=$(pwd)/enable-inspector-all-regions.log

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

######################################################
# 関数：Inspector有効化
# 引数：第１引数（必須）：リージョン名（例、ap-northeast-1）
# リターンコード：0 (成功)、1 (失敗)
######################################################
function enable_inspector_for_region() {
    local region=$1
    local resources=("EC2" "ECR" "LAMBDA" "LAMBDA_CODE")

    # Inspectorを有効化
    info "${region}リージョンのInspectorを有効化"
    info "aws inspector2 enable --resource-types ${resources[*]} --region ${region} --output text"
    result=$(aws inspector2 enable --resource-types ${resources[*]} --region ${region} --output text 2>&1)
    if [[ $? -eq 0 ]]; then
        info "${region}リージョンのInspectorの有効化に成功しました。"
    elif [[ "${result}" = *"Lambda code scanning is not supported"* ]]; then
        info "${region}リージョンはLambda code sccaningに対応していません"
        # LAMBDA_CODEを除外する
        resources=("EC2" "ECR" "LAMBDA")
        info "aws inspector2 enable --resource-types ${resources[*]} --region ${region} --output text"
        result=$(aws inspector2 enable --resource-types ${resources[*]} --region ${region} --output text 2>&1)
        if [[ $? -eq 0 ]]; then
            info "${region}リージョンのInspectorの有効化に成功しました。"
        else
            err "${result}"
            err "${region}リージョンのInspectorの有効化に失敗しました。"
            return 1
        fi
    else
        err "${result}"
        err "${region}リージョンのInspectorの有効化に失敗しました。"
        return 1
    fi

    # 各リソースのInspector有効化の確認
    for resource in "${resources[@]}"; do
        local lower_resource=$(echo "${resource}" | tr '[:upper:]' '[:lower:]')
        if [[ "$lower_resource" ==  "lambda_code" ]] then
            lower_resource=lambdaCode
        fi
        check_enable_inspector ${region} "${resource}" "${lower_resource}"
        if [[ $? -ne 0 ]]; then
            return 1
        fi
    done

    return 0
}

######################################################
# 関数：Inspector有効化の確認
# 引数：第１引数（必須）：リージョン名（例、ap-northeast-1）
#       第２引数（必須）：リソース名（例、EC2）
#       第２引数（必須）：リソース名小文字（例、ec2）
# リターンコード：0 (成功)、1 (失敗)
######################################################
function check_enable_inspector(){
  # 環境変数DEBUG_MODEがonの場合、ステップ実行機能を有効にする。https://qiita.com/mashumashu/items/ee436b770806e8b8176f
  if [[ "${DEBUG_MODE}" = "on" ]]; then trap 'read -p "$0($LINENO) $BASH_COMMAND"' DEBUG ;fi

  ### 定数宣言 ###
  local -r REGION=$1 # リージョン名
  local -r RESOURCE=$2 # リソース指定(大文字)
  local -r LOWER_RESOURCE=$3 # リソース指定（小文字)
  local -r STATUS_CHECK_RETRY_COUNT=10 # ステータスチェック回数

  ### 変数宣言 ###
  local is_err=true # エラーフラグ
  local result # コマンド実行結果
  
  info "${RESOURCE}の有効化の確認"
  for ((i=0; i < ${STATUS_CHECK_RETRY_COUNT}; i++)); do
    # Inspectorのステータスを取得
    info Inspectorのステータスを取得
    info aws inspector2 batch-get-account-status --region ${REGION} --query "accounts[].resourceState.${LOWER_RESOURCE}" --output text
    result=$(aws inspector2 batch-get-account-status --region ${REGION} --query "accounts[].resourceState.${LOWER_RESOURCE}" --output text 2>&1)
    if [[ $? -ne 0 ]]; then
      err "${result}"
      err Inspectorのステータスの取得に失敗しました。
      err "${REGION}リージョンのInspectorの有効化の確認に失敗しました。"
      break
    elif [[ "$result" == "ENABLED" ]]; then
      info "${result}"
      info "${RESOURCE}のステータスは${result}です。"
      is_err=false
      break
    else
      info "${result}"
      info "${RESOURCE}のステータスは${result}です。10秒後にリトライします。"
    fi

    # リトライの回数が上限に達した場合の処理
    if [[ $i -eq ${STATUS_CHECK_RETRY_COUNT}-1 ]]; then
      err "${result}"
      err リトライ回数を超えました。
      err "${REGION}リージョンのInspectorの有効化の確認に失敗しました。"
      return 1
    fi

    sleep 10s
  done
  
  if "${is_err}"; then
    return 1
  fi
  
  info "${REGION}リージョンの${RESOURCE}の有効化を確認しました"
  return 0
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
    local result # コマンド実行結果
    local resources=("EC2" "ECS" "LAMBDA" "LAMBDA_CODE") # リソースタイプの配列
    
    # cloudshell-userユーザで実行されていることの確認（CloudShellで実行されていることの確認）
    if [[ "$(whoami)" != "cloudshell-user" ]] ; then
        err '実行ユーザがcloudshell-userではありません。CloudShellで実行していることを確認して下さい。'
        return 1
    fi
    
    # リージョン一覧を取得
    info リージョン一覧を取得
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
    
    # 全リージョンでInspectorを有効化
    info 全リージョンでInspectorを有効化
    for region in ${regions}; do
        enable_inspector_for_region ${region}
        if [[ $? -ne 0 ]]; then
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
    
    info '全リージョンのAmazon Inspectorを有効化 開始'
    main $1 $2
    if [[ $? = 0 ]]; then
        info '全リージョンのAmazon Inspectorを有効化 正常終了'
        exit 0
    else
        err '全リージョンのAmazon Inspectorを有効化 異常終了'
        exit 1
    fi
    
fi