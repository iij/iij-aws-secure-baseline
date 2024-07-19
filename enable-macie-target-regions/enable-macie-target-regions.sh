#!/bin/bash
###################################################################################
# Title         : enable-macie-target-regions.sh
# Description   : 指定リージョンのAmazon Macieを有効化する。
#               : また、ポリシー検出結果と機密データ検出結果のSecurity Hubへの発行を設定する。
# Author        : IIJ ytachiki
# Date          : 2024.06.05
###################################################################################
# 実行条件：Macieを有効化したいAWSアカウントのCloudShellで実行すること。
# 引数：第１引数（必須）：有効化対象リージョン ※複数ある場合はカンマ区切りで指定（例、ap-northeast-1,ap-northeast-3,us-east-1）
# リターンコード：0 (成功)、1 (失敗)
###################################################################################

# ログファイル
LOGFILE=$(pwd)/enable-macie-target-regions.log

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

#########################################################
# 関数：引数チェック
# 引数：第１引数（必須）：有効化対象リージョン ※複数ある場合はカンマ区切りで指定（例、ap-northeast-1,ap-northeast-3,us-east-1）
# リターンコード：0 (成功)、1 (失敗)
#########################################################
function arg_check() {

  ### 変数宣言 ###
  local result # コマンド実行結果

  # 引数の数を確認
  if [[ $# -lt 1 ]] ; then
    err 引数が足りません。
    err 使用方法）${BASH_SOURCE[1]##*/} 有効化対象リージョン（※複数ある場合はカンマ区切りで指定）
    err 使用例）${BASH_SOURCE[1]##*/} ap-northeast-1,ap-northeast-3,us-east-1
    return 1
  fi

  # 指定された有効化対象リージョンが利用可能か確認
  for region in ${1//,/ }; do
    result=$(aws ec2 describe-regions --filters "Name=region-name, Values=$region" --output text 2>&1)
    if [[ $? -ne 0 ]] || [[ -z "${result}" ]] ; then
      err 指定されたリージョン $region は利用できません。正しいリージョンか確認して下さい。
      return 1
    fi
  done

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

    ### 定数宣言 ###
    local -r TARGET_REGIONS=$1 # 有効化対象リージョン ※複数ある場合はカンマ区切りで指定（例、ap-northeast-1,ap-northeast-3,us-east-1）
    
    ### 変数宣言 ###
    local result # コマンド実行結果
    
    # cloudshell-userユーザで実行されていることの確認（CloudShellで実行されていることの確認）
    if [[ "$(whoami)" != "cloudshell-user" ]] ; then
        err '実行ユーザがcloudshell-userではありません。CloudShellで実行していることを確認して下さい。'
        return 1
    fi

    # 引数チェック
    arg_check $1
    if [[ $? -ne 0 ]] ; then
      err 引数チェックでエラーが発生しました。
      return 1
    fi
    
    # 指定リージョンでMacie及び自動検出を有効化
    for region in ${TARGET_REGIONS//,/ }; do
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

        # Macieの検出結果をSecurity Hubに発行
        info "${region}リージョンのポリシー検出結果と機密データ検出結果のSecurity Hub発行の設定"
        info "aws macie2 put-findings-publication-configuration --security-hub-configuration '{"publishClassificationFindings": true,"publishPolicyFindings": true}' --region ${region}"
        result=$(aws macie2 put-findings-publication-configuration --security-hub-configuration '{"publishClassificationFindings": true,"publishPolicyFindings": true}' --region ${region})

        if [[ $? -eq 0 ]]; then
            info "${region}リージョンのポリシー検出結果と機密データ検出結果のSecurity Hub発行の設定に成功しました"
        else
            err "${result}"
            err "${region}リージョンのポリシー検出結果と機密データ検出結果のSecurity Hub発行の設定に失敗しました"
            return 1
        fi
        
        # Security Hubに発行の設定の確認
        info "${region}リージョンのポリシー検出結果と機密データ検出結果のSecurity Hub発行設定の確認"
        info "aws macie2 get-findings-publication-configuration --region ${region}"
        result=$(aws macie2 get-findings-publication-configuration --region ${region})
        
        if [[ $? -eq 0 ]]; then
            classification_findings=$(echo "${result}" | jq -r ".securityHubConfiguration.publishClassificationFindings")
            publishPolicy_findings=$(echo "${result}" | jq -r ".securityHubConfiguration.publishPolicyFindings")
        
            if [[ "$classification_findings" == "true" ]] && [[ "$publishPolicy_findings" == "true" ]]; then
                info "${region}リージョンのSecurity Hub発行設定を確認しました"
            else
                err "${region}リージョンのSecurity Hub発行設定が有効ではありません"
                return 1
            fi
        else
            err "${result}"
            err "${region}リージョンのポリシー検出結果と機密データ検出結果のSecurity Hub発行設定の確認に失敗しました"
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
    
    info '指定リージョンのAmazon macieを有効化 開始'
    main $1 $2
    if [[ $? = 0 ]]; then
        info '指定リージョンのAmazon macieを有効化 正常終了'
        exit 0
    else
        err '指定リージョンのAmazon macieを有効化 異常終了'
        exit 1
    fi
    
fi

