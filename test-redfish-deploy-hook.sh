#!/usr/bin/env sh

# TODO: Eyal: Delete before opening pull request.

LOG_LEVEL_1=1
LOG_LEVEL_2=2
LOG_LEVEL_3=3
DEFAULT_LOG_LEVEL="$LOG_LEVEL_2"

DEBUG="2"
DEBUG_LEVEL_1=1
DEBUG_LEVEL_2=2
DEBUG_LEVEL_3=3
DEBUG_LEVEL_DEFAULT=$DEBUG_LEVEL_2
DEBUG_LEVEL_NONE=0

SYSLOG_ERROR="user.error"
SYSLOG_INFO="user.info"
SYSLOG_DEBUG="user.debug"

#error
SYSLOG_LEVEL_ERROR=3
#info
SYSLOG_LEVEL_INFO=6
#debug
SYSLOG_LEVEL_DEBUG=7
#debug2
SYSLOG_LEVEL_DEBUG_2=8
#debug3
SYSLOG_LEVEL_DEBUG_3=9

SYSLOG_LEVEL_DEFAULT=$SYSLOG_LEVEL_ERROR
#none
SYSLOG_LEVEL_NONE=0

__INTERACTIVE=""
if [ -t 1 ]; then
  __INTERACTIVE="1"
fi

__green() {
  if [ "${__INTERACTIVE}${ACME_NO_COLOR:-0}" = "10" -o "${ACME_FORCE_COLOR}" = "1" ]; then
    printf '\33[1;32m%b\33[0m' "$1"
    return
  fi
  printf -- "%b" "$1"
}

__red() {
  if [ "${__INTERACTIVE}${ACME_NO_COLOR:-0}" = "10" -o "${ACME_FORCE_COLOR}" = "1" ]; then
    printf '\33[1;31m%b\33[0m' "$1"
    return
  fi
  printf -- "%b" "$1"
}

_printargs() {
  _exitstatus="$?"
  if [ -z "$NO_TIMESTAMP" ] || [ "$NO_TIMESTAMP" = "0" ]; then
    printf -- "%s" "[$(date)] "
  fi
  if [ -z "$2" ]; then
    printf -- "%s" "$1"
  else
    printf -- "%s" "$1='$2'"
  fi
  printf "\n"
  # return the saved exit status
  return "$_exitstatus"
}

_dlg_versions() {
  echo "Diagnosis versions: "
  echo "openssl:$ACME_OPENSSL_BIN"
  if _exists "${ACME_OPENSSL_BIN:-openssl}"; then
    ${ACME_OPENSSL_BIN:-openssl} version 2>&1
  else
    echo "$ACME_OPENSSL_BIN doesn't exist."
  fi

  echo "Apache:"
  if [ "$_APACHECTL" ] && _exists "$_APACHECTL"; then
    $_APACHECTL -V 2>&1
  else
    echo "Apache doesn't exist."
  fi

  echo "nginx:"
  if _exists "nginx"; then
    nginx -V 2>&1
  else
    echo "nginx doesn't exist."
  fi

  echo "socat:"
  if _exists "socat"; then
    socat -V 2>&1
  else
    _debug "socat doesn't exist."
    if _exists "python3"; then
      python3 -V 2>&1
    elif _exists "python2"; then
      python2 -V 2>&1
    elif _exists "python"; then
      python -V 2>&1
    fi
  fi
}

#class
_syslog() {
  _exitstatus="$?"
  if [ "${SYS_LOG:-$SYSLOG_LEVEL_NONE}" = "$SYSLOG_LEVEL_NONE" ]; then
    return
  fi
  _logclass="$1"
  shift
  if [ -z "$__logger_i" ]; then
    if _contains "$(logger --help 2>&1)" "-i"; then
      __logger_i="logger -i"
    else
      __logger_i="logger"
    fi
  fi
  $__logger_i -t "$PROJECT_NAME" -p "$_logclass" "$(_printargs "$@")" >/dev/null 2>&1
  return "$_exitstatus"
}

_log() {
  [ -z "$LOG_FILE" ] && return
  _printargs "$@" >>"$LOG_FILE"
}

_info() {
  _log "$@"
  if [ "${SYS_LOG:-$SYSLOG_LEVEL_NONE}" -ge "$SYSLOG_LEVEL_INFO" ]; then
    _syslog "$SYSLOG_INFO" "$@"
  fi
  _printargs "$@"
}

_err() {
  _syslog "$SYSLOG_ERROR" "$@"
  _log "$@"
  if [ -z "$NO_TIMESTAMP" ] || [ "$NO_TIMESTAMP" = "0" ]; then
    printf -- "%s" "[$(date)] " >&2
  fi
  if [ -z "$2" ]; then
    __red "$1" >&2
  else
    __red "$1='$2'" >&2
  fi
  printf "\n" >&2
  return 1
}

_usage() {
  __red "$@" >&2
  printf "\n" >&2
}

__debug_bash_helper() {
  # At this point only do for --debug 3
  if [ "${DEBUG:-$DEBUG_LEVEL_NONE}" -lt "$DEBUG_LEVEL_3" ]; then
    return
  fi
  # Return extra debug info when running with bash, otherwise return empty
  # string.
  if [ -z "${BASH_VERSION}" ]; then
    return
  fi
  # We are a bash shell at this point, return the filename, function name, and
  # line number as a string
  _dbh_saveIFS=$IFS
  IFS=" "
  # Must use eval or syntax error happens under dash. The eval should use
  # single quotes as older versions of busybox had a bug with double quotes and
  # eval.
  # Use 'caller 1' as we want one level up the stack as we should be called
  # by one of the _debug* functions
  eval '_dbh_called=($(caller 1))'
  IFS=$_dbh_saveIFS
  eval '_dbh_file=${_dbh_called[2]}'
  if [ -n "${_script_home}" ]; then
    # Trim off the _script_home directory name
    eval '_dbh_file=${_dbh_file#$_script_home/}'
  fi
  eval '_dbh_function=${_dbh_called[1]}'
  eval '_dbh_lineno=${_dbh_called[0]}'
  printf "%-40s " "$_dbh_file:${_dbh_function}:${_dbh_lineno}"
}

_debug() {
  if [ "${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}" -ge "$LOG_LEVEL_1" ]; then
    _log "$@"
  fi
  if [ "${SYS_LOG:-$SYSLOG_LEVEL_NONE}" -ge "$SYSLOG_LEVEL_DEBUG" ]; then
    _syslog "$SYSLOG_DEBUG" "$@"
  fi
  if [ "${DEBUG:-$DEBUG_LEVEL_NONE}" -ge "$DEBUG_LEVEL_1" ]; then
    _bash_debug=$(__debug_bash_helper)
    _printargs "${_bash_debug}$@" >&2
  fi
}

#output the sensitive messages
_secure_debug() {
  if [ "${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}" -ge "$LOG_LEVEL_1" ]; then
    if [ "$OUTPUT_INSECURE" = "1" ]; then
      _log "$@"
    else
      _log "$1" "$HIDDEN_VALUE"
    fi
  fi
  if [ "${SYS_LOG:-$SYSLOG_LEVEL_NONE}" -ge "$SYSLOG_LEVEL_DEBUG" ]; then
    _syslog "$SYSLOG_DEBUG" "$1" "$HIDDEN_VALUE"
  fi
  if [ "${DEBUG:-$DEBUG_LEVEL_NONE}" -ge "$DEBUG_LEVEL_1" ]; then
    if [ "$OUTPUT_INSECURE" = "1" ]; then
      _printargs "$@" >&2
    else
      _printargs "$1" "$HIDDEN_VALUE" >&2
    fi
  fi
}

_debug2() {
  if [ "${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}" -ge "$LOG_LEVEL_2" ]; then
    _log "$@"
  fi
  if [ "${SYS_LOG:-$SYSLOG_LEVEL_NONE}" -ge "$SYSLOG_LEVEL_DEBUG_2" ]; then
    _syslog "$SYSLOG_DEBUG" "$@"
  fi
  if [ "${DEBUG:-$DEBUG_LEVEL_NONE}" -ge "$DEBUG_LEVEL_2" ]; then
    _bash_debug=$(__debug_bash_helper)
    _printargs "${_bash_debug}$@" >&2
  fi
}

_secure_debug2() {
  if [ "${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}" -ge "$LOG_LEVEL_2" ]; then
    if [ "$OUTPUT_INSECURE" = "1" ]; then
      _log "$@"
    else
      _log "$1" "$HIDDEN_VALUE"
    fi
  fi
  if [ "${SYS_LOG:-$SYSLOG_LEVEL_NONE}" -ge "$SYSLOG_LEVEL_DEBUG_2" ]; then
    _syslog "$SYSLOG_DEBUG" "$1" "$HIDDEN_VALUE"
  fi
  if [ "${DEBUG:-$DEBUG_LEVEL_NONE}" -ge "$DEBUG_LEVEL_2" ]; then
    if [ "$OUTPUT_INSECURE" = "1" ]; then
      _printargs "$@" >&2
    else
      _printargs "$1" "$HIDDEN_VALUE" >&2
    fi
  fi
}

_debug3() {
  if [ "${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}" -ge "$LOG_LEVEL_3" ]; then
    _log "$@"
  fi
  if [ "${SYS_LOG:-$SYSLOG_LEVEL_NONE}" -ge "$SYSLOG_LEVEL_DEBUG_3" ]; then
    _syslog "$SYSLOG_DEBUG" "$@"
  fi
  if [ "${DEBUG:-$DEBUG_LEVEL_NONE}" -ge "$DEBUG_LEVEL_3" ]; then
    _bash_debug=$(__debug_bash_helper)
    _printargs "${_bash_debug}$@" >&2
  fi
}

_secure_debug3() {
  if [ "${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}" -ge "$LOG_LEVEL_3" ]; then
    if [ "$OUTPUT_INSECURE" = "1" ]; then
      _log "$@"
    else
      _log "$1" "$HIDDEN_VALUE"
    fi
  fi
  if [ "${SYS_LOG:-$SYSLOG_LEVEL_NONE}" -ge "$SYSLOG_LEVEL_DEBUG_3" ]; then
    _syslog "$SYSLOG_DEBUG" "$1" "$HIDDEN_VALUE"
  fi
  if [ "${DEBUG:-$DEBUG_LEVEL_NONE}" -ge "$DEBUG_LEVEL_3" ]; then
    if [ "$OUTPUT_INSECURE" = "1" ]; then
      _printargs "$@" >&2
    else
      _printargs "$1" "$HIDDEN_VALUE" >&2
    fi
  fi
}

__USE_TR_TAG=""
if [ "$(echo "abc" | LANG=C tr a-z A-Z 2>/dev/null)" != "ABC" ]; then
  __USE_TR_TAG="1"
fi
export __USE_TR_TAG

_upper_case() {
  if [ "$__USE_TR_TAG" ]; then
    LANG=C tr '[:lower:]' '[:upper:]'
  else
    # shellcheck disable=SC2018,SC2019
    LANG=C tr '[a-z]' '[A-Z]'
  fi
}

_lower_case() {
  if [ "$__USE_TR_TAG" ]; then
    LANG=C tr '[:upper:]' '[:lower:]'
  else
    # shellcheck disable=SC2018,SC2019
    LANG=C tr '[A-Z]' '[a-z]'
  fi
}

_startswith() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep -- "^$_sub" >/dev/null 2>&1
}

_endswith() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep -- "$_sub\$" >/dev/null 2>&1
}

_contains() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep -- "$_sub" >/dev/null 2>&1
}

_hasfield() {
  _str="$1"
  _field="$2"
  _sep="$3"
  if [ -z "$_field" ]; then
    _usage "Usage: str field  [sep]"
    return 1
  fi

  if [ -z "$_sep" ]; then
    _sep=","
  fi

  for f in $(echo "$_str" | tr "$_sep" ' '); do
    if [ "$f" = "$_field" ]; then
      _debug2 "'$_str' contains '$_field'"
      return 0 #contains ok
    fi
  done
  _debug2 "'$_str' does not contain '$_field'"
  return 1 #not contains
}

# str index [sep]
_getfield() {
  _str="$1"
  _findex="$2"
  _sep="$3"

  if [ -z "$_findex" ]; then
    _usage "Usage: str field  [sep]"
    return 1
  fi

  if [ -z "$_sep" ]; then
    _sep=","
  fi

  _ffi="$_findex"
  while [ "$_ffi" -gt "0" ]; do
    _fv="$(echo "$_str" | cut -d "$_sep" -f "$_ffi")"
    if [ "$_fv" ]; then
      printf -- "%s" "$_fv"
      return 0
    fi
    _ffi="$(_math "$_ffi" - 1)"
  done

  printf -- "%s" "$_str"

}

_exists() {
  cmd="$1"
  if [ -z "$cmd" ]; then
    _usage "Usage: _exists cmd"
    return 1
  fi

  if eval type type >/dev/null 2>&1; then
    eval type "$cmd" >/dev/null 2>&1
  elif command >/dev/null 2>&1; then
    command -v "$cmd" >/dev/null 2>&1
  else
    which "$cmd" >/dev/null 2>&1
  fi
  ret="$?"
  _debug3 "$cmd exists=$ret"
  return $ret
}

#a + b
_math() {
  _m_opts="$@"
  printf "%s" "$(($_m_opts))"
}

_h_char_2_dec() {
  _ch=$1
  case "${_ch}" in
  a | A)
    printf "10"
    ;;
  b | B)
    printf "11"
    ;;
  c | C)
    printf "12"
    ;;
  d | D)
    printf "13"
    ;;
  e | E)
    printf "14"
    ;;
  f | F)
    printf "15"
    ;;
  *)
    printf "%s" "$_ch"
    ;;
  esac

}

_URGLY_PRINTF=""
if [ "$(printf '\x41')" != 'A' ]; then
  _URGLY_PRINTF=1
fi

_h2b() {
  if _exists xxd; then
    if _contains "$(xxd --help 2>&1)" "assumes -c30"; then
      if xxd -r -p -c 9999 2>/dev/null; then
        return
      fi
    else
      if xxd -r -p 2>/dev/null; then
        return
      fi
    fi
  fi

  hex=$(cat)
  ic=""
  jc=""
  _debug2 _URGLY_PRINTF "$_URGLY_PRINTF"
  if [ -z "$_URGLY_PRINTF" ]; then
    # shellcheck disable=SC2059
    printf "$(echo "$hex" | _upper_case | sed 's/\([0-9A-F]\{2\}\)/\\x\1/g')"
  else
    for c in $(echo "$hex" | _upper_case | sed 's/\([0-9A-F]\)/ \1/g'); do
      if [ -z "$ic" ]; then
        ic=$c
        continue
      fi
      jc=$c
      ic="$(_h_char_2_dec "$ic")"
      jc="$(_h_char_2_dec "$jc")"
      printf '\'"$(printf "%o" "$(_math "$ic" \* 16 + $jc)")""%s"
      ic=""
      jc=""
    done
  fi

}

_is_solaris() {
  _contains "${__OS__:=$(uname -a)}" "solaris" || _contains "${__OS__:=$(uname -a)}" "SunOS"
}

#_ascii_hex str
#this can only process ascii chars, should only be used when od command is missing as a backup way.
_ascii_hex() {
  _debug2 "Using _ascii_hex"
  _str="$1"
  _str_len=${#_str}
  _h_i=1
  while [ "$_h_i" -le "$_str_len" ]; do
    _str_c="$(printf "%s" "$_str" | cut -c "$_h_i")"
    printf " %02x" "'$_str_c"
    _h_i="$(_math "$_h_i" + 1)"
  done
}

#stdin  output hexstr splited by one space
#input:"abc"
#output: " 61 62 63"
_hex_dump() {
  if _exists od; then
    od -A n -v -t x1 | tr -s " " | sed 's/ $//' | tr -d "\r\t\n"
  elif _exists hexdump; then
    _debug3 "using hexdump"
    hexdump -v -e '/1 ""' -e '/1 " %02x" ""'
  elif _exists xxd; then
    _debug3 "using xxd"
    xxd -ps -c 20 -i | sed "s/ 0x/ /g" | tr -d ",\n" | tr -s " "
  else
    _debug3 "using _ascii_hex"
    str=$(cat)
    _ascii_hex "$str"
  fi
}

#url encode, no-preserved chars
#A  B  C  D  E  F  G  H  I  J  K  L  M  N  O  P  Q  R  S  T  U  V  W  X  Y  Z
#41 42 43 44 45 46 47 48 49 4a 4b 4c 4d 4e 4f 50 51 52 53 54 55 56 57 58 59 5a

#a  b  c  d  e  f  g  h  i  j  k  l  m  n  o  p  q  r  s  t  u  v  w  x  y  z
#61 62 63 64 65 66 67 68 69 6a 6b 6c 6d 6e 6f 70 71 72 73 74 75 76 77 78 79 7a

#0  1  2  3  4  5  6  7  8  9  -  _  .  ~
#30 31 32 33 34 35 36 37 38 39 2d 5f 2e 7e

#_url_encode [upper-hex]  the encoded hex will be upper-case if the argument upper-hex is followed
#stdin stdout
_url_encode() {
  _upper_hex=$1
  _hex_str=$(_hex_dump)
  _debug3 "_url_encode"
  _debug3 "_hex_str" "$_hex_str"
  for _hex_code in $_hex_str; do
    #upper case
    case "${_hex_code}" in
    "41")
      printf "%s" "A"
      ;;
    "42")
      printf "%s" "B"
      ;;
    "43")
      printf "%s" "C"
      ;;
    "44")
      printf "%s" "D"
      ;;
    "45")
      printf "%s" "E"
      ;;
    "46")
      printf "%s" "F"
      ;;
    "47")
      printf "%s" "G"
      ;;
    "48")
      printf "%s" "H"
      ;;
    "49")
      printf "%s" "I"
      ;;
    "4a")
      printf "%s" "J"
      ;;
    "4b")
      printf "%s" "K"
      ;;
    "4c")
      printf "%s" "L"
      ;;
    "4d")
      printf "%s" "M"
      ;;
    "4e")
      printf "%s" "N"
      ;;
    "4f")
      printf "%s" "O"
      ;;
    "50")
      printf "%s" "P"
      ;;
    "51")
      printf "%s" "Q"
      ;;
    "52")
      printf "%s" "R"
      ;;
    "53")
      printf "%s" "S"
      ;;
    "54")
      printf "%s" "T"
      ;;
    "55")
      printf "%s" "U"
      ;;
    "56")
      printf "%s" "V"
      ;;
    "57")
      printf "%s" "W"
      ;;
    "58")
      printf "%s" "X"
      ;;
    "59")
      printf "%s" "Y"
      ;;
    "5a")
      printf "%s" "Z"
      ;;

      #lower case
    "61")
      printf "%s" "a"
      ;;
    "62")
      printf "%s" "b"
      ;;
    "63")
      printf "%s" "c"
      ;;
    "64")
      printf "%s" "d"
      ;;
    "65")
      printf "%s" "e"
      ;;
    "66")
      printf "%s" "f"
      ;;
    "67")
      printf "%s" "g"
      ;;
    "68")
      printf "%s" "h"
      ;;
    "69")
      printf "%s" "i"
      ;;
    "6a")
      printf "%s" "j"
      ;;
    "6b")
      printf "%s" "k"
      ;;
    "6c")
      printf "%s" "l"
      ;;
    "6d")
      printf "%s" "m"
      ;;
    "6e")
      printf "%s" "n"
      ;;
    "6f")
      printf "%s" "o"
      ;;
    "70")
      printf "%s" "p"
      ;;
    "71")
      printf "%s" "q"
      ;;
    "72")
      printf "%s" "r"
      ;;
    "73")
      printf "%s" "s"
      ;;
    "74")
      printf "%s" "t"
      ;;
    "75")
      printf "%s" "u"
      ;;
    "76")
      printf "%s" "v"
      ;;
    "77")
      printf "%s" "w"
      ;;
    "78")
      printf "%s" "x"
      ;;
    "79")
      printf "%s" "y"
      ;;
    "7a")
      printf "%s" "z"
      ;;
      #numbers
    "30")
      printf "%s" "0"
      ;;
    "31")
      printf "%s" "1"
      ;;
    "32")
      printf "%s" "2"
      ;;
    "33")
      printf "%s" "3"
      ;;
    "34")
      printf "%s" "4"
      ;;
    "35")
      printf "%s" "5"
      ;;
    "36")
      printf "%s" "6"
      ;;
    "37")
      printf "%s" "7"
      ;;
    "38")
      printf "%s" "8"
      ;;
    "39")
      printf "%s" "9"
      ;;
    "2d")
      printf "%s" "-"
      ;;
    "5f")
      printf "%s" "_"
      ;;
    "2e")
      printf "%s" "."
      ;;
    "7e")
      printf "%s" "~"
      ;;
    #other hex
    *)
      if [ "$_upper_hex" = "upper-hex" ]; then
        _hex_code=$(printf "%s" "$_hex_code" | _upper_case)
      fi
      printf '%%%s' "$_hex_code"
      ;;
    esac
  done
}

_json_encode() {
  _j_str="$(sed 's/"/\\"/g' | sed "s/\r/\\r/g")"
  _debug3 "_json_encode"
  _debug3 "_j_str" "$_j_str"
  echo "$_j_str" | _hex_dump | _lower_case | sed 's/0a/5c 6e/g' | tr -d ' ' | _h2b | tr -d "\r\n"
}

#from: http:\/\/  to http://
_json_decode() {
  _j_str="$(sed 's#\\/#/#g')"
  _debug3 "_json_decode"
  _debug3 "_j_str" "$_j_str"
  echo "$_j_str"
}

#extract the authorization URLs from an order response on stdin, as a
#comma-separated list. The entries are quoted URL strings and a quote cannot
#occur inside a URL, so the first '"]' is always the end of the array. A
#char-class scan would stop early on the brackets of an IPv6 host
#(https://[2001:db8::1]/...). Outputs nothing if the field is missing.
_authorizations_from_order() {
  sed -n 's/.*"authorizations" *: *\[//p' | sed 's/" *\].*//' | tr -d '" '
}

#options file
_sed_i() {
  options="$1"
  filename="$2"
  if [ -z "$filename" ]; then
    _usage "Usage:_sed_i options filename"
    return 1
  fi
  _debug2 options "$options"
  if sed -h 2>&1 | grep "\-i\[SUFFIX]" >/dev/null 2>&1; then
    _debug "Using sed  -i"
    sed -i "$options" "$filename"
  elif sed -h 2>&1 | grep "\-i extension" >/dev/null 2>&1; then
    _debug "Using FreeBSD sed -i"
    sed -i "" "$options" "$filename"
  else
    _debug "No -i support in sed"
    text="$(cat "$filename")"
    echo "$text" | sed "$options" >"$filename"
  fi
}

if [ "$(echo abc | egrep -o b 2>/dev/null)" = "b" ]; then
  __USE_EGREP=1
else
  __USE_EGREP=""
fi

_egrep_o() {
  if [ "$__USE_EGREP" ]; then
    egrep -o -- "$1" 2>/dev/null
  else
    sed -n 's/.*\('"$1"'\).*/\1/p'
  fi
}

#Usage: file startline endline
_getfile() {
  filename="$1"
  startline="$2"
  endline="$3"
  if [ -z "$endline" ]; then
    _usage "Usage: file startline endline"
    return 1
  fi

  i="$(grep -n -- "$startline" "$filename" | cut -d : -f 1)"
  if [ -z "$i" ]; then
    _err "Cannot find start line: $startline"
    return 1
  fi
  i="$(_math "$i" + 1)"
  _debug i "$i"

  j="$(grep -n -- "$endline" "$filename" | cut -d : -f 1)"
  if [ -z "$j" ]; then
    _err "Cannot find end line: $endline"
    return 1
  fi
  j="$(_math "$j" - 1)"
  _debug j "$j"

  sed -n "$i,${j}p" "$filename"

}

#Usage: multiline
_base64() {
  [ "" ] #urgly
  if [ "$1" ]; then
    _debug3 "base64 multiline:'$1'"
    ${ACME_OPENSSL_BIN:-openssl} base64 -e
  else
    _debug3 "base64 single line."
    ${ACME_OPENSSL_BIN:-openssl} base64 -e | tr -d '\r\n'
  fi
}

#Usage: multiline
_dbase64() {
  if [ "$1" ]; then
    ${ACME_OPENSSL_BIN:-openssl} base64 -d
  else
    ${ACME_OPENSSL_BIN:-openssl} base64 -d -A
  fi
}

#file
_checkcert() {
  _cf="$1"
  if [ "$DEBUG" ]; then
    ${ACME_OPENSSL_BIN:-openssl} x509 -noout -text -in "$_cf"
  else
    ${ACME_OPENSSL_BIN:-openssl} x509 -noout -text -in "$_cf" >/dev/null 2>&1
  fi
}

#file
_enddate() {
  _cf="$1"
  _res="$(${ACME_OPENSSL_BIN:-openssl} x509 -noout -enddate -in "$_cf")"
  if [ "$?" != "0" ] || [ -z "$_res" ]; then
    return 1
  fi

  case "$_res" in
  notAfter=*)
    echo "${_res#notAfter=}"
    ;;
  *)
    return 1
    ;;
  esac
}

#Usage: hashalg  [outputhex]
#Output Base64-encoded digest
_digest() {
  alg="$1"
  if [ -z "$alg" ]; then
    _usage "Usage: _digest hashalg"
    return 1
  fi

  outputhex="$2"

  if [ "$alg" = "sha3-256" ] || [ "$alg" = "sha256" ] || [ "$alg" = "sha1" ] || [ "$alg" = "md5" ]; then
    if [ "$outputhex" ]; then
      ${ACME_OPENSSL_BIN:-openssl} dgst -"$alg" -hex | cut -d = -f 2 | tr -d ' '
    else
      ${ACME_OPENSSL_BIN:-openssl} dgst -"$alg" -binary | _base64
    fi
  else
    _err "$alg is not supported yet"
    return 1
  fi

}

_mktemp() {
  if _exists mktemp; then
    if mktemp 2>/dev/null; then
      return 0
    elif _contains "$(mktemp 2>&1)" "-t prefix" && mktemp -t "$PROJECT_NAME" 2>/dev/null; then
      #for Mac osx
      return 0
    fi
  fi
  if [ -d "/tmp" ]; then
    echo "/tmp/${PROJECT_NAME}wefADf24sf.$(_time).tmp"
    return 0
  elif [ "$LE_TEMP_DIR" ] && mkdir -p "$LE_TEMP_DIR"; then
    echo "/$LE_TEMP_DIR/wefADf24sf.$(_time).tmp"
    return 0
  fi
  _err "Cannot create temp file."
}

#clear all the https envs to cause _inithttp() to run next time.
_resethttp() {
  __HTTP_INITIALIZED=""
  _ACME_CURL=""
  _ACME_WGET=""
  ACME_HTTP_NO_REDIRECTS=""
}

_inithttp() {

  if [ -z "$HTTP_HEADER" ] || ! touch "$HTTP_HEADER"; then
    HTTP_HEADER="$(_mktemp)"
    _debug2 HTTP_HEADER "$HTTP_HEADER"
  fi

  if [ "$__HTTP_INITIALIZED" ]; then
    if [ "$_ACME_CURL$_ACME_WGET" ]; then
      _debug2 "Http already initialized."
      return 0
    fi
  fi

  if [ -z "$_ACME_CURL" ] && _exists "curl"; then
    _ACME_CURL="curl --silent --dump-header $HTTP_HEADER "
    if [ "$ACME_USE_IPV6_REQUESTS" ]; then
      _ACME_CURL="$_ACME_CURL --ipv6 "
    elif [ "$ACME_USE_IPV4_REQUESTS" ]; then
      _ACME_CURL="$_ACME_CURL --ipv4 "
    fi
    if [ -z "$ACME_HTTP_NO_REDIRECTS" ]; then
      _ACME_CURL="$_ACME_CURL -L "
    fi
    if [ "$DEBUG" ] && [ "$DEBUG" -ge 2 ]; then
      _CURL_DUMP="$(_mktemp)"
      _ACME_CURL="$_ACME_CURL --trace-ascii $_CURL_DUMP "
    fi

    if [ "$CA_PATH" ]; then
      _ACME_CURL="$_ACME_CURL --capath $CA_PATH "
    elif [ "$CA_BUNDLE" ]; then
      _ACME_CURL="$_ACME_CURL --cacert $CA_BUNDLE "
    fi

    if _contains "$(curl --help 2>&1)" "--globoff" || _contains "$(curl --help curl 2>&1)" "--globoff"; then
      _ACME_CURL="$_ACME_CURL -g "
    fi

    #don't use --fail-with-body
    ##from curl 7.76: return fail on HTTP errors but keep the body
    #if _contains "$(curl --help http 2>&1)" "--fail-with-body"; then
    #  _ACME_CURL="$_ACME_CURL --fail-with-body "
    #fi
  fi

  if [ -z "$_ACME_WGET" ] && _exists "wget"; then
    _ACME_WGET="wget -q"
    if [ "$ACME_USE_IPV6_REQUESTS" ]; then
      _ACME_WGET="$_ACME_WGET --inet6-only "
    elif [ "$ACME_USE_IPV4_REQUESTS" ]; then
      _ACME_WGET="$_ACME_WGET --inet4-only "
    fi
    if [ "$ACME_HTTP_NO_REDIRECTS" ]; then
      _ACME_WGET="$_ACME_WGET --max-redirect 0 "
    fi
    if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ]; then
      if [ "$_ACME_WGET" ] && _contains "$($_ACME_WGET --help 2>&1)" "--debug"; then
        _ACME_WGET="$_ACME_WGET -d "
      fi
    fi
    if [ "$CA_PATH" ]; then
      _ACME_WGET="$_ACME_WGET --ca-directory=$CA_PATH "
    elif [ "$CA_BUNDLE" ]; then
      _ACME_WGET="$_ACME_WGET --ca-certificate=$CA_BUNDLE "
    fi

    #from wget 1.14: do not skip body on 404 error
    if _contains "$(wget --help 2>&1)" "--content-on-error"; then
      _ACME_WGET="$_ACME_WGET --content-on-error "
    fi
  fi

  __HTTP_INITIALIZED=1

}

# body  url [needbase64] [POST|PUT|DELETE] [ContentType]
_post() {
  body="$1"
  _post_url="$2"
  needbase64="$3"
  httpmethod="$4"
  _postContentType="$5"

  if [ -z "$httpmethod" ]; then
    httpmethod="POST"
  fi
  _debug $httpmethod
  _debug "_post_url" "$_post_url"
  _debug2 "body" "$body"
  _debug2 "_postContentType" "$_postContentType"

  _inithttp

  if [ "$_ACME_CURL" ] && [ "${ACME_USE_WGET:-0}" = "0" ]; then
    _CURL="$_ACME_CURL"
    if [ "$HTTPS_INSECURE" ]; then
      _CURL="$_CURL --insecure  "
    fi
    if [ "$httpmethod" = "HEAD" ]; then
      _CURL="$_CURL -I  "
    fi
    _debug "_CURL" "$_CURL"
    if [ "$needbase64" ]; then
      if [ "$body" ]; then
        if [ "$_postContentType" ]; then
          response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "Content-Type: $_postContentType" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" --data "$body" "$_post_url" | _base64)"
        else
          response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" --data "$body" "$_post_url" | _base64)"
        fi
      else
        if [ "$_postContentType" ]; then
          response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "Content-Type: $_postContentType" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" "$_post_url" | _base64)"
        else
          response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" "$_post_url" | _base64)"
        fi
      fi
    else
      if [ "$body" ]; then
        if [ "$_postContentType" ]; then
          response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "Content-Type: $_postContentType" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" --data "$body" "$_post_url")"
        else
          response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" --data "$body" "$_post_url")"
        fi
      else
        if [ "$_postContentType" ]; then
          response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "Content-Type: $_postContentType" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" "$_post_url")"
        else
          response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" "$_post_url")"
        fi
      fi
    fi
    _ret="$?"
    if [ "$_ret" != "0" ]; then
      _err "Please refer to https://curl.haxx.se/libcurl/c/libcurl-errors.html for error code: $_ret"
      if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ]; then
        _err "Here is the curl dump log:"
        _err "$(cat "$_CURL_DUMP")"
      fi
    fi
  elif [ "$_ACME_WGET" ]; then
    _WGET="$_ACME_WGET"
    if [ "$HTTPS_INSECURE" ]; then
      _WGET="$_WGET --no-check-certificate "
    fi
    if [ "$httpmethod" = "HEAD" ]; then
      _WGET="$_WGET --read-timeout=3.0  --tries=2  "
    fi
    _debug "_WGET" "$_WGET"
    if [ "$needbase64" ]; then
      if [ "$httpmethod" = "POST" ]; then
        if [ "$_postContentType" ]; then
          response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --header "Content-Type: $_postContentType" --post-data="$body" "$_post_url" 2>"$HTTP_HEADER" | _base64)"
        else
          response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --post-data="$body" "$_post_url" 2>"$HTTP_HEADER" | _base64)"
        fi
      else
        if [ "$_postContentType" ]; then
          response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --header "Content-Type: $_postContentType" --method $httpmethod --body-data="$body" "$_post_url" 2>"$HTTP_HEADER" | _base64)"
        else
          response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --method $httpmethod --body-data="$body" "$_post_url" 2>"$HTTP_HEADER" | _base64)"
        fi
      fi
    else
      if [ "$httpmethod" = "POST" ]; then
        if [ "$_postContentType" ]; then
          response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --header "Content-Type: $_postContentType" --post-data="$body" "$_post_url" 2>"$HTTP_HEADER")"
        else
          response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --post-data="$body" "$_post_url" 2>"$HTTP_HEADER")"
        fi
      elif [ "$httpmethod" = "HEAD" ]; then
        if [ "$_postContentType" ]; then
          response="$($_WGET --spider -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --header "Content-Type: $_postContentType" --post-data="$body" "$_post_url" 2>"$HTTP_HEADER")"
        else
          response="$($_WGET --spider -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --post-data="$body" "$_post_url" 2>"$HTTP_HEADER")"
        fi
      else
        if [ "$_postContentType" ]; then
          response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --header "Content-Type: $_postContentType" --method $httpmethod --body-data="$body" "$_post_url" 2>"$HTTP_HEADER")"
        else
          response="$($_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --method $httpmethod --body-data="$body" "$_post_url" 2>"$HTTP_HEADER")"
        fi
      fi
    fi
    _ret="$?"
    if [ "$_ret" = "8" ]; then
      _ret=0
      _debug "wget returned 8 as the server returned a 'Bad Request' response. Let's process the response later."
    fi
    if [ "$_ret" != "0" ]; then
      _err "Please refer to https://www.gnu.org/software/wget/manual/html_node/Exit-Status.html for error code: $_ret"
    fi
    if _contains "$_WGET" " -d "; then
      # Demultiplex wget debug output
      cat "$HTTP_HEADER" >&2
      _sed_i '/^[^ ][^ ]/d; /^ *$/d' "$HTTP_HEADER"
    fi
    # remove leading whitespaces from header to match curl format
    _sed_i 's/^  //g' "$HTTP_HEADER"
  else
    _ret="$?"
    _err "Neither curl nor wget have been found, cannot make $httpmethod request."
  fi
  _debug "_ret" "$_ret"
  printf "%s" "$response"
  return $_ret
}

# url getheader timeout
_get() {
  _debug GET
  url="$1"
  onlyheader="$2"
  t="$3"
  _debug url "$url"
  _debug "timeout=$t"

  _inithttp

  if [ "$_ACME_CURL" ] && [ "${ACME_USE_WGET:-0}" = "0" ]; then
    _CURL="$_ACME_CURL"
    if [ "$HTTPS_INSECURE" ]; then
      _CURL="$_CURL --insecure  "
    fi
    if [ "$t" ]; then
      _CURL="$_CURL --connect-timeout $t"
    fi
    _debug "_CURL" "$_CURL"
    if [ "$onlyheader" ]; then
      $_CURL -I --user-agent "$USER_AGENT" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" "$url"
    else
      $_CURL --user-agent "$USER_AGENT" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" "$url"
    fi
    ret=$?
    if [ "$ret" != "0" ]; then
      _err "Please refer to https://curl.haxx.se/libcurl/c/libcurl-errors.html for error code: $ret"
      if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ]; then
        _err "Here is the curl dump log:"
        _err "$(cat "$_CURL_DUMP")"
      fi
    fi
  elif [ "$_ACME_WGET" ]; then
    _WGET="$_ACME_WGET"
    if [ "$HTTPS_INSECURE" ]; then
      _WGET="$_WGET --no-check-certificate "
    fi
    if [ "$t" ]; then
      _WGET="$_WGET --timeout=$t"
    fi
    _debug "_WGET" "$_WGET"
    if [ "$onlyheader" ]; then
      _wget_out="$($_WGET --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" -S -O /dev/null "$url" 2>&1)"
      if _contains "$_WGET" " -d "; then
        # Demultiplex wget debug output
        echo "$_wget_out" >&2
        echo "$_wget_out" | sed '/^[^ ][^ ]/d; /^ *$/d; s/^  //g' -
      fi
    else
      $_WGET --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" -S -O - "$url" 2>"$HTTP_HEADER"
      if _contains "$_WGET" " -d "; then
        # Demultiplex wget debug output
        cat "$HTTP_HEADER" >&2
        _sed_i '/^[^ ][^ ]/d; /^ *$/d' "$HTTP_HEADER"
      fi
      # remove leading whitespaces from header to match curl format
      _sed_i 's/^  //g' "$HTTP_HEADER"
    fi
    ret=$?
    if [ "$ret" = "8" ]; then
      ret=0
      _debug "wget returned 8 as the server returned a 'Bad Request' response. Let's process the response later."
    fi
    if [ "$ret" != "0" ]; then
      _err "Please refer to https://www.gnu.org/software/wget/manual/html_node/Exit-Status.html for error code: $ret"
    fi
  else
    ret=$?
    _err "Neither curl nor wget have been found, cannot make GET request."
  fi
  _debug "ret" "$ret"
  return $ret
}

_head_n() {
  head -n "$1"
}

_tail_n() {
  if _is_solaris; then
    #fix for solaris
    tail -"$1"
  else
    tail -n "$1"
  fi
}

_normalizeJson() {
  sed "s/\" *: *\([\"{\[]\)/\":\1/g" | sed "s/^ *\([^ ]\)/\1/" | tr -d "\r\n"
}

HTTP_HEADER="$(_mktemp)"

. deploy/redfish.sh

DEPLOY_REDFISH_HOST='redfish-host'
DEPLOY_REDFISH_USERNAME='username'
DEPLOY_REDFISH_PASSWORD='password'
redfish_deploy 'domain' 'fake-key-file' 'fake-cert' 'fake-ca-cert' 'fake-fullchain'
