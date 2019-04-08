#!/bin/bash
#set -eux
#==================================================================================================
# ディレクトリ比較
#
# 概要
#   指定した 旧ディレクトリ、新ディレクトリ 配下のファイル群を比較して
#   新規、削除、更新ファイルの差分一覧を表示します。
#
# 引数
#   $1: 旧ディレクトリ
#   $2: 新ディレクトリ
#
# オプション
#   -v: 詳細表示オプション
#       新規、削除、更新ファイルの差分一覧と合わせて
#       更新ファイル内の差分を表示します。
#
# 戻り値
#    0: 一致した場合
#    3: 差分を検出した場合
#    6: エラー発生時
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 環境設定
#--------------------------------------------------------------------------------------------------
readonly CMD_NAME=$(basename "$0")
readonly USAGE="Usage: $CMD_NAME [-v] dir_old dir_new"

readonly EXITCODE_SUCCESS=0
readonly EXITCODE_WARN=3
readonly EXITCODE_ERROR=6

dir_cur=$(pwd)
dir_work="/tmp/${CMD_NAME}_$$"
path_old="${dir_work}/files_old"
path_new="${dir_work}/files_new"
path_all="${dir_work}/files_all"
path_common="${dir_work}/files_common"
path_tmp="${dir_work}/tmp"
path_out_tmp="${dir_work}/output"

has_diff="false"
is_verbose="false"


#--------------------------------------------------------------------------------------------------
# 事前処理
#--------------------------------------------------------------------------------------------------
# 強制終了時の処理定義
trap "rm -fr ${dir_work}; exit ${EXITCODE_ERROR}" SIGHUP SIGINT SIGQUIT SIGTERM

# オプション解析
while :; do
  case $1 in
    -v)
      is_verbose="true"
      shift
      ;;
    --) shift
      break
      ;;
    -*)
      echo "${USAGE}" >&2
      exit ${EXITCODE_ERROR}
      ;;
    *)
      break
      ;;
  esac
done

# 引数チェック
if [[ $# -ne 2 ]]; then
  echo "${USAGE}" >&2
  exit ${EXITCODE_ERROR}
fi

# 旧ディレクトリ
dir_old="${1:?}"
if [[ ! -d "${dir_old}" ]]; then
  echo "${dir_old} is NOT a directory." >&2
  exit ${EXITCODE_ERROR}
fi

# 新ディレクトリ
dir_new="${2:?}"
if [[ ! -d "${dir_new}" ]]; then
  echo "${dir_new} is NOT a directory." >&2
  exit ${EXITCODE_ERROR}
fi


#--------------------------------------------------------------------------------------------------
# 本処理
#--------------------------------------------------------------------------------------------------
# 作業ディレクトリの作成
mkdir -p "${dir_work}"

# 旧ファイルリスト
cd "${dir_old}" || exit ${EXITCODE_ERROR}
find . \( -type f -o -type l \) -print | sort > ${path_old}
cd "${dir_cur}" || exit ${EXITCODE_ERROR}

# 新ファイルリスト
cd "${dir_new}" || exit ${EXITCODE_ERROR}
find . \( -type f -o -type l \) -print | sort > ${path_new}
cd "${dir_cur}" || exit ${EXITCODE_ERROR}

# 新旧を含めた全ファイルリスト
cat "${path_old}" "${path_new}" | sort | uniq    >"${path_all}"
# 新旧どちらにも存在するファイルリスト
cat "${path_old}" "${path_new}" | sort | uniq -d >"${path_common}"

# 新規ファイルの検出
cat "${path_old}" "${path_all}" | sort | uniq -u >"${path_tmp}"
if [[ -s "${path_tmp}" ]]; then
  has_diff=true
  for cur_file_path in $(cat "${path_tmp}"); do
    cur_file_path=$(expr "${cur_file_path}" : '..\(.*\)')
    echo "A ${cur_file_path}" >>"${path_out_tmp}"
  done
fi

# 削除ファイルの検出
cat "${path_new}" "${path_all}" | sort | uniq -u >"${path_tmp}"
if [[ -s "${path_tmp}" ]]; then
  has_diff=true
  for cur_file_path in $(cat "${path_tmp}"); do
    cur_file_path=$(expr "${cur_file_path}" : '..\(.*\)')
    echo "D ${cur_file_path}" >>"${path_out_tmp}"
  done
fi

# 更新チェック
for cur_file_path in $(cat ${path_common}); do
  if cmp -s "${dir_old}/${cur_file_path}" "${dir_new}/${cur_file_path}"; then
    has_diff=true
    cur_file_path=$(expr "${cur_file_path}" : '..\(.*\)')
    echo "M ${cur_file_path}" >>"${path_out_tmp}"
    if [[ "${is_verbose}" == "true" ]]; then
      diff "${dir_old}/${cur_file_path}" "${dir_new}/${cur_file_path}" >>"${path_out_tmp}"
    fi
  fi
done


#--------------------------------------------------------------------------------------------------
# 事後処理
#--------------------------------------------------------------------------------------------------
exitcode=${EXITCODE_SUCCESS}
if [[ "${has_diff}" == "true" ]]; then
  exitcode=${EXITCODE_WARN}
  # 詳細出力モードの場合、ソートせずに結果を表示 ※ソートすると崩れるため
  if [[ "${is_verbose}" = "true" ]]; then
    cat "${path_out_tmp}"
  else
    cat "${path_out_tmp}" | sort -k 2
  fi
fi

rm -fr "${dir_work}"
exit ${exitcode}
