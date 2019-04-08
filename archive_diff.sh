#!/bin/bash
#set -eux
#==================================================================================================
# アーカイブファイル内容比較
#
# 概要
#   指定した 旧アーカイブ、新アーカイブ を展開したディレクトリ構成を比較して
#   新規、削除、更新ファイルの差分一覧を表示します。
#
# 引数
#   $1: 旧アーカイブ
#   $2: 新アーカイブ
#
# オプション
#   -v: 詳細表示オプション
#       新規、削除、更新ファイルの差分一覧と合わせて
#       更新ファイル内の差分を表示します。
#
# 戻り値
#   0: 一致した場合
#   3: 差分を検出した場合
#   6: エラー発生時
#
# 出力
#   標準出力  : 比較結果
#   標準エラー: ログ
#
# 前提
#   ・dir_diff.sh と並びのディレクトリに配置されていること
#
#==================================================================================================
#--------------------------------------------------------------------------------------------------
# 環境設定
#--------------------------------------------------------------------------------------------------
# 依存チェック
cd $(cd $(dirname $0); pwd)
if [[ ! -f "./dir_diff.sh" ]]; then echo "$(pwd)/dir_diff.sh is not exist."; exit 1; fi

readonly CMD_NAME=$(basename $0)
readonly USAGE="Usage: ${CMD_NAME} [-v] PATH_OLD PATH_NEW"

readonly EXITCODE_SUCCESS=0
readonly EXITCODE_WARN=3
readonly EXITCODE_ERROR=6

dir_work="/tmp/${CMD_NAME}_$$"
dir_old="${dir_work}/old"
dir_new="${dir_work}/new"
dir_tmp_root="${dir_work}/tmp"

# 対応拡張子
ALLOW_EXTS=()
ALLOW_EXTS+=( zip )
ALLOW_EXTS+=( tar.gz )
ALLOW_EXTS+=( tgz )
ALLOW_EXTS+=( jar )
ALLOW_EXTS+=( war )
ALLOW_EXTS+=( ear )


#--------------------------------------------------------------------------------------------------
# 関数定義
#--------------------------------------------------------------------------------------------------
#------------------------------------------------------------------------------
# 拡張子取得
#
# 引数
#   $1: 対象ファイルパス
#------------------------------------------------------------------------------
function get_ext() {
  local _path="${1:?}"
  local _ext="${_path##*.}"

  # 変数展開結果を確認
  if [ "${_ext}" = "gz" ]; then
    # gzの場合、2重拡張子を確認 ※tar.gzのみ対応
    if [ "$(basename ${_path} .tar.gz)" = "$(basename ${_path})" ]; then
      _ext="tar.gz"
    fi

  elif [ "${_ext}" = "${_path}" ]; then
    # pathそのままの場合、拡張子なし
    _ext=""
  fi

  echo "${_ext}"
  return ${EXITCODE_SUCCESS}
}

#------------------------------------------------------------------------------
# 再帰アーカイブ展開
#
# 引数
#   $1: 対象ファイルパス
#   $2: 出力ディレクトリ ※再帰呼び出し時は指定なし＝対象ファイルを展開後に削除
#------------------------------------------------------------------------------
function recursive_expand() {
  local _path_archive="${1:?}"
  local _dir_out_parent="${2:?}"
  local _is_remove="false"

  echo "$(date '+%Y-%m-%d %T') -- ${FUNCNAME[0]} $*" >&2

  if [[ "${_dir_out_parent}" == "" ]]; then
    # 出力ディレクトリが指定されていない（再帰呼び出し）場合
    # アーカイブファイルと同名のディレクトリに出力させる
    _dir_out_parent="$(dirname ${_path_archive})"
    # アーカイブファイルを展開後に削除
    _is_remove="true"
  fi

  local _name_archive="$(basename ${_path_archive})"
  local _dir_out="${_dir_out_parent}/${_name_archive}"
  local _dir_out_tmp="${_dir_out}_tmp"
  local _ext=$(get_ext ${_path_archive})

  mkdir -p "${_dir_out_tmp}"

  # 拡張子に合わせたコマンドで、作業ディレクトリに展開
  local _retcode=${EXITCODE_SUCCESS}
  cd "${_dir_out_tmp}" || return ${EXITCODE_ERROR}
  if [[ "${_ext}" == "zip" ]]; then
    unzip "${_path_archive}" >/dev/null
    _retcode=$?

  elif [[ "${_ext}" == "tar.gz" ]] || [[ "${_ext}" == "gz" ]]; then
    tar -xfz "${_path_archive}" >/dev/null
    _retcode=$?

  elif [[ "${_ext}" == "jar" ]] || [[ "${_ext}" == "war" ]] || [[ "${_ext}" == "ear" ]]; then
    jar xf "${_path_archive}" >/dev/null
    _retcode=$?

  fi
  cd - >/dev/null 2>&1 || return ${EXITCODE_ERROR}
  if [ ${_retcode} -ne ${EXITCODE_SUCCESS} ]; then
    return ${EXITCODE_ERROR}
  fi

  # 対応拡張子群をループ
  for _cur_allow_ext in ${ALLOW_EXTS[@]}; do
    # 現在の対応拡張子のファイルをループ
    for _cur_file_path in $(find "${_dir_out_tmp}" -type f -name "\\*.${_cur_allow_ext}" ); do
      # 再帰呼び出し
      if recursive_expand "${_cur_file_path}"; then return ${EXITCODE_ERROR}; fi
    done
  done

  if [[ "${_is_remove}" == "true" ]]; then rm -f "${_path_archive}"; fi
  rm -fr "${_dir_out}"
  mv "${_dir_out_tmp}" "${_dir_out}"

  return ${EXITCODE_SUCCESS}
}


#--------------------------------------------------------------------------------------------------
# 事前処理
#--------------------------------------------------------------------------------------------------
option=

# オプション解析
while :; do
  case $1 in
    -v)
      option="-v"
      shift
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "${USAGE}" >&2
      exit 1
      ;;
    *)  break
      ;;
  esac
done

# 引数チェック
if [[ $# -ne 2 ]]; then
  echo "${USAGE}" >&2
  exit ${EXITCODE_ERROR}
fi

# 旧アーカイブ
path_old="$1"
if [[ ! -f "${path_old}" ]]; then
  echo "${path_old} is NOT exist." >&2
  exit ${EXITCODE_ERROR}
fi

# 新アーカイブ
path_new="$2"
if [[ ! -f "${path_new}" ]]; then
  echo "${path_new} is NOT exist." >&2
  exit ${EXITCODE_ERROR}
fi

# 拡張子の一致チェック
ext_old=$(get_ext "${path_old}")
ext_new=$(get_ext "${path_new}")
if [[ "${ext_old}" != "${ext_new}" ]]; then
  echo "file extension is UNMATCHED. old:${ext_old} new:${ext_new}" >&2
  exit ${EXITCODE_ERROR}
fi

# 対応拡張子チェック
is_allow="false"
for _cur_allow_ext in ${ALLOW_EXTS[@]}; do
  if [[ "${ext_old}" = "${_cur_allow_ext}" ]]; then
    is_allow="true"
    break
  fi
done
if [[ "${is_allow}" == "false" ]]; then
  echo "file extension \"${ext_old}\" is NOT allowed. allows:${ALLOW_EXTS[*]}" >&2
  exit ${EXITCODE_ERROR}
fi

mkdir -p "${dir_tmp_root}"
trap "rm -fr ${dir_work}; exit ${EXITCODE_ERROR}" SIGHUP SIGINT SIGQUIT SIGTERM


#--------------------------------------------------------------------------------------------------
# 本処理
#--------------------------------------------------------------------------------------------------
# 旧アーカイブを再帰的に展開
echo "$(date '+%Y-%m-%d %T') recursive_expand \"${path_old}\" \"${dir_old}\"" >&2
if ! recursive_expand "${path_old}" "${dir_old}"; then
  exit ${EXITCODE_ERROR}
fi

# 新アーカイブを再帰的に展開
echo "$(date '+%Y-%m-%d %T') recursive_expand \"${path_new}\" \"${dir_new}\"" >&2
if ! recursive_expand "${path_new}" "${dir_new}"; then
  exit ${EXITCODE_ERROR}
fi

# ディレクトリ比較
dir_out_old="${dir_old}/$(basename ${path_old})"
dir_out_new="${dir_new}/$(basename ${path_new})"
echo "$(date '+%Y-%m-%d %T') ./dir_diff.sh \"${dir_out_old}\" \"${dir_out_new}\"" >&2
echo ""                                                                           >&2
"./dir_diff.sh" ${option} "${dir_out_old}" "${dir_out_new}"
retcode=$?


#--------------------------------------------------------------------------------------------------
# 事後処理
#--------------------------------------------------------------------------------------------------
rm -fr "${dir_work}"
exit ${retcode}
