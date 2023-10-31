#!/bin/bash
###################################################################################
# Title         : enable-detective-target-regions.sh
# Description   : 指定リージョンのAmazon Detectiveを有効化。
# Author        : IIJ takeda-m
# Date          : 2023.10.26
###################################################################################
# 実行条件：Detectiveを有効化したいAWSアカウントのCloudShellで実行すること。
# 引数：第１引数（必須）：有効化対象リージョン ※複数ある場合はカンマ区切りで指定（例、ap-northeast-1,ap-northeast-3,us-east-1）
# リターンコード：0 (成功)、1 (失敗)
###################################################################################

# ログファイル
LOGFILE=$(pwd)/enable-detective-target-regions.log

# タグ
NAME_TAGKEY="Name" # Nameタグのキー値
NAME_TAGVAL="iijsecbase-detective" # Nameタグのキー値
CREATEDBY_TAGKEY="CreatedBy" # CreatedByタグのキー
CREATEDBY_TAGVAL="iijsecbase" # CreatedByタグの値
IIJCOSTTAG_TAGKEY="iij-cost-tag" # iij-cost-tagタグのキー
IIJCOSTTAG_TAGVAL="iijsecbase" # iij-cost-tagタグの値

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
  local regions # リージョン一覧
  local result # コマンド実行結果
  local detective_arn # DetectiveリソースのARN

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

  # Detectiveを有効化
  for region in ${TARGET_REGIONS//,/ }; do
    # Detective有効化
    info "${region}リージョンのDetectiveを有効化"
    info "aws detective create-graph --region ${region} --output text"
    result=$(aws detective create-graph --region ${region} --output text 2>&1)
    if [[ $? -ne 0 ]]; then
      err "${result}"
      err "${region}リージョンのDetectiveの有効化に失敗しました。"
      return 1
    else
      info "${result}"
      detective_arn=${result}
    fi
    # タグ付け
    info "${region}リージョンのDetectiveへのタグ付け"
    info "aws detective tag-resource --resource-arn ${detective_arn} --tags ${NAME_TAGKEY}=${NAME_TAGVAL},${CREATEDBY_TAGKEY}=${CREATEDBY_TAGVAL},${IIJCOSTTAG_TAGKEY}=${IIJCOSTTAG_TAGVAL} --region ${region} --output text"
    result=$(aws detective tag-resource --resource-arn ${detective_arn} --tags ${NAME_TAGKEY}=${NAME_TAGVAL},${CREATEDBY_TAGKEY}=${CREATEDBY_TAGVAL},${IIJCOSTTAG_TAGKEY}=${IIJCOSTTAG_TAGVAL} --region ${region} --output text 2>&1)
    if [[ $? -ne 0 ]]; then
      err "${result}"
      err "${region}リージョンのDetectiveへのタグ付けに失敗しました。"
      return 1
    fi
  done

  # Detective有効化の確認
  for region in ${TARGET_REGIONS//,/ }; do
    # Detective有効化確認
    info "${region}リージョンのDetective有効化を確認"
    info "aws detective list-graphs --query GraphList[].Arn --region ${region} --output text"
    result=$(aws detective list-graphs --query GraphList[].Arn --region ${region} --output text 2>&1)
    if [[ $? -ne 0 ]]; then
      err "${result}"
      err "${region}リージョンのDetective有効化の確認に失敗しました。"
      return 1
    elif [[ -z "$result" ]]; then
      err "${result}"
      err "${region}リージョンのDetectiveが有効になっていません。"
      return 1
    else
      info "${result}"
      detective_arn=${result}
    fi
    # タグ付け確認
    info "${region}リージョンのDetectiveタグ付けの確認"
    info "aws detective list-tags-for-resource --resource-arn ${detective_arn} --query \"Tags\" --region ${region}"
    result=$(aws detective list-tags-for-resource --resource-arn ${detective_arn} --query "Tags" --region ${region} 2>&1)
    if [[ $? -ne 0 ]]; then
      err "${result}"
      err "${region}リージョンのDetectiveタグ付けの確認に失敗しました。"
      return 1
    else
      info ${result}
      name_tag_value=$(echo ${result} | jq -r .${NAME_TAGKEY})
      createdby_tag_value=$(echo ${result} | jq -r .${CREATEDBY_TAGKEY})
      iijcosttag_tag_value=$(echo ${result} | jq -r .\"${IIJCOSTTAG_TAGKEY}\")
      if [[ "${name_tag_value}" != "${NAME_TAGVAL}" ]] || [[ "${createdby_tag_value}" != "${CREATEDBY_TAGVAL}" ]] || [[ "${iijcosttag_tag_value}" != "${IIJCOSTTAG_TAGVAL}" ]]; then
        err "${region}リージョンのDetectiveに正しく付与されていないタグが存在しました。"
        return 1
      fi
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

  info '指定リージョンのAmazon Detectiveを有効化 開始'
  main $1 $2
  if [[ $? = 0 ]]; then
    info '指定リージョンのAmazon Detectiveを有効化 正常終了'
    exit 0
  else
    err '指定リージョンのAmazon Detectiveを有効化 異常終了'
    exit 1
  fi

fi