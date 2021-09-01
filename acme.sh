#!/usr/bin/env sh

VER=3.0.1

PROJECT_NAME="acme.sh"

PROJECT_ENTRY="acme.sh"

PROJECT="https://github.com/acmesh-official/$PROJECT_NAME"

DEFAULT_INSTALL_HOME="$HOME/.$PROJECT_NAME"

_WINDOWS_SCHEDULER_NAME="$PROJECT_NAME.cron"

_SCRIPT_="$0"

_SUB_FOLDER_NOTIFY="notify"
_SUB_FOLDER_DNSAPI="dnsapi"
_SUB_FOLDER_DEPLOY="deploy"

_SUB_FOLDERS="$_SUB_FOLDER_DNSAPI $_SUB_FOLDER_DEPLOY $_SUB_FOLDER_NOTIFY"

CA_LETSENCRYPT_V1="https://acme-v01.api.letsencrypt.org/directory"

CA_LETSENCRYPT_V2="https://acme-v02.api.letsencrypt.org/directory"
CA_LETSENCRYPT_V2_TEST="https://acme-staging-v02.api.letsencrypt.org/directory"

CA_BUYPASS="https://api.buypass.com/acme/directory"
CA_BUYPASS_TEST="https://api.test4.buypass.no/acme/directory"

CA_ZEROSSL="https://acme.zerossl.com/v2/DV90"
_ZERO_EAB_ENDPOINT="http://api.zerossl.com/acme/eab-credentials-email"

CA_SSLCOM_RSA="https://acme.ssl.com/sslcom-dv-rsa"
CA_SSLCOM_ECC="https://acme.ssl.com/sslcom-dv-ecc"

DEFAULT_CA=$CA_LETSENCRYPT_V2
DEFAULT_STAGING_CA=$CA_LETSENCRYPT_V2_TEST

CA_NAMES="
ZeroSSL.com,zerossl
LetsEncrypt.org,letsencrypt
LetsEncrypt.org_test,letsencrypt_test,letsencrypttest
BuyPass.com,buypass
BuyPass.com_test,buypass_test,buypasstest
SSL.com,sslcom
"

CA_SERVERS="$CA_ZEROSSL,$CA_LETSENCRYPT_V2,$CA_LETSENCRYPT_V2_TEST,$CA_BUYPASS,$CA_BUYPASS_TEST,$CA_SSLCOM_RSA"

DEFAULT_USER_AGENT="$PROJECT_NAME/$VER ($PROJECT)"

DEFAULT_ACCOUNT_KEY_LENGTH=2048
DEFAULT_DOMAIN_KEY_LENGTH=2048

DEFAULT_OPENSSL_BIN="openssl"

VTYPE_HTTP="http-01"
VTYPE_DNS="dns-01"
VTYPE_ALPN="tls-alpn-01"

LOCAL_ANY_ADDRESS="0.0.0.0"

DEFAULT_RENEW=60

NO_VALUE="no"

W_DNS="dns"
W_ALPN="alpn"
DNS_ALIAS_PREFIX="="

MODE_STATELESS="stateless"

STATE_VERIFIED="verified_ok"

NGINX="nginx:"
NGINX_START="#ACME_NGINX_START"
NGINX_END="#ACME_NGINX_END"

BEGIN_CSR="-----BEGIN CERTIFICATE REQUEST-----"
END_CSR="-----END CERTIFICATE REQUEST-----"

BEGIN_CERT="-----BEGIN CERTIFICATE-----"
END_CERT="-----END CERTIFICATE-----"

CONTENT_TYPE_JSON="application/jose+json"
RENEW_SKIP=2

B64CONF_START="__ACME_BASE64__START_"
B64CONF_END="__ACME_BASE64__END_"

ECC_SEP="_"
ECC_SUFFIX="${ECC_SEP}ecc"

LOG_LEVEL_1=1
LOG_LEVEL_2=2
LOG_LEVEL_3=3
DEFAULT_LOG_LEVEL="$LOG_LEVEL_1"

DEBUG_LEVEL_1=1
DEBUG_LEVEL_2=2
DEBUG_LEVEL_3=3
DEBUG_LEVEL_DEFAULT=$DEBUG_LEVEL_1
DEBUG_LEVEL_NONE=0

DOH_CLOUDFLARE=1
DOH_GOOGLE=2
DOH_ALI=3
DOH_DP=4

HIDDEN_VALUE="[hidden](please add '--output-insecure' to see this value)"

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

NOTIFY_LEVEL_DISABLE=0
NOTIFY_LEVEL_ERROR=1
NOTIFY_LEVEL_RENEW=2
NOTIFY_LEVEL_SKIP=3

NOTIFY_LEVEL_DEFAULT=$NOTIFY_LEVEL_RENEW

NOTIFY_MODE_BULK=0
NOTIFY_MODE_CERT=1

NOTIFY_MODE_DEFAULT=$NOTIFY_MODE_BULK

_DEBUG_WIKI="https://github.com/acmesh-official/acme.sh/wiki/How-to-debug-acme.sh"

_PREPARE_LINK="https://github.com/acmesh-official/acme.sh/wiki/Install-preparations"

_STATELESS_WIKI="https://github.com/acmesh-official/acme.sh/wiki/Stateless-Mode"

_DNS_ALIAS_WIKI="https://github.com/acmesh-official/acme.sh/wiki/DNS-alias-mode"

_DNS_MANUAL_WIKI="https://github.com/acmesh-official/acme.sh/wiki/dns-manual-mode"

_DNS_API_WIKI="https://github.com/acmesh-official/acme.sh/wiki/dnsapi"

_NOTIFY_WIKI="https://github.com/acmesh-official/acme.sh/wiki/notify"

_SUDO_WIKI="https://github.com/acmesh-official/acme.sh/wiki/sudo"

_REVOKE_WIKI="https://github.com/acmesh-official/acme.sh/wiki/revokecert"

_ZEROSSL_WIKI="https://github.com/acmesh-official/acme.sh/wiki/ZeroSSL.com-CA"

_SSLCOM_WIKI="https://github.com/acmesh-official/acme.sh/wiki/SSL.com-CA"

_SERVER_WIKI="https://github.com/acmesh-official/acme.sh/wiki/Server"

_PREFERRED_CHAIN_WIKI="https://github.com/acmesh-official/acme.sh/wiki/Preferred-Chain"

_DNSCHECK_WIKI="https://github.com/acmesh-official/acme.sh/wiki/dnscheck"

_DNS_MANUAL_ERR="The dns manual mode can not renew automatically, you must issue it again manually. You'd better use the other modes instead."

_DNS_MANUAL_WARN="It seems that you are using dns manual mode. please take care: $_DNS_MANUAL_ERR"

_DNS_MANUAL_ERROR="It seems that you are using dns manual mode. Read this link first: $_DNS_MANUAL_WIKI"

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

  echo "apache:"
  if [ "$_APACHECTL" ] && _exists "$_APACHECTL"; then
    $_APACHECTL -V 2>&1
  else
    echo "apache doesn't exist."
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

_upper_case() {
  # shellcheck disable=SC2018,SC2019
  tr 'a-z' 'A-Z'
}

_lower_case() {
  # shellcheck disable=SC2018,SC2019
  tr 'A-Z' 'a-z'
}

_startswith() {
  _str="$1"
  _sub="$2"
  echo "$_str" | grep "^$_sub" >/dev/null 2>&1
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

_ESCAPE_XARGS=""
if _exists xargs && [ "$(printf %s '\\x41' | xargs printf)" = 'A' ]; then
  _ESCAPE_XARGS=1
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
    if [ "$_ESCAPE_XARGS" ] && _exists xargs; then
      _debug2 "xargs"
      echo "$hex" | _upper_case | sed 's/\([0-9A-F]\{2\}\)/\\\\\\x\1/g' | xargs printf
    else
      for h in $(echo "$hex" | _upper_case | sed 's/\([0-9A-F]\{2\}\)/ \1/g'); do
        if [ -z "$h" ]; then
          break
        fi
        printf "\x$h%s"
      done
    fi
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

#stdin stdout
_url_encode() {
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
  else
    _debug "No -i support in sed"
    text="$(cat "$filename")"
    echo "$text" | sed "$options" >"$filename"
  fi
}

_egrep_o() {
  if ! egrep -o "$1" 2>/dev/null; then
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
    _err "Can not find start line: $startline"
    return 1
  fi
  i="$(_math "$i" + 1)"
  _debug i "$i"

  j="$(grep -n -- "$endline" "$filename" | cut -d : -f 1)"
  if [ -z "$j" ]; then
    _err "Can not find end line: $endline"
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
    ${ACME_OPENSSL_BIN:-openssl} base64 -d -A
  else
    ${ACME_OPENSSL_BIN:-openssl} base64 -d
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

#Usage: hashalg  [outputhex]
#Output Base64-encoded digest
_digest() {
  alg="$1"
  if [ -z "$alg" ]; then
    _usage "Usage: _digest hashalg"
    return 1
  fi

  outputhex="$2"

  if [ "$alg" = "sha256" ] || [ "$alg" = "sha1" ] || [ "$alg" = "md5" ]; then
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

#Usage: hashalg  secret_hex  [outputhex]
#Output binary hmac
_hmac() {
  alg="$1"
  secret_hex="$2"
  outputhex="$3"

  if [ -z "$secret_hex" ]; then
    _usage "Usage: _hmac hashalg secret [outputhex]"
    return 1
  fi

  if [ "$alg" = "sha256" ] || [ "$alg" = "sha1" ]; then
    if [ "$outputhex" ]; then
      (${ACME_OPENSSL_BIN:-openssl} dgst -"$alg" -mac HMAC -macopt "hexkey:$secret_hex" 2>/dev/null || ${ACME_OPENSSL_BIN:-openssl} dgst -"$alg" -hmac "$(printf "%s" "$secret_hex" | _h2b)") | cut -d = -f 2 | tr -d ' '
    else
      ${ACME_OPENSSL_BIN:-openssl} dgst -"$alg" -mac HMAC -macopt "hexkey:$secret_hex" -binary 2>/dev/null || ${ACME_OPENSSL_BIN:-openssl} dgst -"$alg" -hmac "$(printf "%s" "$secret_hex" | _h2b)" -binary
    fi
  else
    _err "$alg is not supported yet"
    return 1
  fi

}

#Usage: keyfile hashalg
#Output: Base64-encoded signature value
_sign() {
  keyfile="$1"
  alg="$2"
  if [ -z "$alg" ]; then
    _usage "Usage: _sign keyfile hashalg"
    return 1
  fi

  _sign_openssl="${ACME_OPENSSL_BIN:-openssl} dgst -sign $keyfile "

  if grep "BEGIN RSA PRIVATE KEY" "$keyfile" >/dev/null 2>&1 || grep "BEGIN PRIVATE KEY" "$keyfile" >/dev/null 2>&1; then
    $_sign_openssl -$alg | _base64
  elif grep "BEGIN EC PRIVATE KEY" "$keyfile" >/dev/null 2>&1; then
    if ! _signedECText="$($_sign_openssl -sha$__ECC_KEY_LEN | ${ACME_OPENSSL_BIN:-openssl} asn1parse -inform DER)"; then
      _err "Sign failed: $_sign_openssl"
      _err "Key file: $keyfile"
      _err "Key content:$(wc -l <"$keyfile") lines"
      return 1
    fi
    _debug3 "_signedECText" "$_signedECText"
    _ec_r="$(echo "$_signedECText" | _head_n 2 | _tail_n 1 | cut -d : -f 4 | tr -d "\r\n")"
    _ec_s="$(echo "$_signedECText" | _head_n 3 | _tail_n 1 | cut -d : -f 4 | tr -d "\r\n")"
    if [ "$__ECC_KEY_LEN" -eq "256" ]; then
      while [ "${#_ec_r}" -lt "64" ]; do
        _ec_r="0${_ec_r}"
      done
      while [ "${#_ec_s}" -lt "64" ]; do
        _ec_s="0${_ec_s}"
      done
    fi
    if [ "$__ECC_KEY_LEN" -eq "384" ]; then
      while [ "${#_ec_r}" -lt "96" ]; do
        _ec_r="0${_ec_r}"
      done
      while [ "${#_ec_s}" -lt "96" ]; do
        _ec_s="0${_ec_s}"
      done
    fi
    if [ "$__ECC_KEY_LEN" -eq "512" ]; then
      while [ "${#_ec_r}" -lt "132" ]; do
        _ec_r="0${_ec_r}"
      done
      while [ "${#_ec_s}" -lt "132" ]; do
        _ec_s="0${_ec_s}"
      done
    fi
    _debug3 "_ec_r" "$_ec_r"
    _debug3 "_ec_s" "$_ec_s"
    printf "%s" "$_ec_r$_ec_s" | _h2b | _base64
  else
    _err "Unknown key file format."
    return 1
  fi

}

#keylength or isEcc flag (empty str => not ecc)
_isEccKey() {
  _length="$1"

  if [ -z "$_length" ]; then
    return 1
  fi

  [ "$_length" != "1024" ] &&
    [ "$_length" != "2048" ] &&
    [ "$_length" != "3072" ] &&
    [ "$_length" != "4096" ] &&
    [ "$_length" != "8192" ]
}

# _createkey  2048|ec-256   file
_createkey() {
  length="$1"
  f="$2"
  _debug2 "_createkey for file:$f"
  eccname="$length"
  if _startswith "$length" "ec-"; then
    length=$(printf "%s" "$length" | cut -d '-' -f 2-100)

    if [ "$length" = "256" ]; then
      eccname="prime256v1"
    fi
    if [ "$length" = "384" ]; then
      eccname="secp384r1"
    fi
    if [ "$length" = "521" ]; then
      eccname="secp521r1"
    fi

  fi

  if [ -z "$length" ]; then
    length=2048
  fi

  _debug "Use length $length"

  if ! touch "$f" >/dev/null 2>&1; then
    _f_path="$(dirname "$f")"
    _debug _f_path "$_f_path"
    if ! mkdir -p "$_f_path"; then
      _err "Can not create path: $_f_path"
      return 1
    fi
  fi

  if _isEccKey "$length"; then
    _debug "Using ec name: $eccname"
    if _opkey="$(${ACME_OPENSSL_BIN:-openssl} ecparam -name "$eccname" -noout -genkey 2>/dev/null)"; then
      echo "$_opkey" >"$f"
    else
      _err "error ecc key name: $eccname"
      return 1
    fi
  else
    _debug "Using RSA: $length"
    __traditional=""
    if _contains "$(${ACME_OPENSSL_BIN:-openssl} help genrsa 2>&1)" "-traditional"; then
      __traditional="-traditional"
    fi
    if _opkey="$(${ACME_OPENSSL_BIN:-openssl} genrsa $__traditional "$length" 2>/dev/null)"; then
      echo "$_opkey" >"$f"
    else
      _err "error rsa key: $length"
      return 1
    fi
  fi

  if [ "$?" != "0" ]; then
    _err "Create key error."
    return 1
  fi
}

#domain
_is_idn() {
  _is_idn_d="$1"
  _debug2 _is_idn_d "$_is_idn_d"
  _idn_temp=$(printf "%s" "$_is_idn_d" | tr -d '0-9' | tr -d 'a-z' | tr -d 'A-Z' | tr -d '*.,-_')
  _debug2 _idn_temp "$_idn_temp"
  [ "$_idn_temp" ]
}

#aa.com
#aa.com,bb.com,cc.com
_idn() {
  __idn_d="$1"
  if ! _is_idn "$__idn_d"; then
    printf "%s" "$__idn_d"
    return 0
  fi

  if _exists idn; then
    if _contains "$__idn_d" ','; then
      _i_first="1"
      for f in $(echo "$__idn_d" | tr ',' ' '); do
        [ -z "$f" ] && continue
        if [ -z "$_i_first" ]; then
          printf "%s" ","
        else
          _i_first=""
        fi
        idn --quiet "$f" | tr -d "\r\n"
      done
    else
      idn "$__idn_d" | tr -d "\r\n"
    fi
  else
    _err "Please install idn to process IDN names."
  fi
}

#_createcsr  cn  san_list  keyfile csrfile conf acmeValidationv1
_createcsr() {
  _debug _createcsr
  domain="$1"
  domainlist="$2"
  csrkey="$3"
  csr="$4"
  csrconf="$5"
  acmeValidationv1="$6"
  _debug2 domain "$domain"
  _debug2 domainlist "$domainlist"
  _debug2 csrkey "$csrkey"
  _debug2 csr "$csr"
  _debug2 csrconf "$csrconf"

  printf "[ req_distinguished_name ]\n[ req ]\ndistinguished_name = req_distinguished_name\nreq_extensions = v3_req\n[ v3_req ]\n\n" >"$csrconf"

  if [ "$acmeValidationv1" ]; then
    domainlist="$(_idn "$domainlist")"
    printf -- "\nsubjectAltName=DNS:$domainlist" >>"$csrconf"
  elif [ -z "$domainlist" ] || [ "$domainlist" = "$NO_VALUE" ]; then
    #single domain
    _info "Single domain" "$domain"
    printf -- "\nsubjectAltName=DNS:$(_idn "$domain")" >>"$csrconf"
  else
    domainlist="$(_idn "$domainlist")"
    _debug2 domainlist "$domainlist"
    if _contains "$domainlist" ","; then
      alt="DNS:$(_idn "$domain"),DNS:$(echo "$domainlist" | sed "s/,,/,/g" | sed "s/,/,DNS:/g")"
    else
      alt="DNS:$(_idn "$domain"),DNS:$domainlist"
    fi
    #multi
    _info "Multi domain" "$alt"
    printf -- "\nsubjectAltName=$alt" >>"$csrconf"
  fi
  if [ "$Le_OCSP_Staple" = "1" ]; then
    _savedomainconf Le_OCSP_Staple "$Le_OCSP_Staple"
    printf -- "\nbasicConstraints = CA:FALSE\n1.3.6.1.5.5.7.1.24=DER:30:03:02:01:05" >>"$csrconf"
  fi

  if [ "$acmeValidationv1" ]; then
    printf "\n1.3.6.1.5.5.7.1.31=critical,DER:04:20:${acmeValidationv1}" >>"${csrconf}"
  fi

  _csr_cn="$(_idn "$domain")"
  _debug2 _csr_cn "$_csr_cn"
  if _contains "$(uname -a)" "MINGW"; then
    ${ACME_OPENSSL_BIN:-openssl} req -new -sha256 -key "$csrkey" -subj "//CN=$_csr_cn" -config "$csrconf" -out "$csr"
  else
    ${ACME_OPENSSL_BIN:-openssl} req -new -sha256 -key "$csrkey" -subj "/CN=$_csr_cn" -config "$csrconf" -out "$csr"
  fi
}

#_signcsr key  csr  conf cert
_signcsr() {
  key="$1"
  csr="$2"
  conf="$3"
  cert="$4"
  _debug "_signcsr"

  _msg="$(${ACME_OPENSSL_BIN:-openssl} x509 -req -days 365 -in "$csr" -signkey "$key" -extensions v3_req -extfile "$conf" -out "$cert" 2>&1)"
  _ret="$?"
  _debug "$_msg"
  return $_ret
}

#_csrfile
_readSubjectFromCSR() {
  _csrfile="$1"
  if [ -z "$_csrfile" ]; then
    _usage "_readSubjectFromCSR mycsr.csr"
    return 1
  fi
  ${ACME_OPENSSL_BIN:-openssl} req -noout -in "$_csrfile" -subject | tr ',' "\n" | _egrep_o "CN *=.*" | cut -d = -f 2 | cut -d / -f 1 | tr -d ' \n'
}

#_csrfile
#echo comma separated domain list
_readSubjectAltNamesFromCSR() {
  _csrfile="$1"
  if [ -z "$_csrfile" ]; then
    _usage "_readSubjectAltNamesFromCSR mycsr.csr"
    return 1
  fi

  _csrsubj="$(_readSubjectFromCSR "$_csrfile")"
  _debug _csrsubj "$_csrsubj"

  _dnsAltnames="$(${ACME_OPENSSL_BIN:-openssl} req -noout -text -in "$_csrfile" | grep "^ *DNS:.*" | tr -d ' \n')"
  _debug _dnsAltnames "$_dnsAltnames"

  if _contains "$_dnsAltnames," "DNS:$_csrsubj,"; then
    _debug "AltNames contains subject"
    _excapedAlgnames="$(echo "$_dnsAltnames" | tr '*' '#')"
    _debug _excapedAlgnames "$_excapedAlgnames"
    _escapedSubject="$(echo "$_csrsubj" | tr '*' '#')"
    _debug _escapedSubject "$_escapedSubject"
    _dnsAltnames="$(echo "$_excapedAlgnames," | sed "s/DNS:$_escapedSubject,//g" | tr '#' '*' | sed "s/,\$//g")"
    _debug _dnsAltnames "$_dnsAltnames"
  else
    _debug "AltNames doesn't contain subject"
  fi

  echo "$_dnsAltnames" | sed "s/DNS://g"
}

#_csrfile
_readKeyLengthFromCSR() {
  _csrfile="$1"
  if [ -z "$_csrfile" ]; then
    _usage "_readKeyLengthFromCSR mycsr.csr"
    return 1
  fi

  _outcsr="$(${ACME_OPENSSL_BIN:-openssl} req -noout -text -in "$_csrfile")"
  _debug2 _outcsr "$_outcsr"
  if _contains "$_outcsr" "Public Key Algorithm: id-ecPublicKey"; then
    _debug "ECC CSR"
    echo "$_outcsr" | tr "\t" " " | _egrep_o "^ *ASN1 OID:.*" | cut -d ':' -f 2 | tr -d ' '
  else
    _debug "RSA CSR"
    _rkl="$(echo "$_outcsr" | tr "\t" " " | _egrep_o "^ *Public.Key:.*" | cut -d '(' -f 2 | cut -d ' ' -f 1)"
    if [ "$_rkl" ]; then
      echo "$_rkl"
    else
      echo "$_outcsr" | tr "\t" " " | _egrep_o "RSA Public.Key:.*" | cut -d '(' -f 2 | cut -d ' ' -f 1
    fi
  fi
}

_ss() {
  _port="$1"

  if _exists "ss"; then
    _debug "Using: ss"
    ss -ntpl 2>/dev/null | grep ":$_port "
    return 0
  fi

  if _exists "netstat"; then
    _debug "Using: netstat"
    if netstat -help 2>&1 | grep "\-p proto" >/dev/null; then
      #for windows version netstat tool
      netstat -an -p tcp | grep "LISTENING" | grep ":$_port "
    else
      if netstat -help 2>&1 | grep "\-p protocol" >/dev/null; then
        netstat -an -p tcp | grep LISTEN | grep ":$_port "
      elif netstat -help 2>&1 | grep -- '-P protocol' >/dev/null; then
        #for solaris
        netstat -an -P tcp | grep "\.$_port " | grep "LISTEN"
      elif netstat -help 2>&1 | grep "\-p" >/dev/null; then
        #for full linux
        netstat -ntpl | grep ":$_port "
      else
        #for busybox (embedded linux; no pid support)
        netstat -ntl 2>/dev/null | grep ":$_port "
      fi
    fi
    return 0
  fi

  return 1
}

#outfile key cert cacert [password [name [caname]]]
_toPkcs() {
  _cpfx="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  pfxPassword="$5"
  pfxName="$6"
  pfxCaname="$7"

  if [ "$pfxCaname" ]; then
    ${ACME_OPENSSL_BIN:-openssl} pkcs12 -export -out "$_cpfx" -inkey "$_ckey" -in "$_ccert" -certfile "$_cca" -password "pass:$pfxPassword" -name "$pfxName" -caname "$pfxCaname"
  elif [ "$pfxName" ]; then
    ${ACME_OPENSSL_BIN:-openssl} pkcs12 -export -out "$_cpfx" -inkey "$_ckey" -in "$_ccert" -certfile "$_cca" -password "pass:$pfxPassword" -name "$pfxName"
  elif [ "$pfxPassword" ]; then
    ${ACME_OPENSSL_BIN:-openssl} pkcs12 -export -out "$_cpfx" -inkey "$_ckey" -in "$_ccert" -certfile "$_cca" -password "pass:$pfxPassword"
  else
    ${ACME_OPENSSL_BIN:-openssl} pkcs12 -export -out "$_cpfx" -inkey "$_ckey" -in "$_ccert" -certfile "$_cca"
  fi

}

#domain [password] [isEcc]
toPkcs() {
  domain="$1"
  pfxPassword="$2"
  if [ -z "$domain" ]; then
    _usage "Usage: $PROJECT_ENTRY --to-pkcs12 --domain <domain.tld> [--password <password>] [--ecc]"
    return 1
  fi

  _isEcc="$3"

  _initpath "$domain" "$_isEcc"

  _toPkcs "$CERT_PFX_PATH" "$CERT_KEY_PATH" "$CERT_PATH" "$CA_CERT_PATH" "$pfxPassword"

  if [ "$?" = "0" ]; then
    _info "Success, Pfx is exported to: $CERT_PFX_PATH"
  fi

}

#domain [isEcc]
toPkcs8() {
  domain="$1"

  if [ -z "$domain" ]; then
    _usage "Usage: $PROJECT_ENTRY --to-pkcs8 --domain <domain.tld> [--ecc]"
    return 1
  fi

  _isEcc="$2"

  _initpath "$domain" "$_isEcc"

  ${ACME_OPENSSL_BIN:-openssl} pkcs8 -topk8 -inform PEM -outform PEM -nocrypt -in "$CERT_KEY_PATH" -out "$CERT_PKCS8_PATH"

  if [ "$?" = "0" ]; then
    _info "Success, $CERT_PKCS8_PATH"
  fi

}

#[2048]
createAccountKey() {
  _info "Creating account key"
  if [ -z "$1" ]; then
    _usage "Usage: $PROJECT_ENTRY --create-account-key [--accountkeylength <bits>]"
    return
  fi

  length=$1
  _create_account_key "$length"

}

_create_account_key() {

  length=$1

  if [ -z "$length" ] || [ "$length" = "$NO_VALUE" ]; then
    _debug "Use default length $DEFAULT_ACCOUNT_KEY_LENGTH"
    length="$DEFAULT_ACCOUNT_KEY_LENGTH"
  fi

  _debug length "$length"
  _initpath

  mkdir -p "$CA_DIR"
  if [ -s "$ACCOUNT_KEY_PATH" ]; then
    _info "Account key exists, skip"
    return 0
  else
    #generate account key
    if _createkey "$length" "$ACCOUNT_KEY_PATH"; then
      chmod 600 "$ACCOUNT_KEY_PATH"
      _info "Create account key ok."
      return 0
    else
      _err "Create account key error."
      return 1
    fi
  fi

}

#domain [length]
createDomainKey() {
  _info "Creating domain key"
  if [ -z "$1" ]; then
    _usage "Usage: $PROJECT_ENTRY --create-domain-key --domain <domain.tld> [--keylength <bits>]"
    return
  fi

  domain=$1
  _cdl=$2

  if [ -z "$_cdl" ]; then
    _debug "Use DEFAULT_DOMAIN_KEY_LENGTH=$DEFAULT_DOMAIN_KEY_LENGTH"
    _cdl="$DEFAULT_DOMAIN_KEY_LENGTH"
  fi

  _initpath "$domain" "$_cdl"

  if [ ! -f "$CERT_KEY_PATH" ] || [ ! -s "$CERT_KEY_PATH" ] || ([ "$FORCE" ] && ! [ "$_ACME_IS_RENEW" ]) || [ "$Le_ForceNewDomainKey" = "1" ]; then
    if _createkey "$_cdl" "$CERT_KEY_PATH"; then
      _savedomainconf Le_Keylength "$_cdl"
      _info "The domain key is here: $(__green $CERT_KEY_PATH)"
      return 0
    else
      _err "Can not create domain key"
      return 1
    fi
  else
    if [ "$_ACME_IS_RENEW" ]; then
      _info "Domain key exists, skip"
      return 0
    else
      _err "Domain key exists, do you want to overwrite the key?"
      _err "Add '--force', and try again."
      return 1
    fi
  fi

}

# domain  domainlist isEcc
createCSR() {
  _info "Creating csr"
  if [ -z "$1" ]; then
    _usage "Usage: $PROJECT_ENTRY --create-csr --domain <domain.tld> [--domain <domain2.tld> ...]"
    return
  fi

  domain="$1"
  domainlist="$2"
  _isEcc="$3"

  _initpath "$domain" "$_isEcc"

  if [ -f "$CSR_PATH" ] && [ "$_ACME_IS_RENEW" ] && [ -z "$FORCE" ]; then
    _info "CSR exists, skip"
    return
  fi

  if [ ! -f "$CERT_KEY_PATH" ]; then
    _err "The key file is not found: $CERT_KEY_PATH"
    _err "Please create the key file first."
    return 1
  fi
  _createcsr "$domain" "$domainlist" "$CERT_KEY_PATH" "$CSR_PATH" "$DOMAIN_SSL_CONF"

}

_url_replace() {
  tr '/+' '_-' | tr -d '= '
}

#base64 string
_durl_replace_base64() {
  _l=$((${#1} % 4))
  if [ $_l -eq 2 ]; then
    _s="$1"'=='
  elif [ $_l -eq 3 ]; then
    _s="$1"'='
  else
    _s="$1"
  fi
  echo "$_s" | tr '_-' '/+'
}

_time2str() {
  #BSD
  if date -u -r "$1" 2>/dev/null; then
    return
  fi

  #Linux
  if date -u -d@"$1" 2>/dev/null; then
    return
  fi

  #Solaris
  if _exists adb; then
    _t_s_a=$(echo "0t${1}=Y" | adb)
    echo "$_t_s_a"
  fi

  #Busybox
  if echo "$1" | awk '{ print strftime("%c", $0); }' 2>/dev/null; then
    return
  fi
}

_normalizeJson() {
  sed "s/\" *: *\([\"{\[]\)/\":\1/g" | sed "s/^ *\([^ ]\)/\1/" | tr -d "\r\n"
}

_stat() {
  #Linux
  if stat -c '%U:%G' "$1" 2>/dev/null; then
    return
  fi

  #BSD
  if stat -f '%Su:%Sg' "$1" 2>/dev/null; then
    return
  fi

  return 1 #error, 'stat' not found
}

#keyfile
_calcjwk() {
  keyfile="$1"
  if [ -z "$keyfile" ]; then
    _usage "Usage: _calcjwk keyfile"
    return 1
  fi

  if [ "$JWK_HEADER" ] && [ "$__CACHED_JWK_KEY_FILE" = "$keyfile" ]; then
    _debug2 "Use cached jwk for file: $__CACHED_JWK_KEY_FILE"
    return 0
  fi

  if grep "BEGIN RSA PRIVATE KEY" "$keyfile" >/dev/null 2>&1; then
    _debug "RSA key"
    pub_exp=$(${ACME_OPENSSL_BIN:-openssl} rsa -in "$keyfile" -noout -text | grep "^publicExponent:" | cut -d '(' -f 2 | cut -d 'x' -f 2 | cut -d ')' -f 1)
    if [ "${#pub_exp}" = "5" ]; then
      pub_exp=0$pub_exp
    fi
    _debug3 pub_exp "$pub_exp"

    e=$(echo "$pub_exp" | _h2b | _base64)
    _debug3 e "$e"

    modulus=$(${ACME_OPENSSL_BIN:-openssl} rsa -in "$keyfile" -modulus -noout | cut -d '=' -f 2)
    _debug3 modulus "$modulus"
    n="$(printf "%s" "$modulus" | _h2b | _base64 | _url_replace)"
    _debug3 n "$n"

    jwk='{"e": "'$e'", "kty": "RSA", "n": "'$n'"}'
    _debug3 jwk "$jwk"

    JWK_HEADER='{"alg": "RS256", "jwk": '$jwk'}'
    JWK_HEADERPLACE_PART1='{"nonce": "'
    JWK_HEADERPLACE_PART2='", "alg": "RS256"'
  elif grep "BEGIN EC PRIVATE KEY" "$keyfile" >/dev/null 2>&1; then
    _debug "EC key"
    crv="$(${ACME_OPENSSL_BIN:-openssl} ec -in "$keyfile" -noout -text 2>/dev/null | grep "^NIST CURVE:" | cut -d ":" -f 2 | tr -d " \r\n")"
    _debug3 crv "$crv"
    __ECC_KEY_LEN=$(echo "$crv" | cut -d "-" -f 2)
    if [ "$__ECC_KEY_LEN" = "521" ]; then
      __ECC_KEY_LEN=512
    fi
    _debug3 __ECC_KEY_LEN "$__ECC_KEY_LEN"
    if [ -z "$crv" ]; then
      _debug "Let's try ASN1 OID"
      crv_oid="$(${ACME_OPENSSL_BIN:-openssl} ec -in "$keyfile" -noout -text 2>/dev/null | grep "^ASN1 OID:" | cut -d ":" -f 2 | tr -d " \r\n")"
      _debug3 crv_oid "$crv_oid"
      case "${crv_oid}" in
      "prime256v1")
        crv="P-256"
        __ECC_KEY_LEN=256
        ;;
      "secp384r1")
        crv="P-384"
        __ECC_KEY_LEN=384
        ;;
      "secp521r1")
        crv="P-521"
        __ECC_KEY_LEN=512
        ;;
      *)
        _err "ECC oid : $crv_oid"
        return 1
        ;;
      esac
      _debug3 crv "$crv"
    fi

    pubi="$(${ACME_OPENSSL_BIN:-openssl} ec -in "$keyfile" -noout -text 2>/dev/null | grep -n pub: | cut -d : -f 1)"
    pubi=$(_math "$pubi" + 1)
    _debug3 pubi "$pubi"

    pubj="$(${ACME_OPENSSL_BIN:-openssl} ec -in "$keyfile" -noout -text 2>/dev/null | grep -n "ASN1 OID:" | cut -d : -f 1)"
    pubj=$(_math "$pubj" - 1)
    _debug3 pubj "$pubj"

    pubtext="$(${ACME_OPENSSL_BIN:-openssl} ec -in "$keyfile" -noout -text 2>/dev/null | sed -n "$pubi,${pubj}p" | tr -d " \n\r")"
    _debug3 pubtext "$pubtext"

    xlen="$(printf "%s" "$pubtext" | tr -d ':' | wc -c)"
    xlen=$(_math "$xlen" / 4)
    _debug3 xlen "$xlen"

    xend=$(_math "$xlen" + 1)
    x="$(printf "%s" "$pubtext" | cut -d : -f 2-"$xend")"
    _debug3 x "$x"

    x64="$(printf "%s" "$x" | tr -d : | _h2b | _base64 | _url_replace)"
    _debug3 x64 "$x64"

    xend=$(_math "$xend" + 1)
    y="$(printf "%s" "$pubtext" | cut -d : -f "$xend"-10000)"
    _debug3 y "$y"

    y64="$(printf "%s" "$y" | tr -d : | _h2b | _base64 | _url_replace)"
    _debug3 y64 "$y64"

    jwk='{"crv": "'$crv'", "kty": "EC", "x": "'$x64'", "y": "'$y64'"}'
    _debug3 jwk "$jwk"

    JWK_HEADER='{"alg": "ES'$__ECC_KEY_LEN'", "jwk": '$jwk'}'
    JWK_HEADERPLACE_PART1='{"nonce": "'
    JWK_HEADERPLACE_PART2='", "alg": "ES'$__ECC_KEY_LEN'"'
  else
    _err "Only RSA or EC key is supported. keyfile=$keyfile"
    _debug2 "$(cat "$keyfile")"
    return 1
  fi

  _debug3 JWK_HEADER "$JWK_HEADER"
  __CACHED_JWK_KEY_FILE="$keyfile"
}

_time() {
  date -u "+%s"
}

_utc_date() {
  date -u "+%Y-%m-%d %H:%M:%S"
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
  _err "Can not create temp file."
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

    if _contains "$(curl --help 2>&1)" "--globoff"; then
      _ACME_CURL="$_ACME_CURL -g "
    fi
  fi

  if [ -z "$_ACME_WGET" ] && _exists "wget"; then
    _ACME_WGET="wget -q"
    if [ "$ACME_HTTP_NO_REDIRECTS" ]; then
      _ACME_WGET="$_ACME_WGET --max-redirect 0 "
    fi
    if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ]; then
      _ACME_WGET="$_ACME_WGET -d "
    fi
    if [ "$CA_PATH" ]; then
      _ACME_WGET="$_ACME_WGET --ca-directory=$CA_PATH "
    elif [ "$CA_BUNDLE" ]; then
      _ACME_WGET="$_ACME_WGET --ca-certificate=$CA_BUNDLE "
    fi
  fi

  #from wget 1.14: do not skip body on 404 error
  if [ "$_ACME_WGET" ] && _contains "$($_ACME_WGET --help 2>&1)" "--content-on-error"; then
    _ACME_WGET="$_ACME_WGET --content-on-error "
  fi

  __HTTP_INITIALIZED=1

}

_HTTP_MAX_RETRY=8

# body  url [needbase64] [POST|PUT|DELETE] [ContentType]
_post() {
  body="$1"
  _post_url="$2"
  needbase64="$3"
  httpmethod="$4"
  _postContentType="$5"
  _sleep_retry_sec=1
  _http_retry_times=0
  _hcode=0
  while [ "${_http_retry_times}" -le "$_HTTP_MAX_RETRY" ]; do
    [ "$_http_retry_times" = "$_HTTP_MAX_RETRY" ]
    _lastHCode="$?"
    _debug "Retrying post"
    _post_impl "$body" "$_post_url" "$needbase64" "$httpmethod" "$_postContentType" "$_lastHCode"
    _hcode="$?"
    _debug _hcode "$_hcode"
    if [ "$_hcode" = "0" ]; then
      break
    fi
    _http_retry_times=$(_math $_http_retry_times + 1)
    _sleep $_sleep_retry_sec
  done
  return $_hcode
}

# body  url [needbase64] [POST|PUT|DELETE] [ContentType] [displayError]
_post_impl() {
  body="$1"
  _post_url="$2"
  needbase64="$3"
  httpmethod="$4"
  _postContentType="$5"
  displayError="$6"

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
      if [ -z "$displayError" ] || [ "$displayError" = "0" ]; then
        _err "Please refer to https://curl.haxx.se/libcurl/c/libcurl-errors.html for error code: $_ret"
      fi
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
      _debug "wget returns 8, the server returns a 'Bad request' response, lets process the response later."
    fi
    if [ "$_ret" != "0" ]; then
      if [ -z "$displayError" ] || [ "$displayError" = "0" ]; then
        _err "Please refer to https://www.gnu.org/software/wget/manual/html_node/Exit-Status.html for error code: $_ret"
      fi
    fi
    _sed_i "s/^ *//g" "$HTTP_HEADER"
  else
    _ret="$?"
    _err "Neither curl nor wget is found, can not do $httpmethod."
  fi
  _debug "_ret" "$_ret"
  printf "%s" "$response"
  return $_ret
}

# url getheader timeout
_get() {
  url="$1"
  onlyheader="$2"
  t="$3"
  _sleep_retry_sec=1
  _http_retry_times=0
  _hcode=0
  while [ "${_http_retry_times}" -le "$_HTTP_MAX_RETRY" ]; do
    [ "$_http_retry_times" = "$_HTTP_MAX_RETRY" ]
    _lastHCode="$?"
    _debug "Retrying GET"
    _get_impl "$url" "$onlyheader" "$t" "$_lastHCode"
    _hcode="$?"
    _debug _hcode "$_hcode"
    if [ "$_hcode" = "0" ]; then
      break
    fi
    _http_retry_times=$(_math $_http_retry_times + 1)
    _sleep $_sleep_retry_sec
  done
  return $_hcode
}

# url getheader timeout displayError
_get_impl() {
  _debug GET
  url="$1"
  onlyheader="$2"
  t="$3"
  displayError="$4"
  _debug url "$url"
  _debug "timeout=$t"
  _debug "displayError" "$displayError"
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
      if [ -z "$displayError" ] || [ "$displayError" = "0" ]; then
        _err "Please refer to https://curl.haxx.se/libcurl/c/libcurl-errors.html for error code: $ret"
      fi
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
      $_WGET --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" -S -O /dev/null "$url" 2>&1 | sed 's/^[ ]*//g'
    else
      $_WGET --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" -O - "$url"
    fi
    ret=$?
    if [ "$ret" = "8" ]; then
      ret=0
      _debug "wget returns 8, the server returns a 'Bad request' response, lets process the response later."
    fi
    if [ "$ret" != "0" ]; then
      if [ -z "$displayError" ] || [ "$displayError" = "0" ]; then
        _err "Please refer to https://www.gnu.org/software/wget/manual/html_node/Exit-Status.html for error code: $ret"
      fi
    fi
  else
    ret=$?
    _err "Neither curl nor wget is found, can not do GET."
  fi
  _debug "ret" "$ret"
  return $ret
}

_head_n() {
  head -n "$1"
}

_tail_n() {
  if ! tail -n "$1" 2>/dev/null; then
    #fix for solaris
    tail -"$1"
  fi
}

# url  payload needbase64  keyfile
_send_signed_request() {
  url=$1
  payload=$2
  needbase64=$3
  keyfile=$4
  if [ -z "$keyfile" ]; then
    keyfile="$ACCOUNT_KEY_PATH"
  fi
  _debug url "$url"
  _debug payload "$payload"

  if ! _calcjwk "$keyfile"; then
    return 1
  fi

  __request_conent_type="$CONTENT_TYPE_JSON"

  payload64=$(printf "%s" "$payload" | _base64 | _url_replace)
  _debug3 payload64 "$payload64"

  MAX_REQUEST_RETRY_TIMES=20
  _sleep_retry_sec=1
  _request_retry_times=0
  while [ "${_request_retry_times}" -lt "$MAX_REQUEST_RETRY_TIMES" ]; do
    _request_retry_times=$(_math "$_request_retry_times" + 1)
    _debug3 _request_retry_times "$_request_retry_times"
    if [ -z "$_CACHED_NONCE" ]; then
      _headers=""
      if [ "$ACME_NEW_NONCE" ]; then
        _debug2 "Get nonce with HEAD. ACME_NEW_NONCE" "$ACME_NEW_NONCE"
        nonceurl="$ACME_NEW_NONCE"
        if _post "" "$nonceurl" "" "HEAD" "$__request_conent_type" >/dev/null; then
          _headers="$(cat "$HTTP_HEADER")"
          _debug2 _headers "$_headers"
          _CACHED_NONCE="$(echo "$_headers" | grep -i "Replay-Nonce:" | _head_n 1 | tr -d "\r\n " | cut -d ':' -f 2 | cut -d , -f 1)"
        fi
      fi
      if [ -z "$_CACHED_NONCE" ]; then
        _debug2 "Get nonce with GET. ACME_DIRECTORY" "$ACME_DIRECTORY"
        nonceurl="$ACME_DIRECTORY"
        _headers="$(_get "$nonceurl" "onlyheader")"
        _debug2 _headers "$_headers"
        _CACHED_NONCE="$(echo "$_headers" | grep -i "Replay-Nonce:" | _head_n 1 | tr -d "\r\n " | cut -d ':' -f 2)"
      fi
      if [ -z "$_CACHED_NONCE" ] && [ "$ACME_NEW_NONCE" ]; then
        _debug2 "Get nonce with GET. ACME_NEW_NONCE" "$ACME_NEW_NONCE"
        nonceurl="$ACME_NEW_NONCE"
        _headers="$(_get "$nonceurl" "onlyheader")"
        _debug2 _headers "$_headers"
        _CACHED_NONCE="$(echo "$_headers" | grep -i "Replay-Nonce:" | _head_n 1 | tr -d "\r\n " | cut -d ':' -f 2)"
      fi
      _debug2 _CACHED_NONCE "$_CACHED_NONCE"
      if [ "$?" != "0" ]; then
        _err "Can not connect to $nonceurl to get nonce."
        return 1
      fi
    else
      _debug2 "Use _CACHED_NONCE" "$_CACHED_NONCE"
    fi
    nonce="$_CACHED_NONCE"
    _debug2 nonce "$nonce"
    if [ -z "$nonce" ]; then
      _info "Could not get nonce, let's try again."
      _sleep 2
      continue
    fi

    if [ "$url" = "$ACME_NEW_ACCOUNT" ]; then
      protected="$JWK_HEADERPLACE_PART1$nonce\", \"url\": \"${url}$JWK_HEADERPLACE_PART2, \"jwk\": $jwk"'}'
    elif [ "$url" = "$ACME_REVOKE_CERT" ] && [ "$keyfile" != "$ACCOUNT_KEY_PATH" ]; then
      protected="$JWK_HEADERPLACE_PART1$nonce\", \"url\": \"${url}$JWK_HEADERPLACE_PART2, \"jwk\": $jwk"'}'
    else
      protected="$JWK_HEADERPLACE_PART1$nonce\", \"url\": \"${url}$JWK_HEADERPLACE_PART2, \"kid\": \"${ACCOUNT_URL}\""'}'
    fi

    _debug3 protected "$protected"

    protected64="$(printf "%s" "$protected" | _base64 | _url_replace)"
    _debug3 protected64 "$protected64"

    if ! _sig_t="$(printf "%s" "$protected64.$payload64" | _sign "$keyfile" "sha256")"; then
      _err "Sign request failed."
      return 1
    fi
    _debug3 _sig_t "$_sig_t"

    sig="$(printf "%s" "$_sig_t" | _url_replace)"
    _debug3 sig "$sig"

    body="{\"protected\": \"$protected64\", \"payload\": \"$payload64\", \"signature\": \"$sig\"}"
    _debug3 body "$body"

    response="$(_post "$body" "$url" "$needbase64" "POST" "$__request_conent_type")"
    _CACHED_NONCE=""

    if [ "$?" != "0" ]; then
      _err "Can not post to $url"
      return 1
    fi

    responseHeaders="$(cat "$HTTP_HEADER")"
    _debug2 responseHeaders "$responseHeaders"

    code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
    _debug code "$code"

    _debug2 original "$response"
    if echo "$responseHeaders" | grep -i "Content-Type: *application/json" >/dev/null 2>&1; then
      response="$(echo "$response" | _json_decode | _normalizeJson)"
    fi
    _debug2 response "$response"

    _CACHED_NONCE="$(echo "$responseHeaders" | grep -i "Replay-Nonce:" | _head_n 1 | tr -d "\r\n " | cut -d ':' -f 2 | cut -d , -f 1)"

    if ! _startswith "$code" "2"; then
      _body="$response"
      if [ "$needbase64" ]; then
        _body="$(echo "$_body" | _dbase64 multiline)"
        _debug3 _body "$_body"
      fi

      if _contains "$_body" "JWS has invalid anti-replay nonce" || _contains "$_body" "JWS has an invalid anti-replay nonce"; then
        _info "It seems the CA server is busy now, let's wait and retry. Sleeping $_sleep_retry_sec seconds."
        _CACHED_NONCE=""
        _sleep $_sleep_retry_sec
        continue
      fi
      if _contains "$_body" "The Replay Nonce is not recognized"; then
        _info "The replay Nonce is not valid, let's get a new one, Sleeping $_sleep_retry_sec seconds."
        _CACHED_NONCE=""
        _sleep $_sleep_retry_sec
        continue
      fi
    fi
    return 0
  done
  _info "Giving up sending to CA server after $MAX_REQUEST_RETRY_TIMES retries."
  return 1

}

#setopt "file"  "opt"  "="  "value" [";"]
_setopt() {
  __conf="$1"
  __opt="$2"
  __sep="$3"
  __val="$4"
  __end="$5"
  if [ -z "$__opt" ]; then
    _usage usage: _setopt '"file"  "opt"  "="  "value" [";"]'
    return
  fi
  if [ ! -f "$__conf" ]; then
    touch "$__conf"
  fi

  if grep -n "^$__opt$__sep" "$__conf" >/dev/null; then
    _debug3 OK
    if _contains "$__val" "&"; then
      __val="$(echo "$__val" | sed 's/&/\\&/g')"
    fi
    text="$(cat "$__conf")"
    printf -- "%s\n" "$text" | sed "s|^$__opt$__sep.*$|$__opt$__sep$__val$__end|" >"$__conf"

  elif grep -n "^#$__opt$__sep" "$__conf" >/dev/null; then
    if _contains "$__val" "&"; then
      __val="$(echo "$__val" | sed 's/&/\\&/g')"
    fi
    text="$(cat "$__conf")"
    printf -- "%s\n" "$text" | sed "s|^#$__opt$__sep.*$|$__opt$__sep$__val$__end|" >"$__conf"

  else
    _debug3 APP
    echo "$__opt$__sep$__val$__end" >>"$__conf"
  fi
  _debug3 "$(grep -n "^$__opt$__sep" "$__conf")"
}

#_save_conf  file key  value base64encode
#save to conf
_save_conf() {
  _s_c_f="$1"
  _sdkey="$2"
  _sdvalue="$3"
  _b64encode="$4"
  if [ "$_sdvalue" ] && [ "$_b64encode" ]; then
    _sdvalue="${B64CONF_START}$(printf "%s" "${_sdvalue}" | _base64)${B64CONF_END}"
  fi
  if [ "$_s_c_f" ]; then
    _setopt "$_s_c_f" "$_sdkey" "=" "'$_sdvalue'"
  else
    _err "config file is empty, can not save $_sdkey=$_sdvalue"
  fi
}

#_clear_conf file  key
_clear_conf() {
  _c_c_f="$1"
  _sdkey="$2"
  if [ "$_c_c_f" ]; then
    _conf_data="$(cat "$_c_c_f")"
    echo "$_conf_data" | sed "s/^$_sdkey *=.*$//" >"$_c_c_f"
  else
    _err "config file is empty, can not clear"
  fi
}

#_read_conf file  key
_read_conf() {
  _r_c_f="$1"
  _sdkey="$2"
  if [ -f "$_r_c_f" ]; then
    _sdv="$(
      eval "$(grep "^$_sdkey *=" "$_r_c_f")"
      eval "printf \"%s\" \"\$$_sdkey\""
    )"
    if _startswith "$_sdv" "${B64CONF_START}" && _endswith "$_sdv" "${B64CONF_END}"; then
      _sdv="$(echo "$_sdv" | sed "s/${B64CONF_START}//" | sed "s/${B64CONF_END}//" | _dbase64)"
    fi
    printf "%s" "$_sdv"
  else
    _debug "config file is empty, can not read $_sdkey"
  fi
}

#_savedomainconf   key  value  base64encode
#save to domain.conf
_savedomainconf() {
  _save_conf "$DOMAIN_CONF" "$@"
}

#_cleardomainconf   key
_cleardomainconf() {
  _clear_conf "$DOMAIN_CONF" "$1"
}

#_readdomainconf   key
_readdomainconf() {
  _read_conf "$DOMAIN_CONF" "$1"
}

#key  value  base64encode
_savedeployconf() {
  _savedomainconf "SAVED_$1" "$2" "$3"
  #remove later
  _cleardomainconf "$1"
}

#key
_getdeployconf() {
  _rac_key="$1"
  _rac_value="$(eval echo \$"$_rac_key")"
  if [ "$_rac_value" ]; then
    if _startswith "$_rac_value" '"' && _endswith "$_rac_value" '"'; then
      _debug2 "trim quotation marks"
      eval "export $_rac_key=$_rac_value"
    fi
    return 0 # do nothing
  fi
  _saved=$(_readdomainconf "SAVED_$_rac_key")
  eval "export $_rac_key=\"\$_saved\""
}

#_saveaccountconf  key  value  base64encode
_saveaccountconf() {
  _save_conf "$ACCOUNT_CONF_PATH" "$@"
}

#key  value base64encode
_saveaccountconf_mutable() {
  _save_conf "$ACCOUNT_CONF_PATH" "SAVED_$1" "$2" "$3"
  #remove later
  _clearaccountconf "$1"
}

#key
_readaccountconf() {
  _read_conf "$ACCOUNT_CONF_PATH" "$1"
}

#key
_readaccountconf_mutable() {
  _rac_key="$1"
  _readaccountconf "SAVED_$_rac_key"
}

#_clearaccountconf   key
_clearaccountconf() {
  _clear_conf "$ACCOUNT_CONF_PATH" "$1"
}

#key
_clearaccountconf_mutable() {
  _clearaccountconf "SAVED_$1"
  #remove later
  _clearaccountconf "$1"
}

#_savecaconf  key  value
_savecaconf() {
  _save_conf "$CA_CONF" "$1" "$2"
}

#_readcaconf   key
_readcaconf() {
  _read_conf "$CA_CONF" "$1"
}

#_clearaccountconf   key
_clearcaconf() {
  _clear_conf "$CA_CONF" "$1"
}

# content localaddress
_startserver() {
  content="$1"
  ncaddr="$2"
  _debug "content" "$content"
  _debug "ncaddr" "$ncaddr"

  _debug "startserver: $$"

  _debug Le_HTTPPort "$Le_HTTPPort"
  _debug Le_Listen_V4 "$Le_Listen_V4"
  _debug Le_Listen_V6 "$Le_Listen_V6"

  _NC="socat"
  if [ "$Le_Listen_V4" ]; then
    _NC="$_NC -4"
  elif [ "$Le_Listen_V6" ]; then
    _NC="$_NC -6"
  fi

  if [ "$DEBUG" ] && [ "$DEBUG" -gt "1" ]; then
    _NC="$_NC -d -d -v"
  fi

  SOCAT_OPTIONS=TCP-LISTEN:$Le_HTTPPort,crlf,reuseaddr,fork

  #Adding bind to local-address
  if [ "$ncaddr" ]; then
    SOCAT_OPTIONS="$SOCAT_OPTIONS,bind=${ncaddr}"
  fi

  _content_len="$(printf "%s" "$content" | wc -c)"
  _debug _content_len "$_content_len"
  _debug "_NC" "$_NC $SOCAT_OPTIONS"
  $_NC $SOCAT_OPTIONS SYSTEM:"sleep 1; \
echo 'HTTP/1.0 200 OK'; \
echo 'Content-Length\: $_content_len'; \
echo ''; \
printf '%s' '$content';" &
  serverproc="$!"
}

_stopserver() {
  pid="$1"
  _debug "pid" "$pid"
  if [ -z "$pid" ]; then
    return
  fi

  kill $pid

}

# sleep sec
_sleep() {
  _sleep_sec="$1"
  if [ "$__INTERACTIVE" ]; then
    _sleep_c="$_sleep_sec"
    while [ "$_sleep_c" -ge "0" ]; do
      printf "\r      \r"
      __green "$_sleep_c"
      _sleep_c="$(_math "$_sleep_c" - 1)"
      sleep 1
    done
    printf "\r"
  else
    sleep "$_sleep_sec"
  fi
}

# _starttlsserver  san_a  san_b port content _ncaddr acmeValidationv1
_starttlsserver() {
  _info "Starting tls server."
  san_a="$1"
  san_b="$2"
  port="$3"
  content="$4"
  opaddr="$5"
  acmeValidationv1="$6"

  _debug san_a "$san_a"
  _debug san_b "$san_b"
  _debug port "$port"
  _debug acmeValidationv1 "$acmeValidationv1"

  #create key TLS_KEY
  if ! _createkey "2048" "$TLS_KEY"; then
    _err "Create tls validation key error."
    return 1
  fi

  #create csr
  alt="$san_a"
  if [ "$san_b" ]; then
    alt="$alt,$san_b"
  fi
  if ! _createcsr "tls.acme.sh" "$alt" "$TLS_KEY" "$TLS_CSR" "$TLS_CONF" "$acmeValidationv1"; then
    _err "Create tls validation csr error."
    return 1
  fi

  #self signed
  if ! _signcsr "$TLS_KEY" "$TLS_CSR" "$TLS_CONF" "$TLS_CERT"; then
    _err "Create tls validation cert error."
    return 1
  fi

  __S_OPENSSL="${ACME_OPENSSL_BIN:-openssl} s_server -www -cert $TLS_CERT  -key $TLS_KEY "
  if [ "$opaddr" ]; then
    __S_OPENSSL="$__S_OPENSSL -accept $opaddr:$port"
  else
    __S_OPENSSL="$__S_OPENSSL -accept $port"
  fi

  _debug Le_Listen_V4 "$Le_Listen_V4"
  _debug Le_Listen_V6 "$Le_Listen_V6"
  if [ "$Le_Listen_V4" ]; then
    __S_OPENSSL="$__S_OPENSSL -4"
  elif [ "$Le_Listen_V6" ]; then
    __S_OPENSSL="$__S_OPENSSL -6"
  fi

  if [ "$acmeValidationv1" ]; then
    __S_OPENSSL="$__S_OPENSSL -alpn acme-tls/1"
  fi

  _debug "$__S_OPENSSL"
  if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ]; then
    $__S_OPENSSL -tlsextdebug &
  else
    $__S_OPENSSL >/dev/null 2>&1 &
  fi

  serverproc="$!"
  sleep 1
  _debug serverproc "$serverproc"
}

#file
_readlink() {
  _rf="$1"
  if ! readlink -f "$_rf" 2>/dev/null; then
    if _startswith "$_rf" "/"; then
      echo "$_rf"
      return 0
    fi
    echo "$(pwd)/$_rf" | _conapath
  fi
}

_conapath() {
  sed "s#/\./#/#g"
}

__initHome() {
  if [ -z "$_SCRIPT_HOME" ]; then
    if _exists readlink && _exists dirname; then
      _debug "Lets find script dir."
      _debug "_SCRIPT_" "$_SCRIPT_"
      _script="$(_readlink "$_SCRIPT_")"
      _debug "_script" "$_script"
      _script_home="$(dirname "$_script")"
      _debug "_script_home" "$_script_home"
      if [ -d "$_script_home" ]; then
        _SCRIPT_HOME="$_script_home"
      else
        _err "It seems the script home is not correct:$_script_home"
      fi
    fi
  fi

  #  if [ -z "$LE_WORKING_DIR" ]; then
  #    if [ -f "$DEFAULT_INSTALL_HOME/account.conf" ]; then
  #      _debug "It seems that $PROJECT_NAME is already installed in $DEFAULT_INSTALL_HOME"
  #      LE_WORKING_DIR="$DEFAULT_INSTALL_HOME"
  #    else
  #      LE_WORKING_DIR="$_SCRIPT_HOME"
  #    fi
  #  fi

  if [ -z "$LE_WORKING_DIR" ]; then
    _debug "Using default home:$DEFAULT_INSTALL_HOME"
    LE_WORKING_DIR="$DEFAULT_INSTALL_HOME"
  fi
  export LE_WORKING_DIR

  if [ -z "$LE_CONFIG_HOME" ]; then
    LE_CONFIG_HOME="$LE_WORKING_DIR"
  fi
  _debug "Using config home:$LE_CONFIG_HOME"
  export LE_CONFIG_HOME

  _DEFAULT_ACCOUNT_CONF_PATH="$LE_CONFIG_HOME/account.conf"

  if [ -z "$ACCOUNT_CONF_PATH" ]; then
    if [ -f "$_DEFAULT_ACCOUNT_CONF_PATH" ]; then
      . "$_DEFAULT_ACCOUNT_CONF_PATH"
    fi
  fi

  if [ -z "$ACCOUNT_CONF_PATH" ]; then
    ACCOUNT_CONF_PATH="$_DEFAULT_ACCOUNT_CONF_PATH"
  fi
  _debug3 ACCOUNT_CONF_PATH "$ACCOUNT_CONF_PATH"
  DEFAULT_LOG_FILE="$LE_CONFIG_HOME/$PROJECT_NAME.log"

  DEFAULT_CA_HOME="$LE_CONFIG_HOME/ca"

  if [ -z "$LE_TEMP_DIR" ]; then
    LE_TEMP_DIR="$LE_CONFIG_HOME/tmp"
  fi
}

_clearAPI() {
  ACME_NEW_ACCOUNT=""
  ACME_KEY_CHANGE=""
  ACME_NEW_AUTHZ=""
  ACME_NEW_ORDER=""
  ACME_REVOKE_CERT=""
  ACME_NEW_NONCE=""
  ACME_AGREEMENT=""
}

#server
_initAPI() {
  _api_server="${1:-$ACME_DIRECTORY}"
  _debug "_init api for server: $_api_server"

  MAX_API_RETRY_TIMES=10
  _sleep_retry_sec=10
  _request_retry_times=0
  while [ -z "$ACME_NEW_ACCOUNT" ] && [ "${_request_retry_times}" -lt "$MAX_API_RETRY_TIMES" ]; do
    _request_retry_times=$(_math "$_request_retry_times" + 1)
    response=$(_get "$_api_server")
    if [ "$?" != "0" ]; then
      _debug2 "response" "$response"
      _info "Can not init api for: $_api_server."
      _info "Sleep $_sleep_retry_sec and retry."
      _sleep "$_sleep_retry_sec"
      continue
    fi
    response=$(echo "$response" | _json_decode)
    _debug2 "response" "$response"

    ACME_KEY_CHANGE=$(echo "$response" | _egrep_o 'keyChange" *: *"[^"]*"' | cut -d '"' -f 3)
    export ACME_KEY_CHANGE

    ACME_NEW_AUTHZ=$(echo "$response" | _egrep_o 'newAuthz" *: *"[^"]*"' | cut -d '"' -f 3)
    export ACME_NEW_AUTHZ

    ACME_NEW_ORDER=$(echo "$response" | _egrep_o 'newOrder" *: *"[^"]*"' | cut -d '"' -f 3)
    export ACME_NEW_ORDER

    ACME_NEW_ACCOUNT=$(echo "$response" | _egrep_o 'newAccount" *: *"[^"]*"' | cut -d '"' -f 3)
    export ACME_NEW_ACCOUNT

    ACME_REVOKE_CERT=$(echo "$response" | _egrep_o 'revokeCert" *: *"[^"]*"' | cut -d '"' -f 3)
    export ACME_REVOKE_CERT

    ACME_NEW_NONCE=$(echo "$response" | _egrep_o 'newNonce" *: *"[^"]*"' | cut -d '"' -f 3)
    export ACME_NEW_NONCE

    ACME_AGREEMENT=$(echo "$response" | _egrep_o 'termsOfService" *: *"[^"]*"' | cut -d '"' -f 3)
    export ACME_AGREEMENT

    _debug "ACME_KEY_CHANGE" "$ACME_KEY_CHANGE"
    _debug "ACME_NEW_AUTHZ" "$ACME_NEW_AUTHZ"
    _debug "ACME_NEW_ORDER" "$ACME_NEW_ORDER"
    _debug "ACME_NEW_ACCOUNT" "$ACME_NEW_ACCOUNT"
    _debug "ACME_REVOKE_CERT" "$ACME_REVOKE_CERT"
    _debug "ACME_AGREEMENT" "$ACME_AGREEMENT"
    _debug "ACME_NEW_NONCE" "$ACME_NEW_NONCE"
    if [ "$ACME_NEW_ACCOUNT" ] && [ "$ACME_NEW_ORDER" ]; then
      return 0
    fi
    _info "Sleep $_sleep_retry_sec and retry."
    _sleep "$_sleep_retry_sec"
  done
  if [ "$ACME_NEW_ACCOUNT" ] && [ "$ACME_NEW_ORDER" ]; then
    return 0
  fi
  _err "Can not init api, for $_api_server"
  return 1
}

#[domain]  [keylength or isEcc flag]
_initpath() {
  domain="$1"
  _ilength="$2"

  __initHome

  if [ -f "$ACCOUNT_CONF_PATH" ]; then
    . "$ACCOUNT_CONF_PATH"
  fi

  if [ "$_ACME_IN_CRON" ]; then
    if [ ! "$_USER_PATH_EXPORTED" ]; then
      _USER_PATH_EXPORTED=1
      export PATH="$USER_PATH:$PATH"
    fi
  fi

  if [ -z "$CA_HOME" ]; then
    CA_HOME="$DEFAULT_CA_HOME"
  fi

  if [ -z "$ACME_DIRECTORY" ]; then
    if [ "$STAGE" ]; then
      ACME_DIRECTORY="$DEFAULT_STAGING_CA"
      _info "Using ACME_DIRECTORY: $ACME_DIRECTORY"
    else
      default_acme_server=$(_readaccountconf "DEFAULT_ACME_SERVER")
      _debug default_acme_server "$default_acme_server"
      if [ "$default_acme_server" ]; then
        ACME_DIRECTORY="$default_acme_server"
      else
        ACME_DIRECTORY="$DEFAULT_CA"
      fi
    fi
  fi

  _debug ACME_DIRECTORY "$ACME_DIRECTORY"
  _ACME_SERVER_HOST="$(echo "$ACME_DIRECTORY" | cut -d : -f 2 | tr -s / | cut -d / -f 2)"
  _debug2 "_ACME_SERVER_HOST" "$_ACME_SERVER_HOST"

  _ACME_SERVER_PATH="$(echo "$ACME_DIRECTORY" | cut -d : -f 2- | tr -s / | cut -d / -f 3-)"
  _debug2 "_ACME_SERVER_PATH" "$_ACME_SERVER_PATH"

  CA_DIR="$CA_HOME/$_ACME_SERVER_HOST/$_ACME_SERVER_PATH"
  _DEFAULT_CA_CONF="$CA_DIR/ca.conf"
  if [ -z "$CA_CONF" ]; then
    CA_CONF="$_DEFAULT_CA_CONF"
  fi
  _debug3 CA_CONF "$CA_CONF"

  _OLD_CADIR="$CA_HOME/$_ACME_SERVER_HOST"
  _OLD_ACCOUNT_KEY="$_OLD_CADIR/account.key"
  _OLD_ACCOUNT_JSON="$_OLD_CADIR/account.json"
  _OLD_CA_CONF="$_OLD_CADIR/ca.conf"

  _DEFAULT_ACCOUNT_KEY_PATH="$CA_DIR/account.key"
  _DEFAULT_ACCOUNT_JSON_PATH="$CA_DIR/account.json"
  if [ -z "$ACCOUNT_KEY_PATH" ]; then
    ACCOUNT_KEY_PATH="$_DEFAULT_ACCOUNT_KEY_PATH"
    if [ -f "$_OLD_ACCOUNT_KEY" ] && ! [ -f "$ACCOUNT_KEY_PATH" ]; then
      mkdir -p "$CA_DIR"
      mv "$_OLD_ACCOUNT_KEY" "$ACCOUNT_KEY_PATH"
    fi
  fi

  if [ -z "$ACCOUNT_JSON_PATH" ]; then
    ACCOUNT_JSON_PATH="$_DEFAULT_ACCOUNT_JSON_PATH"
    if [ -f "$_OLD_ACCOUNT_JSON" ] && ! [ -f "$ACCOUNT_JSON_PATH" ]; then
      mkdir -p "$CA_DIR"
      mv "$_OLD_ACCOUNT_JSON" "$ACCOUNT_JSON_PATH"
    fi
  fi

  if [ -f "$_OLD_CA_CONF" ] && ! [ -f "$CA_CONF" ]; then
    mkdir -p "$CA_DIR"
    mv "$_OLD_CA_CONF" "$CA_CONF"
  fi

  if [ -f "$CA_CONF" ]; then
    . "$CA_CONF"
  fi

  if [ -z "$ACME_DIR" ]; then
    ACME_DIR="/home/.acme"
  fi

  if [ -z "$APACHE_CONF_BACKUP_DIR" ]; then
    APACHE_CONF_BACKUP_DIR="$LE_CONFIG_HOME"
  fi

  if [ -z "$USER_AGENT" ]; then
    USER_AGENT="$DEFAULT_USER_AGENT"
  fi

  if [ -z "$HTTP_HEADER" ]; then
    HTTP_HEADER="$LE_CONFIG_HOME/http.header"
  fi

  _DEFAULT_CERT_HOME="$LE_CONFIG_HOME"
  if [ -z "$CERT_HOME" ]; then
    CERT_HOME="$_DEFAULT_CERT_HOME"
  fi

  if [ -z "$ACME_OPENSSL_BIN" ] || [ ! -f "$ACME_OPENSSL_BIN" ] || [ ! -x "$ACME_OPENSSL_BIN" ]; then
    ACME_OPENSSL_BIN="$DEFAULT_OPENSSL_BIN"
  fi

  if [ -z "$domain" ]; then
    return 0
  fi

  if [ -z "$DOMAIN_PATH" ]; then
    domainhome="$CERT_HOME/$domain"
    domainhomeecc="$CERT_HOME/$domain$ECC_SUFFIX"

    DOMAIN_PATH="$domainhome"

    if _isEccKey "$_ilength"; then
      DOMAIN_PATH="$domainhomeecc"
    else
      if [ ! -d "$domainhome" ] && [ -d "$domainhomeecc" ]; then
        _info "The domain '$domain' seems to have a ECC cert already, please add '$(__red "--ecc")' parameter if you want to use that cert."
      fi
    fi
    _debug DOMAIN_PATH "$DOMAIN_PATH"
  fi

  if [ -z "$DOMAIN_BACKUP_PATH" ]; then
    DOMAIN_BACKUP_PATH="$DOMAIN_PATH/backup"
  fi

  if [ -z "$DOMAIN_CONF" ]; then
    DOMAIN_CONF="$DOMAIN_PATH/$domain.conf"
  fi

  if [ -z "$DOMAIN_SSL_CONF" ]; then
    DOMAIN_SSL_CONF="$DOMAIN_PATH/$domain.csr.conf"
  fi

  if [ -z "$CSR_PATH" ]; then
    CSR_PATH="$DOMAIN_PATH/$domain.csr"
  fi
  if [ -z "$CERT_KEY_PATH" ]; then
    CERT_KEY_PATH="$DOMAIN_PATH/$domain.key"
  fi
  if [ -z "$CERT_PATH" ]; then
    CERT_PATH="$DOMAIN_PATH/$domain.cer"
  fi
  if [ -z "$CA_CERT_PATH" ]; then
    CA_CERT_PATH="$DOMAIN_PATH/ca.cer"
  fi
  if [ -z "$CERT_FULLCHAIN_PATH" ]; then
    CERT_FULLCHAIN_PATH="$DOMAIN_PATH/fullchain.cer"
  fi
  if [ -z "$CERT_PFX_PATH" ]; then
    CERT_PFX_PATH="$DOMAIN_PATH/$domain.pfx"
  fi
  if [ -z "$CERT_PKCS8_PATH" ]; then
    CERT_PKCS8_PATH="$DOMAIN_PATH/$domain.pkcs8"
  fi

  if [ -z "$TLS_CONF" ]; then
    TLS_CONF="$DOMAIN_PATH/tls.validation.conf"
  fi
  if [ -z "$TLS_CERT" ]; then
    TLS_CERT="$DOMAIN_PATH/tls.validation.cert"
  fi
  if [ -z "$TLS_KEY" ]; then
    TLS_KEY="$DOMAIN_PATH/tls.validation.key"
  fi
  if [ -z "$TLS_CSR" ]; then
    TLS_CSR="$DOMAIN_PATH/tls.validation.csr"
  fi

}

_exec() {
  if [ -z "$_EXEC_TEMP_ERR" ]; then
    _EXEC_TEMP_ERR="$(_mktemp)"
  fi

  if [ "$_EXEC_TEMP_ERR" ]; then
    eval "$@ 2>>$_EXEC_TEMP_ERR"
  else
    eval "$@"
  fi
}

_exec_err() {
  [ "$_EXEC_TEMP_ERR" ] && _err "$(cat "$_EXEC_TEMP_ERR")" && echo "" >"$_EXEC_TEMP_ERR"
}

_apachePath() {
  _APACHECTL="apachectl"
  if ! _exists apachectl; then
    if _exists apache2ctl; then
      _APACHECTL="apache2ctl"
    else
      _err "'apachectl not found. It seems that apache is not installed, or you are not root user.'"
      _err "Please use webroot mode to try again."
      return 1
    fi
  fi

  if ! _exec $_APACHECTL -V >/dev/null; then
    _exec_err
    return 1
  fi

  if [ "$APACHE_HTTPD_CONF" ]; then
    _saveaccountconf APACHE_HTTPD_CONF "$APACHE_HTTPD_CONF"
    httpdconf="$APACHE_HTTPD_CONF"
    httpdconfname="$(basename "$httpdconfname")"
  else
    httpdconfname="$($_APACHECTL -V | grep SERVER_CONFIG_FILE= | cut -d = -f 2 | tr -d '"')"
    _debug httpdconfname "$httpdconfname"

    if [ -z "$httpdconfname" ]; then
      _err "Can not read apache config file."
      return 1
    fi

    if _startswith "$httpdconfname" '/'; then
      httpdconf="$httpdconfname"
      httpdconfname="$(basename "$httpdconfname")"
    else
      httpdroot="$($_APACHECTL -V | grep HTTPD_ROOT= | cut -d = -f 2 | tr -d '"')"
      _debug httpdroot "$httpdroot"
      httpdconf="$httpdroot/$httpdconfname"
      httpdconfname="$(basename "$httpdconfname")"
    fi
  fi
  _debug httpdconf "$httpdconf"
  _debug httpdconfname "$httpdconfname"
  if [ ! -f "$httpdconf" ]; then
    _err "Apache Config file not found" "$httpdconf"
    return 1
  fi
  return 0
}

_restoreApache() {
  if [ -z "$usingApache" ]; then
    return 0
  fi
  _initpath
  if ! _apachePath; then
    return 1
  fi

  if [ ! -f "$APACHE_CONF_BACKUP_DIR/$httpdconfname" ]; then
    _debug "No config file to restore."
    return 0
  fi

  cat "$APACHE_CONF_BACKUP_DIR/$httpdconfname" >"$httpdconf"
  _debug "Restored: $httpdconf."
  if ! _exec $_APACHECTL -t; then
    _exec_err
    _err "Sorry, restore apache config error, please contact me."
    return 1
  fi
  _debug "Restored successfully."
  rm -f "$APACHE_CONF_BACKUP_DIR/$httpdconfname"
  return 0
}

_setApache() {
  _initpath
  if ! _apachePath; then
    return 1
  fi

  #test the conf first
  _info "Checking if there is an error in the apache config file before starting."

  if ! _exec "$_APACHECTL" -t >/dev/null; then
    _exec_err
    _err "The apache config file has error, please fix it first, then try again."
    _err "Don't worry, there is nothing changed to your system."
    return 1
  else
    _info "OK"
  fi

  #backup the conf
  _debug "Backup apache config file" "$httpdconf"
  if ! cp "$httpdconf" "$APACHE_CONF_BACKUP_DIR/"; then
    _err "Can not backup apache config file, so abort. Don't worry, the apache config is not changed."
    _err "This might be a bug of $PROJECT_NAME , please report issue: $PROJECT"
    return 1
  fi
  _info "JFYI, Config file $httpdconf is backuped to $APACHE_CONF_BACKUP_DIR/$httpdconfname"
  _info "In case there is an error that can not be restored automatically, you may try restore it yourself."
  _info "The backup file will be deleted on success, just forget it."

  #add alias

  apacheVer="$($_APACHECTL -V | grep "Server version:" | cut -d : -f 2 | cut -d " " -f 2 | cut -d '/' -f 2)"
  _debug "apacheVer" "$apacheVer"
  apacheMajor="$(echo "$apacheVer" | cut -d . -f 1)"
  apacheMinor="$(echo "$apacheVer" | cut -d . -f 2)"

  if [ "$apacheVer" ] && [ "$apacheMajor$apacheMinor" -ge "24" ]; then
    echo "
Alias /.well-known/acme-challenge  $ACME_DIR

<Directory $ACME_DIR >
Require all granted
</Directory>
  " >>"$httpdconf"
  else
    echo "
Alias /.well-known/acme-challenge  $ACME_DIR

<Directory $ACME_DIR >
Order allow,deny
Allow from all
</Directory>
  " >>"$httpdconf"
  fi

  _msg="$($_APACHECTL -t 2>&1)"
  if [ "$?" != "0" ]; then
    _err "Sorry, apache config error"
    if _restoreApache; then
      _err "The apache config file is restored."
    else
      _err "Sorry, the apache config file can not be restored, please report bug."
    fi
    return 1
  fi

  if [ ! -d "$ACME_DIR" ]; then
    mkdir -p "$ACME_DIR"
    chmod 755 "$ACME_DIR"
  fi

  if ! _exec "$_APACHECTL" graceful; then
    _exec_err
    _err "$_APACHECTL  graceful error, please contact me."
    _restoreApache
    return 1
  fi
  usingApache="1"
  return 0
}

#find the real nginx conf file
#backup
#set the nginx conf
#returns the real nginx conf file
_setNginx() {
  _d="$1"
  _croot="$2"
  _thumbpt="$3"

  FOUND_REAL_NGINX_CONF=""
  FOUND_REAL_NGINX_CONF_LN=""
  BACKUP_NGINX_CONF=""
  _debug _croot "$_croot"
  _start_f="$(echo "$_croot" | cut -d : -f 2)"
  _debug _start_f "$_start_f"
  if [ -z "$_start_f" ]; then
    _debug "find start conf from nginx command"
    if [ -z "$NGINX_CONF" ]; then
      if ! _exists "nginx"; then
        _err "nginx command is not found."
        return 1
      fi
      NGINX_CONF="$(nginx -V 2>&1 | _egrep_o "--conf-path=[^ ]* " | tr -d " ")"
      _debug NGINX_CONF "$NGINX_CONF"
      NGINX_CONF="$(echo "$NGINX_CONF" | cut -d = -f 2)"
      _debug NGINX_CONF "$NGINX_CONF"
      if [ -z "$NGINX_CONF" ]; then
        _err "Can not find nginx conf."
        NGINX_CONF=""
        return 1
      fi
      if [ ! -f "$NGINX_CONF" ]; then
        _err "'$NGINX_CONF' doesn't exist."
        NGINX_CONF=""
        return 1
      fi
      _debug "Found nginx conf file:$NGINX_CONF"
    fi
    _start_f="$NGINX_CONF"
  fi
  _debug "Start detect nginx conf for $_d from:$_start_f"
  if ! _checkConf "$_d" "$_start_f"; then
    _err "Can not find conf file for domain $d"
    return 1
  fi
  _info "Found conf file: $FOUND_REAL_NGINX_CONF"

  _ln=$FOUND_REAL_NGINX_CONF_LN
  _debug "_ln" "$_ln"

  _lnn=$(_math $_ln + 1)
  _debug _lnn "$_lnn"
  _start_tag="$(sed -n "$_lnn,${_lnn}p" "$FOUND_REAL_NGINX_CONF")"
  _debug "_start_tag" "$_start_tag"
  if [ "$_start_tag" = "$NGINX_START" ]; then
    _info "The domain $_d is already configured, skip"
    FOUND_REAL_NGINX_CONF=""
    return 0
  fi

  mkdir -p "$DOMAIN_BACKUP_PATH"
  _backup_conf="$DOMAIN_BACKUP_PATH/$_d.nginx.conf"
  _debug _backup_conf "$_backup_conf"
  BACKUP_NGINX_CONF="$_backup_conf"
  _info "Backup $FOUND_REAL_NGINX_CONF to $_backup_conf"
  if ! cp "$FOUND_REAL_NGINX_CONF" "$_backup_conf"; then
    _err "backup error."
    FOUND_REAL_NGINX_CONF=""
    return 1
  fi

  if ! _exists "nginx"; then
    _err "nginx command is not found."
    return 1
  fi
  _info "Check the nginx conf before setting up."
  if ! _exec "nginx -t" >/dev/null; then
    _exec_err
    return 1
  fi

  _info "OK, Set up nginx config file"

  if ! sed -n "1,${_ln}p" "$_backup_conf" >"$FOUND_REAL_NGINX_CONF"; then
    cat "$_backup_conf" >"$FOUND_REAL_NGINX_CONF"
    _err "write nginx conf error, but don't worry, the file is restored to the original version."
    return 1
  fi

  echo "$NGINX_START
location ~ \"^/\.well-known/acme-challenge/([-_a-zA-Z0-9]+)\$\" {
  default_type text/plain;
  return 200 \"\$1.$_thumbpt\";
}
#NGINX_START
" >>"$FOUND_REAL_NGINX_CONF"

  if ! sed -n "${_lnn},99999p" "$_backup_conf" >>"$FOUND_REAL_NGINX_CONF"; then
    cat "$_backup_conf" >"$FOUND_REAL_NGINX_CONF"
    _err "write nginx conf error, but don't worry, the file is restored."
    return 1
  fi
  _debug3 "Modified config:$(cat $FOUND_REAL_NGINX_CONF)"
  _info "nginx conf is done, let's check it again."
  if ! _exec "nginx -t" >/dev/null; then
    _exec_err
    _err "It seems that nginx conf was broken, let's restore."
    cat "$_backup_conf" >"$FOUND_REAL_NGINX_CONF"
    return 1
  fi

  _info "Reload nginx"
  if ! _exec "nginx -s reload" >/dev/null; then
    _exec_err
    _err "It seems that nginx reload error, let's restore."
    cat "$_backup_conf" >"$FOUND_REAL_NGINX_CONF"
    return 1
  fi

  return 0
}

#d , conf
_checkConf() {
  _d="$1"
  _c_file="$2"
  _debug "Start _checkConf from:$_c_file"
  if [ ! -f "$2" ] && ! echo "$2" | grep '*$' >/dev/null && echo "$2" | grep '*' >/dev/null; then
    _debug "wildcard"
    for _w_f in $2; do
      if [ -f "$_w_f" ] && _checkConf "$1" "$_w_f"; then
        return 0
      fi
    done
    #not found
    return 1
  elif [ -f "$2" ]; then
    _debug "single"
    if _isRealNginxConf "$1" "$2"; then
      _debug "$2 is found."
      FOUND_REAL_NGINX_CONF="$2"
      return 0
    fi
    if cat "$2" | tr "\t" " " | grep "^ *include *.*;" >/dev/null; then
      _debug "Try include files"
      for included in $(cat "$2" | tr "\t" " " | grep "^ *include *.*;" | sed "s/include //" | tr -d " ;"); do
        _debug "check included $included"
        if ! _startswith "$included" "/" && _exists dirname; then
          _relpath="$(dirname "$_c_file")"
          _debug "_relpath" "$_relpath"
          included="$_relpath/$included"
        fi
        if _checkConf "$1" "$included"; then
          return 0
        fi
      done
    fi
    return 1
  else
    _debug "$2 not found."
    return 1
  fi
  return 1
}

#d , conf
_isRealNginxConf() {
  _debug "_isRealNginxConf $1 $2"
  if [ -f "$2" ]; then
    for _fln in $(tr "\t" ' ' <"$2" | grep -n "^ *server_name.* $1" | cut -d : -f 1); do
      _debug _fln "$_fln"
      if [ "$_fln" ]; then
        _start=$(tr "\t" ' ' <"$2" | _head_n "$_fln" | grep -n "^ *server *" | grep -v server_name | _tail_n 1)
        _debug "_start" "$_start"
        _start_n=$(echo "$_start" | cut -d : -f 1)
        _start_nn=$(_math $_start_n + 1)
        _debug "_start_n" "$_start_n"
        _debug "_start_nn" "$_start_nn"

        _left="$(sed -n "${_start_nn},99999p" "$2")"
        _debug2 _left "$_left"
        _end="$(echo "$_left" | tr "\t" ' ' | grep -n "^ *server *" | grep -v server_name | _head_n 1)"
        _debug "_end" "$_end"
        if [ "$_end" ]; then
          _end_n=$(echo "$_end" | cut -d : -f 1)
          _debug "_end_n" "$_end_n"
          _seg_n=$(echo "$_left" | sed -n "1,${_end_n}p")
        else
          _seg_n="$_left"
        fi

        _debug "_seg_n" "$_seg_n"

        _skip_ssl=1
        for _listen_i in $(echo "$_seg_n" | tr "\t" ' ' | grep "^ *listen" | tr -d " "); do
          if [ "$_listen_i" ]; then
            if [ "$(echo "$_listen_i" | _egrep_o "listen.*ssl")" ]; then
              _debug2 "$_listen_i is ssl"
            else
              _debug2 "$_listen_i is plain text"
              _skip_ssl=""
              break
            fi
          fi
        done

        if [ "$_skip_ssl" = "1" ]; then
          _debug "ssl on, skip"
        else
          FOUND_REAL_NGINX_CONF_LN=$_fln
          _debug3 "found FOUND_REAL_NGINX_CONF_LN" "$FOUND_REAL_NGINX_CONF_LN"
          return 0
        fi
      fi
    done
  fi
  return 1
}

#restore all the nginx conf
_restoreNginx() {
  if [ -z "$NGINX_RESTORE_VLIST" ]; then
    _debug "No need to restore nginx, skip."
    return
  fi
  _debug "_restoreNginx"
  _debug "NGINX_RESTORE_VLIST" "$NGINX_RESTORE_VLIST"

  for ng_entry in $(echo "$NGINX_RESTORE_VLIST" | tr "$dvsep" ' '); do
    _debug "ng_entry" "$ng_entry"
    _nd=$(echo "$ng_entry" | cut -d "$sep" -f 1)
    _ngconf=$(echo "$ng_entry" | cut -d "$sep" -f 2)
    _ngbackupconf=$(echo "$ng_entry" | cut -d "$sep" -f 3)
    _info "Restoring from $_ngbackupconf to $_ngconf"
    cat "$_ngbackupconf" >"$_ngconf"
  done

  _info "Reload nginx"
  if ! _exec "nginx -s reload" >/dev/null; then
    _exec_err
    _err "It seems that nginx reload error, please report bug."
    return 1
  fi
  return 0
}

_clearup() {
  _stopserver "$serverproc"
  serverproc=""
  _restoreApache
  _restoreNginx
  _clearupdns
  if [ -z "$DEBUG" ]; then
    rm -f "$TLS_CONF"
    rm -f "$TLS_CERT"
    rm -f "$TLS_KEY"
    rm -f "$TLS_CSR"
  fi
}

_clearupdns() {
  _debug "_clearupdns"
  _debug "dns_entries" "$dns_entries"

  if [ -z "$dns_entries" ]; then
    _debug "skip dns."
    return
  fi
  _info "Removing DNS records."

  for entry in $dns_entries; do
    d=$(_getfield "$entry" 1)
    txtdomain=$(_getfield "$entry" 2)
    aliasDomain=$(_getfield "$entry" 3)
    _currentRoot=$(_getfield "$entry" 4)
    txt=$(_getfield "$entry" 5)
    d_api=$(_getfield "$entry" 6)
    _debug "d" "$d"
    _debug "txtdomain" "$txtdomain"
    _debug "aliasDomain" "$aliasDomain"
    _debug "_currentRoot" "$_currentRoot"
    _debug "txt" "$txt"
    _debug "d_api" "$d_api"
    if [ "$d_api" = "$txt" ]; then
      d_api=""
    fi

    if [ -z "$d_api" ]; then
      _info "Not Found domain api file: $d_api"
      continue
    fi

    if [ "$aliasDomain" ]; then
      txtdomain="$aliasDomain"
    fi

    (
      if ! . "$d_api"; then
        _err "Load file $d_api error. Please check your api file and try again."
        return 1
      fi

      rmcommand="${_currentRoot}_rm"
      if ! _exists "$rmcommand"; then
        _err "It seems that your api file doesn't define $rmcommand"
        return 1
      fi
      _info "Removing txt: $txt for domain: $txtdomain"
      if ! $rmcommand "$txtdomain" "$txt"; then
        _err "Error removing txt for domain:$txtdomain"
        return 1
      fi
      _info "Removed: Success"
    )

  done
}

# webroot  removelevel tokenfile
_clearupwebbroot() {
  __webroot="$1"
  if [ -z "$__webroot" ]; then
    _debug "no webroot specified, skip"
    return 0
  fi

  _rmpath=""
  if [ "$2" = '1' ]; then
    _rmpath="$__webroot/.well-known"
  elif [ "$2" = '2' ]; then
    _rmpath="$__webroot/.well-known/acme-challenge"
  elif [ "$2" = '3' ]; then
    _rmpath="$__webroot/.well-known/acme-challenge/$3"
  else
    _debug "Skip for removelevel:$2"
  fi

  if [ "$_rmpath" ]; then
    if [ "$DEBUG" ]; then
      _debug "Debugging, skip removing: $_rmpath"
    else
      rm -rf "$_rmpath"
    fi
  fi

  return 0

}

_on_before_issue() {
  _chk_web_roots="$1"
  _chk_main_domain="$2"
  _chk_alt_domains="$3"
  _chk_pre_hook="$4"
  _chk_local_addr="$5"
  _debug _on_before_issue
  _debug _chk_main_domain "$_chk_main_domain"
  _debug _chk_alt_domains "$_chk_alt_domains"
  #run pre hook
  if [ "$_chk_pre_hook" ]; then
    _info "Run pre hook:'$_chk_pre_hook'"
    if ! (
      export Le_Domain="$_chk_main_domain"
      export Le_Alt="$_chk_alt_domains"
      cd "$DOMAIN_PATH" && eval "$_chk_pre_hook"
    ); then
      _err "Error when run pre hook."
      return 1
    fi
  fi

  if _hasfield "$_chk_web_roots" "$NO_VALUE"; then
    if ! _exists "socat"; then
      _err "Please install socat tools first."
      return 1
    fi
  fi

  _debug Le_LocalAddress "$_chk_local_addr"

  _index=1
  _currentRoot=""
  _addrIndex=1
  _w_index=1
  while true; do
    d="$(echo "$_chk_main_domain,$_chk_alt_domains," | cut -d , -f "$_w_index")"
    _w_index="$(_math "$_w_index" + 1)"
    _debug d "$d"
    if [ -z "$d" ]; then
      break
    fi
    _debug "Check for domain" "$d"
    _currentRoot="$(_getfield "$_chk_web_roots" $_index)"
    _debug "_currentRoot" "$_currentRoot"
    _index=$(_math $_index + 1)
    _checkport=""
    if [ "$_currentRoot" = "$NO_VALUE" ]; then
      _info "Standalone mode."
      if [ -z "$Le_HTTPPort" ]; then
        Le_HTTPPort=80
        _cleardomainconf "Le_HTTPPort"
      else
        _savedomainconf "Le_HTTPPort" "$Le_HTTPPort"
      fi
      _checkport="$Le_HTTPPort"
    elif [ "$_currentRoot" = "$W_ALPN" ]; then
      _info "Standalone alpn mode."
      if [ -z "$Le_TLSPort" ]; then
        Le_TLSPort=443
      else
        _savedomainconf "Le_TLSPort" "$Le_TLSPort"
      fi
      _checkport="$Le_TLSPort"
    fi

    if [ "$_checkport" ]; then
      _debug _checkport "$_checkport"
      _checkaddr="$(_getfield "$_chk_local_addr" $_addrIndex)"
      _debug _checkaddr "$_checkaddr"

      _addrIndex="$(_math $_addrIndex + 1)"

      _netprc="$(_ss "$_checkport" | grep "$_checkport")"
      netprc="$(echo "$_netprc" | grep "$_checkaddr")"
      if [ -z "$netprc" ]; then
        netprc="$(echo "$_netprc" | grep "$LOCAL_ANY_ADDRESS:$_checkport")"
      fi
      if [ "$netprc" ]; then
        _err "$netprc"
        _err "tcp port $_checkport is already used by $(echo "$netprc" | cut -d : -f 4)"
        _err "Please stop it first"
        return 1
      fi
    fi
  done

  if _hasfield "$_chk_web_roots" "apache"; then
    if ! _setApache; then
      _err "set up apache error. Report error to me."
      return 1
    fi
  else
    usingApache=""
  fi

}

_on_issue_err() {
  _chk_post_hook="$1"
  _chk_vlist="$2"
  _debug _on_issue_err

  if [ "$LOG_FILE" ]; then
    _err "Please check log file for more details: $LOG_FILE"
  else
    _err "Please add '--debug' or '--log' to check more details."
    _err "See: $_DEBUG_WIKI"
  fi

  #run the post hook
  if [ "$_chk_post_hook" ]; then
    _info "Run post hook:'$_chk_post_hook'"
    if ! (
      cd "$DOMAIN_PATH" && eval "$_chk_post_hook"
    ); then
      _err "Error when run post hook."
      return 1
    fi
  fi

  #trigger the validation to flush the pending authz
  _debug2 "_chk_vlist" "$_chk_vlist"
  if [ "$_chk_vlist" ]; then
    (
      _debug2 "start to deactivate authz"
      ventries=$(echo "$_chk_vlist" | tr "$dvsep" ' ')
      for ventry in $ventries; do
        d=$(echo "$ventry" | cut -d "$sep" -f 1)
        keyauthorization=$(echo "$ventry" | cut -d "$sep" -f 2)
        uri=$(echo "$ventry" | cut -d "$sep" -f 3)
        vtype=$(echo "$ventry" | cut -d "$sep" -f 4)
        _currentRoot=$(echo "$ventry" | cut -d "$sep" -f 5)
        __trigger_validation "$uri" "$keyauthorization"
      done
    )
  fi

  if [ "$_ACME_IS_RENEW" = "1" ] && _hasfield "$Le_Webroot" "$W_DNS"; then
    _err "$_DNS_MANUAL_ERR"
  fi

  if [ "$DEBUG" ] && [ "$DEBUG" -gt "0" ]; then
    _debug "$(_dlg_versions)"
  fi

}

_on_issue_success() {
  _chk_post_hook="$1"
  _chk_renew_hook="$2"
  _debug _on_issue_success

  #run the post hook
  if [ "$_chk_post_hook" ]; then
    _info "Run post hook:'$_chk_post_hook'"
    if ! (
      export CERT_PATH
      export CERT_KEY_PATH
      export CA_CERT_PATH
      export CERT_FULLCHAIN_PATH
      export Le_Domain="$_main_domain"
      cd "$DOMAIN_PATH" && eval "$_chk_post_hook"
    ); then
      _err "Error when run post hook."
      return 1
    fi
  fi

  #run renew hook
  if [ "$_ACME_IS_RENEW" ] && [ "$_chk_renew_hook" ]; then
    _info "Run renew hook:'$_chk_renew_hook'"
    if ! (
      export CERT_PATH
      export CERT_KEY_PATH
      export CA_CERT_PATH
      export CERT_FULLCHAIN_PATH
      export Le_Domain="$_main_domain"
      cd "$DOMAIN_PATH" && eval "$_chk_renew_hook"
    ); then
      _err "Error when run renew hook."
      return 1
    fi
  fi

  if _hasfield "$Le_Webroot" "$W_DNS" && [ -z "$FORCE_DNS_MANUAL" ]; then
    _err "$_DNS_MANUAL_WARN"
  fi

}

#account_key_length   eab-kid  eab-hmac-key
registeraccount() {
  _account_key_length="$1"
  _eab_id="$2"
  _eab_hmac_key="$3"
  _initpath
  _regAccount "$_account_key_length" "$_eab_id" "$_eab_hmac_key"
}

__calcAccountKeyHash() {
  [ -f "$ACCOUNT_KEY_PATH" ] && _digest sha256 <"$ACCOUNT_KEY_PATH"
}

__calc_account_thumbprint() {
  printf "%s" "$jwk" | tr -d ' ' | _digest "sha256" | _url_replace
}

_getAccountEmail() {
  if [ "$ACCOUNT_EMAIL" ]; then
    echo "$ACCOUNT_EMAIL"
    return 0
  fi
  if [ -z "$CA_EMAIL" ]; then
    CA_EMAIL="$(_readcaconf CA_EMAIL)"
  fi
  if [ "$CA_EMAIL" ]; then
    echo "$CA_EMAIL"
    return 0
  fi
  _readaccountconf "ACCOUNT_EMAIL"
}

#keylength
_regAccount() {
  _initpath
  _reg_length="$1"
  _eab_id="$2"
  _eab_hmac_key="$3"
  _debug3 _regAccount "$_regAccount"
  _initAPI

  mkdir -p "$CA_DIR"

  if [ ! -f "$ACCOUNT_KEY_PATH" ]; then
    if ! _create_account_key "$_reg_length"; then
      _err "Create account key error."
      return 1
    fi
  fi

  if ! _calcjwk "$ACCOUNT_KEY_PATH"; then
    return 1
  fi
  if [ "$_eab_id" ] && [ "$_eab_hmac_key" ]; then
    _savecaconf CA_EAB_KEY_ID "$_eab_id"
    _savecaconf CA_EAB_HMAC_KEY "$_eab_hmac_key"
  fi
  _eab_id=$(_readcaconf "CA_EAB_KEY_ID")
  _eab_hmac_key=$(_readcaconf "CA_EAB_HMAC_KEY")
  _secure_debug3 _eab_id "$_eab_id"
  _secure_debug3 _eab_hmac_key "$_eab_hmac_key"
  _email="$(_getAccountEmail)"
  if [ "$_email" ]; then
    _savecaconf "CA_EMAIL" "$_email"
  fi

  if [ "$ACME_DIRECTORY" = "$CA_ZEROSSL" ]; then
    if [ -z "$_eab_id" ] || [ -z "$_eab_hmac_key" ]; then
      _info "No EAB credentials found for ZeroSSL, let's get one"
      if [ -z "$_email" ]; then
        _info "$(__green "$PROJECT_NAME is using ZeroSSL as default CA now.")"
        _info "$(__green "Please update your account with an email address first.")"
        _info "$(__green "$PROJECT_ENTRY --register-account -m my@example.com")"
        _info "See: $(__green "$_ZEROSSL_WIKI")"
        return 1
      fi
      _eabresp=$(_post "email=$_email" $_ZERO_EAB_ENDPOINT)
      if [ "$?" != "0" ]; then
        _debug2 "$_eabresp"
        _err "Can not get EAB credentials from ZeroSSL."
        return 1
      fi
      _secure_debug2 _eabresp "$_eabresp"
      _eab_id="$(echo "$_eabresp" | tr ',}' '\n\n' | grep '"eab_kid"' | cut -d : -f 2 | tr -d '"')"
      _secure_debug2 _eab_id "$_eab_id"
      if [ -z "$_eab_id" ]; then
        _err "Can not resolve _eab_id"
        return 1
      fi
      _eab_hmac_key="$(echo "$_eabresp" | tr ',}' '\n\n' | grep '"eab_hmac_key"' | cut -d : -f 2 | tr -d '"')"
      _secure_debug2 _eab_hmac_key "$_eab_hmac_key"
      if [ -z "$_eab_hmac_key" ]; then
        _err "Can not resolve _eab_hmac_key"
        return 1
      fi
      _savecaconf CA_EAB_KEY_ID "$_eab_id"
      _savecaconf CA_EAB_HMAC_KEY "$_eab_hmac_key"
    fi
  fi
  if [ "$_eab_id" ] && [ "$_eab_hmac_key" ]; then
    eab_protected="{\"alg\":\"HS256\",\"kid\":\"$_eab_id\",\"url\":\"${ACME_NEW_ACCOUNT}\"}"
    _debug3 eab_protected "$eab_protected"

    eab_protected64=$(printf "%s" "$eab_protected" | _base64 | _url_replace)
    _debug3 eab_protected64 "$eab_protected64"

    eab_payload64=$(printf "%s" "$jwk" | _base64 | _url_replace)
    _debug3 eab_payload64 "$eab_payload64"

    eab_sign_t="$eab_protected64.$eab_payload64"
    _debug3 eab_sign_t "$eab_sign_t"

    key_hex="$(_durl_replace_base64 "$_eab_hmac_key" | _dbase64 multi | _hex_dump | tr -d ' ')"
    _debug3 key_hex "$key_hex"

    eab_signature=$(printf "%s" "$eab_sign_t" | _hmac sha256 $key_hex | _base64 | _url_replace)
    _debug3 eab_signature "$eab_signature"

    externalBinding=",\"externalAccountBinding\":{\"protected\":\"$eab_protected64\", \"payload\":\"$eab_payload64\", \"signature\":\"$eab_signature\"}"
    _debug3 externalBinding "$externalBinding"
  fi
  if [ "$_email" ]; then
    email_sg="\"contact\": [\"mailto:$_email\"], "
  fi
  regjson="{$email_sg\"termsOfServiceAgreed\": true$externalBinding}"

  _info "Registering account: $ACME_DIRECTORY"

  if ! _send_signed_request "${ACME_NEW_ACCOUNT}" "$regjson"; then
    _err "Register account Error: $response"
    return 1
  fi

  _eabAlreadyBound=""
  if [ "$code" = "" ] || [ "$code" = '201' ]; then
    echo "$response" >"$ACCOUNT_JSON_PATH"
    _info "Registered"
  elif [ "$code" = '409' ] || [ "$code" = '200' ]; then
    _info "Already registered"
  elif [ "$code" = '400' ] && _contains "$response" 'The account is not awaiting external account binding'; then
    _info "Already register EAB."
    _eabAlreadyBound=1
  else
    _err "Register account Error: $response"
    return 1
  fi

  if [ -z "$_eabAlreadyBound" ]; then
    _debug2 responseHeaders "$responseHeaders"
    _accUri="$(echo "$responseHeaders" | grep -i "^Location:" | _head_n 1 | cut -d ':' -f 2- | tr -d "\r\n ")"
    _debug "_accUri" "$_accUri"
    if [ -z "$_accUri" ]; then
      _err "Can not find account id url."
      _err "$responseHeaders"
      return 1
    fi
    _savecaconf "ACCOUNT_URL" "$_accUri"
  else
    ACCOUNT_URL="$(_readcaconf ACCOUNT_URL)"
  fi
  export ACCOUNT_URL="$_accUri"

  CA_KEY_HASH="$(__calcAccountKeyHash)"
  _debug "Calc CA_KEY_HASH" "$CA_KEY_HASH"
  _savecaconf CA_KEY_HASH "$CA_KEY_HASH"

  if [ "$code" = '403' ]; then
    _err "It seems that the account key is already deactivated, please use a new account key."
    return 1
  fi

  ACCOUNT_THUMBPRINT="$(__calc_account_thumbprint)"
  _info "ACCOUNT_THUMBPRINT" "$ACCOUNT_THUMBPRINT"
}

#implement updateaccount
updateaccount() {
  _initpath

  if [ ! -f "$ACCOUNT_KEY_PATH" ]; then
    _err "Account key is not found at: $ACCOUNT_KEY_PATH"
    return 1
  fi

  _accUri=$(_readcaconf "ACCOUNT_URL")
  _debug _accUri "$_accUri"

  if [ -z "$_accUri" ]; then
    _err "The account url is empty, please run '--update-account' first to update the account info first,"
    _err "Then try again."
    return 1
  fi

  if ! _calcjwk "$ACCOUNT_KEY_PATH"; then
    return 1
  fi
  _initAPI

  _email="$(_getAccountEmail)"

  if [ "$ACCOUNT_EMAIL" ]; then
    updjson='{"contact": ["mailto:'$_email'"]}'
  else
    updjson='{"contact": []}'
  fi

  _send_signed_request "$_accUri" "$updjson"

  if [ "$code" = '200' ]; then
    echo "$response" >"$ACCOUNT_JSON_PATH"
    _info "account update success for $_accUri."
  else
    _info "Error. The account was not updated."
    return 1
  fi
}

#Implement deactivate account
deactivateaccount() {
  _initpath

  if [ ! -f "$ACCOUNT_KEY_PATH" ]; then
    _err "Account key is not found at: $ACCOUNT_KEY_PATH"
    return 1
  fi

  _accUri=$(_readcaconf "ACCOUNT_URL")
  _debug _accUri "$_accUri"

  if [ -z "$_accUri" ]; then
    _err "The account url is empty, please run '--update-account' first to update the account info first,"
    _err "Then try again."
    return 1
  fi

  if ! _calcjwk "$ACCOUNT_KEY_PATH"; then
    return 1
  fi
  _initAPI

  _djson="{\"status\":\"deactivated\"}"

  if _send_signed_request "$_accUri" "$_djson" && _contains "$response" '"deactivated"'; then
    _info "Deactivate account success for $_accUri."
    _accid=$(echo "$response" | _egrep_o "\"id\" *: *[^,]*," | cut -d : -f 2 | tr -d ' ,')
  elif [ "$code" = "403" ]; then
    _info "The account is already deactivated."
    _accid=$(_getfield "$_accUri" "999" "/")
  else
    _err "Deactivate: account failed for $_accUri."
    return 1
  fi

  _debug "Account id: $_accid"
  if [ "$_accid" ]; then
    _deactivated_account_path="$CA_DIR/deactivated/$_accid"
    _debug _deactivated_account_path "$_deactivated_account_path"
    if mkdir -p "$_deactivated_account_path"; then
      _info "Moving deactivated account info to $_deactivated_account_path/"
      mv "$CA_CONF" "$_deactivated_account_path/"
      mv "$ACCOUNT_JSON_PATH" "$_deactivated_account_path/"
      mv "$ACCOUNT_KEY_PATH" "$_deactivated_account_path/"
    else
      _err "Can not create dir: $_deactivated_account_path, try to remove the deactivated account key."
      rm -f "$CA_CONF"
      rm -f "$ACCOUNT_JSON_PATH"
      rm -f "$ACCOUNT_KEY_PATH"
    fi
  fi
}

# domain folder  file
_findHook() {
  _hookdomain="$1"
  _hookcat="$2"
  _hookname="$3"

  if [ -f "$_SCRIPT_HOME/$_hookcat/$_hookname" ]; then
    d_api="$_SCRIPT_HOME/$_hookcat/$_hookname"
  elif [ -f "$_SCRIPT_HOME/$_hookcat/$_hookname.sh" ]; then
    d_api="$_SCRIPT_HOME/$_hookcat/$_hookname.sh"
  elif [ "$_hookdomain" ] && [ -f "$LE_WORKING_DIR/$_hookdomain/$_hookname" ]; then
    d_api="$LE_WORKING_DIR/$_hookdomain/$_hookname"
  elif [ "$_hookdomain" ] && [ -f "$LE_WORKING_DIR/$_hookdomain/$_hookname.sh" ]; then
    d_api="$LE_WORKING_DIR/$_hookdomain/$_hookname.sh"
  elif [ -f "$LE_WORKING_DIR/$_hookname" ]; then
    d_api="$LE_WORKING_DIR/$_hookname"
  elif [ -f "$LE_WORKING_DIR/$_hookname.sh" ]; then
    d_api="$LE_WORKING_DIR/$_hookname.sh"
  elif [ -f "$LE_WORKING_DIR/$_hookcat/$_hookname" ]; then
    d_api="$LE_WORKING_DIR/$_hookcat/$_hookname"
  elif [ -f "$LE_WORKING_DIR/$_hookcat/$_hookname.sh" ]; then
    d_api="$LE_WORKING_DIR/$_hookcat/$_hookname.sh"
  fi

  printf "%s" "$d_api"
}

#domain
__get_domain_new_authz() {
  _gdnd="$1"
  _info "Getting new-authz for domain" "$_gdnd"
  _initAPI
  _Max_new_authz_retry_times=5
  _authz_i=0
  while [ "$_authz_i" -lt "$_Max_new_authz_retry_times" ]; do
    _debug "Try new-authz for the $_authz_i time."
    if ! _send_signed_request "${ACME_NEW_AUTHZ}" "{\"resource\": \"new-authz\", \"identifier\": {\"type\": \"dns\", \"value\": \"$(_idn "$_gdnd")\"}}"; then
      _err "Can not get domain new authz."
      return 1
    fi
    if _contains "$response" "No registration exists matching provided key"; then
      _err "It seems there is an error, but it's recovered now, please try again."
      _err "If you see this message for a second time, please report bug: $(__green "$PROJECT")"
      _clearcaconf "CA_KEY_HASH"
      break
    fi
    if ! _contains "$response" "An error occurred while processing your request"; then
      _info "The new-authz request is ok."
      break
    fi
    _authz_i="$(_math "$_authz_i" + 1)"
    _info "The server is busy, Sleep $_authz_i to retry."
    _sleep "$_authz_i"
  done

  if [ "$_authz_i" = "$_Max_new_authz_retry_times" ]; then
    _err "new-authz retry reach the max $_Max_new_authz_retry_times times."
  fi

  if [ "$code" ] && [ "$code" != '201' ]; then
    _err "new-authz error: $response"
    return 1
  fi

}

#uri keyAuthorization
__trigger_validation() {
  _debug2 "Trigger domain validation."
  _t_url="$1"
  _debug2 _t_url "$_t_url"
  _t_key_authz="$2"
  _debug2 _t_key_authz "$_t_key_authz"
  _t_vtype="$3"
  _debug2 _t_vtype "$_t_vtype"

  _send_signed_request "$_t_url" "{}"

}

#endpoint  domain type
_ns_lookup_impl() {
  _ns_ep="$1"
  _ns_domain="$2"
  _ns_type="$3"
  _debug2 "_ns_ep" "$_ns_ep"
  _debug2 "_ns_domain" "$_ns_domain"
  _debug2 "_ns_type" "$_ns_type"

  response="$(_H1="accept: application/dns-json" _get "$_ns_ep?name=$_ns_domain&type=$_ns_type")"
  _ret=$?
  _debug2 "response" "$response"
  if [ "$_ret" != "0" ]; then
    return $_ret
  fi
  _answers="$(echo "$response" | tr '{}' '<>' | _egrep_o '"Answer":\[[^]]*]' | tr '<>' '\n\n')"
  _debug2 "_answers" "$_answers"
  echo "$_answers"
}

#domain, type
_ns_lookup_cf() {
  _cf_ld="$1"
  _cf_ld_type="$2"
  _cf_ep="https://cloudflare-dns.com/dns-query"
  _ns_lookup_impl "$_cf_ep" "$_cf_ld" "$_cf_ld_type"
}

#domain, type
_ns_purge_cf() {
  _cf_d="$1"
  _cf_d_type="$2"
  _debug "Cloudflare purge $_cf_d_type record for domain $_cf_d"
  _cf_purl="https://cloudflare-dns.com/api/v1/purge?domain=$_cf_d&type=$_cf_d_type"
  response="$(_post "" "$_cf_purl")"
  _debug2 response "$response"
}

#checks if cf server is available
_ns_is_available_cf() {
  if _get "https://cloudflare-dns.com" "" 1 >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

_ns_is_available_google() {
  if _get "https://dns.google" "" 1 >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

#domain, type
_ns_lookup_google() {
  _cf_ld="$1"
  _cf_ld_type="$2"
  _cf_ep="https://dns.google/resolve"
  _ns_lookup_impl "$_cf_ep" "$_cf_ld" "$_cf_ld_type"
}

_ns_is_available_ali() {
  if _get "https://dns.alidns.com" "" 1 >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

#domain, type
_ns_lookup_ali() {
  _cf_ld="$1"
  _cf_ld_type="$2"
  _cf_ep="https://dns.alidns.com/resolve"
  _ns_lookup_impl "$_cf_ep" "$_cf_ld" "$_cf_ld_type"
}

_ns_is_available_dp() {
  if _get "https://doh.pub" "" 1 >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

#dnspod
_ns_lookup_dp() {
  _cf_ld="$1"
  _cf_ld_type="$2"
  _cf_ep="https://doh.pub/dns-query"
  _ns_lookup_impl "$_cf_ep" "$_cf_ld" "$_cf_ld_type"
}

#domain, type
_ns_lookup() {
  if [ -z "$DOH_USE" ]; then
    _debug "Detect dns server first."
    if _ns_is_available_cf; then
      _debug "Use cloudflare doh server"
      export DOH_USE=$DOH_CLOUDFLARE
    elif _ns_is_available_google; then
      _debug "Use google doh server"
      export DOH_USE=$DOH_GOOGLE
    elif _ns_is_available_ali; then
      _debug "Use aliyun doh server"
      export DOH_USE=$DOH_ALI
    elif _ns_is_available_dp; then
      _debug "Use dns pod doh server"
      export DOH_USE=$DOH_DP
    else
      _err "No doh"
    fi
  fi

  if [ "$DOH_USE" = "$DOH_CLOUDFLARE" ] || [ -z "$DOH_USE" ]; then
    _ns_lookup_cf "$@"
  elif [ "$DOH_USE" = "$DOH_GOOGLE" ]; then
    _ns_lookup_google "$@"
  elif [ "$DOH_USE" = "$DOH_ALI" ]; then
    _ns_lookup_ali "$@"
  elif [ "$DOH_USE" = "$DOH_DP" ]; then
    _ns_lookup_dp "$@"
  else
    _err "Unknown doh provider: DOH_USE=$DOH_USE"
  fi

}

#txtdomain, alias, txt
__check_txt() {
  _c_txtdomain="$1"
  _c_aliasdomain="$2"
  _c_txt="$3"
  _debug "_c_txtdomain" "$_c_txtdomain"
  _debug "_c_aliasdomain" "$_c_aliasdomain"
  _debug "_c_txt" "$_c_txt"
  _answers="$(_ns_lookup "$_c_aliasdomain" TXT)"
  _contains "$_answers" "$_c_txt"

}

#txtdomain
__purge_txt() {
  _p_txtdomain="$1"
  _debug _p_txtdomain "$_p_txtdomain"
  if [ "$DOH_USE" = "$DOH_CLOUDFLARE" ] || [ -z "$DOH_USE" ]; then
    _ns_purge_cf "$_p_txtdomain" "TXT"
  else
    _debug "no purge api for this doh api, just sleep 5 secs"
    _sleep 5
  fi

}

#wait and check each dns entries
_check_dns_entries() {
  _success_txt=","
  _end_time="$(_time)"
  _end_time="$(_math "$_end_time" + 1200)" #let's check no more than 20 minutes.

  while [ "$(_time)" -le "$_end_time" ]; do
    _info "You can use '--dnssleep' to disable public dns checks."
    _info "See: $_DNSCHECK_WIKI"
    _left=""
    for entry in $dns_entries; do
      d=$(_getfield "$entry" 1)
      txtdomain=$(_getfield "$entry" 2)
      txtdomain=$(_idn "$txtdomain")
      aliasDomain=$(_getfield "$entry" 3)
      aliasDomain=$(_idn "$aliasDomain")
      txt=$(_getfield "$entry" 5)
      d_api=$(_getfield "$entry" 6)
      _debug "d" "$d"
      _debug "txtdomain" "$txtdomain"
      _debug "aliasDomain" "$aliasDomain"
      _debug "txt" "$txt"
      _debug "d_api" "$d_api"
      _info "Checking $d for $aliasDomain"
      if _contains "$_success_txt" ",$txt,"; then
        _info "Already success, continue next one."
        continue
      fi

      if __check_txt "$txtdomain" "$aliasDomain" "$txt"; then
        _info "Domain $d '$aliasDomain' success."
        _success_txt="$_success_txt,$txt,"
        continue
      fi
      _left=1
      _info "Not valid yet, let's wait 10 seconds and check next one."
      __purge_txt "$txtdomain"
      if [ "$txtdomain" != "$aliasDomain" ]; then
        __purge_txt "$aliasDomain"
      fi
      _sleep 10
    done
    if [ "$_left" ]; then
      _info "Let's wait 10 seconds and check again".
      _sleep 10
    else
      _info "All success, let's return"
      return 0
    fi
  done
  _info "Timed out waiting for DNS."
  return 1

}

#file
_get_chain_issuers() {
  _cfile="$1"
  if _contains "$(${ACME_OPENSSL_BIN:-openssl} help crl2pkcs7 2>&1)" "Usage: crl2pkcs7" || _contains "$(${ACME_OPENSSL_BIN:-openssl} crl2pkcs7 -help 2>&1)" "Usage: crl2pkcs7" || _contains "$(${ACME_OPENSSL_BIN:-openssl} crl2pkcs7 help 2>&1)" "unknown option help"; then
    ${ACME_OPENSSL_BIN:-openssl} crl2pkcs7 -nocrl -certfile $_cfile | ${ACME_OPENSSL_BIN:-openssl} pkcs7 -print_certs -text -noout | grep -i 'Issuer:' | _egrep_o "CN *=[^,]*" | cut -d = -f 2
  else
    _cindex=1
    for _startn in $(grep -n -- "$BEGIN_CERT" "$_cfile" | cut -d : -f 1); do
      _endn="$(grep -n -- "$END_CERT" "$_cfile" | cut -d : -f 1 | _head_n $_cindex | _tail_n 1)"
      _debug2 "_startn" "$_startn"
      _debug2 "_endn" "$_endn"
      if [ "$DEBUG" ]; then
        _debug2 "cert$_cindex" "$(sed -n "$_startn,${_endn}p" "$_cfile")"
      fi
      sed -n "$_startn,${_endn}p" "$_cfile" | ${ACME_OPENSSL_BIN:-openssl} x509 -text -noout | grep 'Issuer:' | _egrep_o "CN *=[^,]*" | cut -d = -f 2 | sed "s/ *\(.*\)/\1/"
      _cindex=$(_math $_cindex + 1)
    done
  fi
}

#
_get_chain_subjects() {
  _cfile="$1"
  if _contains "$(${ACME_OPENSSL_BIN:-openssl} help crl2pkcs7 2>&1)" "Usage: crl2pkcs7" || _contains "$(${ACME_OPENSSL_BIN:-openssl} crl2pkcs7 -help 2>&1)" "Usage: crl2pkcs7" || _contains "$(${ACME_OPENSSL_BIN:-openssl} crl2pkcs7 help 2>&1)" "unknown option help"; then
    ${ACME_OPENSSL_BIN:-openssl} crl2pkcs7 -nocrl -certfile $_cfile | ${ACME_OPENSSL_BIN:-openssl} pkcs7 -print_certs -text -noout | grep -i 'Subject:' | _egrep_o "CN *=[^,]*" | cut -d = -f 2
  else
    _cindex=1
    for _startn in $(grep -n -- "$BEGIN_CERT" "$_cfile" | cut -d : -f 1); do
      _endn="$(grep -n -- "$END_CERT" "$_cfile" | cut -d : -f 1 | _head_n $_cindex | _tail_n 1)"
      _debug2 "_startn" "$_startn"
      _debug2 "_endn" "$_endn"
      if [ "$DEBUG" ]; then
        _debug2 "cert$_cindex" "$(sed -n "$_startn,${_endn}p" "$_cfile")"
      fi
      sed -n "$_startn,${_endn}p" "$_cfile" | ${ACME_OPENSSL_BIN:-openssl} x509 -text -noout | grep -i 'Subject:' | _egrep_o "CN *=[^,]*" | cut -d = -f 2 | sed "s/ *\(.*\)/\1/"
      _cindex=$(_math $_cindex + 1)
    done
  fi
}

#cert  issuer
_match_issuer() {
  _cfile="$1"
  _missuer="$2"
  _fissuers="$(_get_chain_issuers $_cfile)"
  _debug2 _fissuers "$_fissuers"
  _rootissuer="$(echo "$_fissuers" | _lower_case | _tail_n 1)"
  _debug2 _rootissuer "$_rootissuer"
  _missuer="$(echo "$_missuer" | _lower_case)"
  _contains "$_rootissuer" "$_missuer"
}

#webroot, domain domainlist  keylength
issue() {
  if [ -z "$2" ]; then
    _usage "Usage: $PROJECT_ENTRY --issue --domain <domain.tld> --webroot <directory>"
    return 1
  fi
  if [ -z "$1" ]; then
    _usage "Please specify at least one validation method: '--webroot', '--standalone', '--apache', '--nginx' or '--dns' etc."
    return 1
  fi
  _web_roots="$1"
  _main_domain="$2"
  _alt_domains="$3"

  if _contains "$_main_domain" ","; then
    _main_domain=$(echo "$2,$3" | cut -d , -f 1)
    _alt_domains=$(echo "$2,$3" | cut -d , -f 2- | sed "s/,${NO_VALUE}$//")
  fi
  _debug _main_domain "$_main_domain"
  _debug _alt_domains "$_alt_domains"

  _key_length="$4"
  _real_cert="$5"
  _real_key="$6"
  _real_ca="$7"
  _reload_cmd="$8"
  _real_fullchain="$9"
  _pre_hook="${10}"
  _post_hook="${11}"
  _renew_hook="${12}"
  _local_addr="${13}"
  _challenge_alias="${14}"
  _preferred_chain="${15}"

  if [ -z "$_ACME_IS_RENEW" ]; then
    _initpath "$_main_domain" "$_key_length"
    mkdir -p "$DOMAIN_PATH"
  elif ! _hasfield "$_web_roots" "$W_DNS"; then
    Le_OrderFinalize=""
    Le_LinkOrder=""
    Le_LinkCert=""
  fi

  if _hasfield "$_web_roots" "$W_DNS" && [ -z "$FORCE_DNS_MANUAL" ]; then
    _err "$_DNS_MANUAL_ERROR"
    return 1
  fi

  _debug "Using ACME_DIRECTORY: $ACME_DIRECTORY"

  if ! _initAPI; then
    return 1
  fi

  if [ -f "$DOMAIN_CONF" ]; then
    Le_NextRenewTime=$(_readdomainconf Le_NextRenewTime)
    _debug Le_NextRenewTime "$Le_NextRenewTime"
    if [ -z "$FORCE" ] && [ "$Le_NextRenewTime" ] && [ "$(_time)" -lt "$Le_NextRenewTime" ]; then
      _saved_domain=$(_readdomainconf Le_Domain)
      _debug _saved_domain "$_saved_domain"
      _saved_alt=$(_readdomainconf Le_Alt)
      _debug _saved_alt "$_saved_alt"
      if [ "$_saved_domain,$_saved_alt" = "$_main_domain,$_alt_domains" ]; then
        _info "Domains not changed."
        _info "Skip, Next renewal time is: $(__green "$(_readdomainconf Le_NextRenewTimeStr)")"
        _info "Add '$(__red '--force')' to force to renew."
        return $RENEW_SKIP
      else
        _info "Domains have changed."
      fi
    fi
  fi

  _savedomainconf "Le_Domain" "$_main_domain"
  _savedomainconf "Le_Alt" "$_alt_domains"
  _savedomainconf "Le_Webroot" "$_web_roots"

  _savedomainconf "Le_PreHook" "$_pre_hook" "base64"
  _savedomainconf "Le_PostHook" "$_post_hook" "base64"
  _savedomainconf "Le_RenewHook" "$_renew_hook" "base64"

  if [ "$_local_addr" ]; then
    _savedomainconf "Le_LocalAddress" "$_local_addr"
  else
    _cleardomainconf "Le_LocalAddress"
  fi
  if [ "$_challenge_alias" ]; then
    _savedomainconf "Le_ChallengeAlias" "$_challenge_alias"
  else
    _cleardomainconf "Le_ChallengeAlias"
  fi
  if [ "$_preferred_chain" ]; then
    _savedomainconf "Le_Preferred_Chain" "$_preferred_chain" "base64"
  else
    _cleardomainconf "Le_Preferred_Chain"
  fi

  Le_API="$ACME_DIRECTORY"
  _savedomainconf "Le_API" "$Le_API"

  _info "Using CA: $ACME_DIRECTORY"
  if [ "$_alt_domains" = "$NO_VALUE" ]; then
    _alt_domains=""
  fi

  if [ "$_key_length" = "$NO_VALUE" ]; then
    _key_length=""
  fi

  if ! _on_before_issue "$_web_roots" "$_main_domain" "$_alt_domains" "$_pre_hook" "$_local_addr"; then
    _err "_on_before_issue."
    return 1
  fi

  _saved_account_key_hash="$(_readcaconf "CA_KEY_HASH")"
  _debug2 _saved_account_key_hash "$_saved_account_key_hash"

  if [ -z "$ACCOUNT_URL" ] || [ -z "$_saved_account_key_hash" ] || [ "$_saved_account_key_hash" != "$(__calcAccountKeyHash)" ]; then
    if ! _regAccount "$_accountkeylength"; then
      _on_issue_err "$_post_hook"
      return 1
    fi
  else
    _debug "_saved_account_key_hash is not changed, skip register account."
  fi

  if [ -f "$CSR_PATH" ] && [ ! -f "$CERT_KEY_PATH" ]; then
    _info "Signing from existing CSR."
  else
    _key=$(_readdomainconf Le_Keylength)
    _debug "Read key length:$_key"
    if [ ! -f "$CERT_KEY_PATH" ] || [ "$_key_length" != "$_key" ] || [ "$Le_ForceNewDomainKey" = "1" ]; then
      if ! createDomainKey "$_main_domain" "$_key_length"; then
        _err "Create domain key error."
        _clearup
        _on_issue_err "$_post_hook"
        return 1
      fi
    fi

    if ! _createcsr "$_main_domain" "$_alt_domains" "$CERT_KEY_PATH" "$CSR_PATH" "$DOMAIN_SSL_CONF"; then
      _err "Create CSR error."
      _clearup
      _on_issue_err "$_post_hook"
      return 1
    fi
  fi

  _savedomainconf "Le_Keylength" "$_key_length"

  vlist="$Le_Vlist"
  _cleardomainconf "Le_Vlist"
  _info "Getting domain auth token for each domain"
  sep='#'
  dvsep=','
  if [ -z "$vlist" ]; then
    #make new order request
    _identifiers="{\"type\":\"dns\",\"value\":\"$(_idn "$_main_domain")\"}"
    _w_index=1
    while true; do
      d="$(echo "$_alt_domains," | cut -d , -f "$_w_index")"
      _w_index="$(_math "$_w_index" + 1)"
      _debug d "$d"
      if [ -z "$d" ]; then
        break
      fi
      _identifiers="$_identifiers,{\"type\":\"dns\",\"value\":\"$(_idn "$d")\"}"
    done
    _debug2 _identifiers "$_identifiers"
    if ! _send_signed_request "$ACME_NEW_ORDER" "{\"identifiers\": [$_identifiers]}"; then
      _err "Create new order error."
      _clearup
      _on_issue_err "$_post_hook"
      return 1
    fi
    Le_LinkOrder="$(echo "$responseHeaders" | grep -i '^Location.*$' | _tail_n 1 | tr -d "\r\n " | cut -d ":" -f 2-)"
    _debug Le_LinkOrder "$Le_LinkOrder"
    Le_OrderFinalize="$(echo "$response" | _egrep_o '"finalize" *: *"[^"]*"' | cut -d '"' -f 4)"
    _debug Le_OrderFinalize "$Le_OrderFinalize"
    if [ -z "$Le_OrderFinalize" ]; then
      _err "Create new order error. Le_OrderFinalize not found. $response"
      _clearup
      _on_issue_err "$_post_hook"
      return 1
    fi

    #for dns manual mode
    _savedomainconf "Le_OrderFinalize" "$Le_OrderFinalize"

    _authorizations_seg="$(echo "$response" | _json_decode | _egrep_o '"authorizations" *: *\[[^\[]*\]' | cut -d '[' -f 2 | tr -d ']' | tr -d '"')"
    _debug2 _authorizations_seg "$_authorizations_seg"
    if [ -z "$_authorizations_seg" ]; then
      _err "_authorizations_seg not found."
      _clearup
      _on_issue_err "$_post_hook"
      return 1
    fi

    #domain and authz map
    _authorizations_map=""
    for _authz_url in $(echo "$_authorizations_seg" | tr ',' ' '); do
      _debug2 "_authz_url" "$_authz_url"
      if ! _send_signed_request "$_authz_url"; then
        _err "get to authz error."
        _err "_authorizations_seg" "$_authorizations_seg"
        _err "_authz_url" "$_authz_url"
        _clearup
        _on_issue_err "$_post_hook"
        return 1
      fi

      response="$(echo "$response" | _normalizeJson)"
      _debug2 response "$response"
      _d="$(echo "$response" | _egrep_o '"value" *: *"[^"]*"' | cut -d : -f 2 | tr -d ' "')"
      if _contains "$response" "\"wildcard\" *: *true"; then
        _d="*.$_d"
      fi
      _debug2 _d "$_d"
      _authorizations_map="$_d,$response
$_authorizations_map"
    done
    _debug2 _authorizations_map "$_authorizations_map"

    _index=0
    _currentRoot=""
    _w_index=1
    while true; do
      d="$(echo "$_main_domain,$_alt_domains," | cut -d , -f "$_w_index")"
      _w_index="$(_math "$_w_index" + 1)"
      _debug d "$d"
      if [ -z "$d" ]; then
        break
      fi
      _info "Getting webroot for domain" "$d"
      _index=$(_math $_index + 1)
      _w="$(echo $_web_roots | cut -d , -f $_index)"
      _debug _w "$_w"
      if [ "$_w" ]; then
        _currentRoot="$_w"
      fi
      _debug "_currentRoot" "$_currentRoot"

      vtype="$VTYPE_HTTP"
      #todo, v2 wildcard force to use dns
      if _startswith "$_currentRoot" "$W_DNS"; then
        vtype="$VTYPE_DNS"
      fi

      if [ "$_currentRoot" = "$W_ALPN" ]; then
        vtype="$VTYPE_ALPN"
      fi

      _idn_d="$(_idn "$d")"
      _candidates="$(echo "$_authorizations_map" | grep -i "^$_idn_d,")"
      _debug2 _candidates "$_candidates"
      if [ "$(echo "$_candidates" | wc -l)" -gt 1 ]; then
        for _can in $_candidates; do
          if _startswith "$(echo "$_can" | tr '.' '|')" "$(echo "$_idn_d" | tr '.' '|'),"; then
            _candidates="$_can"
            break
          fi
        done
      fi
      response="$(echo "$_candidates" | sed "s/$_idn_d,//")"
      _debug2 "response" "$response"
      if [ -z "$response" ]; then
        _err "get to authz error."
        _err "_authorizations_map" "$_authorizations_map"
        _clearup
        _on_issue_err "$_post_hook"
        return 1
      fi

      if [ -z "$thumbprint" ]; then
        thumbprint="$(__calc_account_thumbprint)"
      fi

      entry="$(echo "$response" | _egrep_o '[^\{]*"type":"'$vtype'"[^\}]*')"
      _debug entry "$entry"
      keyauthorization=""
      if [ -z "$entry" ]; then
        if ! _startswith "$d" '*.'; then
          _debug "Not a wildcard domain, lets check whether the validation is already valid."
          if echo "$response" | grep '"status":"valid"' >/dev/null 2>&1; then
            _debug "$d is already valid."
            keyauthorization="$STATE_VERIFIED"
            _debug keyauthorization "$keyauthorization"
          fi
        fi
        if [ -z "$keyauthorization" ]; then
          _err "Error, can not get domain token entry $d for $vtype"
          _supported_vtypes="$(echo "$response" | _egrep_o "\"challenges\":\[[^]]*]" | tr '{' "\n" | grep type | cut -d '"' -f 4 | tr "\n" ' ')"
          if [ "$_supported_vtypes" ]; then
            _err "The supported validation types are: $_supported_vtypes, but you specified: $vtype"
          fi
          _clearup
          _on_issue_err "$_post_hook"
          return 1
        fi
      fi

      if [ -z "$keyauthorization" ]; then
        token="$(echo "$entry" | _egrep_o '"token":"[^"]*' | cut -d : -f 2 | tr -d '"')"
        _debug token "$token"

        if [ -z "$token" ]; then
          _err "Error, can not get domain token $entry"
          _clearup
          _on_issue_err "$_post_hook"
          return 1
        fi

        uri="$(echo "$entry" | _egrep_o '"url":"[^"]*' | cut -d '"' -f 4 | _head_n 1)"

        _debug uri "$uri"

        if [ -z "$uri" ]; then
          _err "Error, can not get domain uri. $entry"
          _clearup
          _on_issue_err "$_post_hook"
          return 1
        fi
        keyauthorization="$token.$thumbprint"
        _debug keyauthorization "$keyauthorization"

        if printf "%s" "$response" | grep '"status":"valid"' >/dev/null 2>&1; then
          _debug "$d is already verified."
          keyauthorization="$STATE_VERIFIED"
          _debug keyauthorization "$keyauthorization"
        fi
      fi

      dvlist="$d$sep$keyauthorization$sep$uri$sep$vtype$sep$_currentRoot"
      _debug dvlist "$dvlist"

      vlist="$vlist$dvlist$dvsep"

    done
    _debug vlist "$vlist"
    #add entry
    dns_entries=""
    dnsadded=""
    ventries=$(echo "$vlist" | tr "$dvsep" ' ')
    _alias_index=1
    for ventry in $ventries; do
      d=$(echo "$ventry" | cut -d "$sep" -f 1)
      keyauthorization=$(echo "$ventry" | cut -d "$sep" -f 2)
      vtype=$(echo "$ventry" | cut -d "$sep" -f 4)
      _currentRoot=$(echo "$ventry" | cut -d "$sep" -f 5)
      _debug d "$d"
      if [ "$keyauthorization" = "$STATE_VERIFIED" ]; then
        _debug "$d is already verified, skip $vtype."
        _alias_index="$(_math "$_alias_index" + 1)"
        continue
      fi

      if [ "$vtype" = "$VTYPE_DNS" ]; then
        dnsadded='0'
        _dns_root_d="$d"
        if _startswith "$_dns_root_d" "*."; then
          _dns_root_d="$(echo "$_dns_root_d" | sed 's/*.//')"
        fi
        _d_alias="$(_getfield "$_challenge_alias" "$_alias_index")"
        _alias_index="$(_math "$_alias_index" + 1)"
        _debug "_d_alias" "$_d_alias"
        if [ "$_d_alias" ]; then
          if _startswith "$_d_alias" "$DNS_ALIAS_PREFIX"; then
            txtdomain="$(echo "$_d_alias" | sed "s/$DNS_ALIAS_PREFIX//")"
          else
            txtdomain="_acme-challenge.$_d_alias"
          fi
          dns_entry="${_dns_root_d}${dvsep}_acme-challenge.$_dns_root_d$dvsep$txtdomain$dvsep$_currentRoot"
        else
          txtdomain="_acme-challenge.$_dns_root_d"
          dns_entry="${_dns_root_d}${dvsep}_acme-challenge.$_dns_root_d$dvsep$dvsep$_currentRoot"
        fi

        _debug txtdomain "$txtdomain"
        txt="$(printf "%s" "$keyauthorization" | _digest "sha256" | _url_replace)"
        _debug txt "$txt"

        d_api="$(_findHook "$_dns_root_d" $_SUB_FOLDER_DNSAPI "$_currentRoot")"
        _debug d_api "$d_api"

        dns_entry="$dns_entry$dvsep$txt${dvsep}$d_api"
        _debug2 dns_entry "$dns_entry"
        if [ "$d_api" ]; then
          _debug "Found domain api file: $d_api"
        else
          if [ "$_currentRoot" != "$W_DNS" ]; then
            _err "Can not find dns api hook for: $_currentRoot"
            _info "You need to add the txt record manually."
          fi
          _info "$(__red "Add the following TXT record:")"
          _info "$(__red "Domain: '$(__green "$txtdomain")'")"
          _info "$(__red "TXT value: '$(__green "$txt")'")"
          _info "$(__red "Please be aware that you prepend _acme-challenge. before your domain")"
          _info "$(__red "so the resulting subdomain will be: $txtdomain")"
          continue
        fi

        (
          if ! . "$d_api"; then
            _err "Load file $d_api error. Please check your api file and try again."
            return 1
          fi

          addcommand="${_currentRoot}_add"
          if ! _exists "$addcommand"; then
            _err "It seems that your api file is not correct, it must have a function named: $addcommand"
            return 1
          fi
          _info "Adding txt value: $txt for domain:  $txtdomain"
          if ! $addcommand "$txtdomain" "$txt"; then
            _err "Error add txt for domain:$txtdomain"
            return 1
          fi
          _info "The txt record is added: Success."
        )

        if [ "$?" != "0" ]; then
          _on_issue_err "$_post_hook" "$vlist"
          _clearup
          return 1
        fi
        dns_entries="$dns_entries$dns_entry
"
        _debug2 "$dns_entries"
        dnsadded='1'
      fi
    done

    if [ "$dnsadded" = '0' ]; then
      _savedomainconf "Le_Vlist" "$vlist"
      _debug "Dns record not added yet, so, save to $DOMAIN_CONF and exit."
      _err "Please add the TXT records to the domains, and re-run with --renew."
      _on_issue_err "$_post_hook"
      _clearup
      return 1
    fi

  fi

  if [ "$dns_entries" ]; then
    if [ -z "$Le_DNSSleep" ]; then
      _info "Let's check each DNS record now. Sleep 20 seconds first."
      _sleep 20
      if ! _check_dns_entries; then
        _err "check dns error."
        _on_issue_err "$_post_hook"
        _clearup
        return 1
      fi
    else
      _savedomainconf "Le_DNSSleep" "$Le_DNSSleep"
      _info "Sleep $(__green $Le_DNSSleep) seconds for the txt records to take effect"
      _sleep "$Le_DNSSleep"
    fi
  fi

  NGINX_RESTORE_VLIST=""
  _debug "ok, let's start to verify"

  _ncIndex=1
  ventries=$(echo "$vlist" | tr "$dvsep" ' ')
  for ventry in $ventries; do
    d=$(echo "$ventry" | cut -d "$sep" -f 1)
    keyauthorization=$(echo "$ventry" | cut -d "$sep" -f 2)
    uri=$(echo "$ventry" | cut -d "$sep" -f 3)
    vtype=$(echo "$ventry" | cut -d "$sep" -f 4)
    _currentRoot=$(echo "$ventry" | cut -d "$sep" -f 5)

    if [ "$keyauthorization" = "$STATE_VERIFIED" ]; then
      _info "$d is already verified, skip $vtype."
      continue
    fi

    _info "Verifying: $d"
    _debug "d" "$d"
    _debug "keyauthorization" "$keyauthorization"
    _debug "uri" "$uri"
    removelevel=""
    token="$(printf "%s" "$keyauthorization" | cut -d '.' -f 1)"

    _debug "_currentRoot" "$_currentRoot"

    if [ "$vtype" = "$VTYPE_HTTP" ]; then
      if [ "$_currentRoot" = "$NO_VALUE" ]; then
        _info "Standalone mode server"
        _ncaddr="$(_getfield "$_local_addr" "$_ncIndex")"
        _ncIndex="$(_math $_ncIndex + 1)"
        _startserver "$keyauthorization" "$_ncaddr"
        if [ "$?" != "0" ]; then
          _clearup
          _on_issue_err "$_post_hook" "$vlist"
          return 1
        fi
        sleep 1
        _debug serverproc "$serverproc"
      elif [ "$_currentRoot" = "$MODE_STATELESS" ]; then
        _info "Stateless mode for domain:$d"
        _sleep 1
      elif _startswith "$_currentRoot" "$NGINX"; then
        _info "Nginx mode for domain:$d"
        #set up nginx server
        FOUND_REAL_NGINX_CONF=""
        BACKUP_NGINX_CONF=""
        if ! _setNginx "$d" "$_currentRoot" "$thumbprint"; then
          _clearup
          _on_issue_err "$_post_hook" "$vlist"
          return 1
        fi

        if [ "$FOUND_REAL_NGINX_CONF" ]; then
          _realConf="$FOUND_REAL_NGINX_CONF"
          _backup="$BACKUP_NGINX_CONF"
          _debug _realConf "$_realConf"
          NGINX_RESTORE_VLIST="$d$sep$_realConf$sep$_backup$dvsep$NGINX_RESTORE_VLIST"
        fi
        _sleep 1
      else
        if [ "$_currentRoot" = "apache" ]; then
          wellknown_path="$ACME_DIR"
        else
          wellknown_path="$_currentRoot/.well-known/acme-challenge"
          if [ ! -d "$_currentRoot/.well-known" ]; then
            removelevel='1'
          elif [ ! -d "$_currentRoot/.well-known/acme-challenge" ]; then
            removelevel='2'
          else
            removelevel='3'
          fi
        fi

        _debug wellknown_path "$wellknown_path"

        _debug "writing token:$token to $wellknown_path/$token"

        mkdir -p "$wellknown_path"

        if ! printf "%s" "$keyauthorization" >"$wellknown_path/$token"; then
          _err "$d:Can not write token to file : $wellknown_path/$token"
          _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
          _clearup
          _on_issue_err "$_post_hook" "$vlist"
          return 1
        fi

        if [ ! "$usingApache" ]; then
          if webroot_owner=$(_stat "$_currentRoot"); then
            _debug "Changing owner/group of .well-known to $webroot_owner"
            if ! _exec "chown -R \"$webroot_owner\" \"$_currentRoot/.well-known\""; then
              _debug "$(cat "$_EXEC_TEMP_ERR")"
              _exec_err >/dev/null 2>&1
            fi
          else
            _debug "not changing owner/group of webroot"
          fi
        fi

      fi
    elif [ "$vtype" = "$VTYPE_ALPN" ]; then
      acmevalidationv1="$(printf "%s" "$keyauthorization" | _digest "sha256" "hex")"
      _debug acmevalidationv1 "$acmevalidationv1"
      if ! _starttlsserver "$d" "" "$Le_TLSPort" "$keyauthorization" "$_ncaddr" "$acmevalidationv1"; then
        _err "Start tls server error."
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        _on_issue_err "$_post_hook" "$vlist"
        return 1
      fi
    fi

    if ! __trigger_validation "$uri" "$keyauthorization" "$vtype"; then
      _err "$d:Can not get challenge: $response"
      _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
      _clearup
      _on_issue_err "$_post_hook" "$vlist"
      return 1
    fi

    if [ "$code" ] && [ "$code" != '202' ]; then
      if [ "$code" = '200' ]; then
        _debug "trigger validation code: $code"
      else
        _err "$d:Challenge error: $response"
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        _on_issue_err "$_post_hook" "$vlist"
        return 1
      fi
    fi

    waittimes=0
    if [ -z "$MAX_RETRY_TIMES" ]; then
      MAX_RETRY_TIMES=30
    fi

    while true; do
      waittimes=$(_math "$waittimes" + 1)
      if [ "$waittimes" -ge "$MAX_RETRY_TIMES" ]; then
        _err "$d:Timeout"
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        _on_issue_err "$_post_hook" "$vlist"
        return 1
      fi

      _debug2 original "$response"

      response="$(echo "$response" | _normalizeJson)"
      _debug2 response "$response"

      status=$(echo "$response" | _egrep_o '"status":"[^"]*' | cut -d : -f 2 | tr -d '"')
      _debug2 status "$status"
      if _contains "$status" "invalid"; then
        error="$(echo "$response" | _egrep_o '"error":\{[^\}]*')"
        _debug2 error "$error"
        errordetail="$(echo "$error" | _egrep_o '"detail": *"[^"]*' | cut -d '"' -f 4)"
        _debug2 errordetail "$errordetail"
        if [ "$errordetail" ]; then
          _err "$d:Verify error:$errordetail"
        else
          _err "$d:Verify error:$error"
        fi
        if [ "$DEBUG" ]; then
          if [ "$vtype" = "$VTYPE_HTTP" ]; then
            _debug "Debug: get token url."
            _get "http://$d/.well-known/acme-challenge/$token" "" 1
          fi
        fi
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        _on_issue_err "$_post_hook" "$vlist"
        return 1
      fi

      if _contains "$status" "valid"; then
        _info "$(__green Success)"
        _stopserver "$serverproc"
        serverproc=""
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        break
      fi

      if [ "$status" = "pending" ]; then
        _info "Pending, The CA is processing your order, please just wait. ($waittimes/$MAX_RETRY_TIMES)"
      elif [ "$status" = "processing" ]; then
        _info "Processing, The CA is processing your order, please just wait. ($waittimes/$MAX_RETRY_TIMES)"
      else
        _err "$d:Verify error:$response"
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        _on_issue_err "$_post_hook" "$vlist"
        return 1
      fi
      _debug "sleep 2 secs to verify again"
      sleep 2
      _debug "checking"

      _send_signed_request "$uri"

      if [ "$?" != "0" ]; then
        _err "$d:Verify error:$response"
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        _on_issue_err "$_post_hook" "$vlist"
        return 1
      fi
    done

  done

  _clearup
  _info "Verify finished, start to sign."
  der="$(_getfile "${CSR_PATH}" "${BEGIN_CSR}" "${END_CSR}" | tr -d "\r\n" | _url_replace)"

  _info "Lets finalize the order."
  _info "Le_OrderFinalize" "$Le_OrderFinalize"
  if ! _send_signed_request "${Le_OrderFinalize}" "{\"csr\": \"$der\"}"; then
    _err "Sign failed."
    _on_issue_err "$_post_hook"
    return 1
  fi
  if [ "$code" != "200" ]; then
    _err "Sign failed, finalize code is not 200."
    _err "$response"
    _on_issue_err "$_post_hook"
    return 1
  fi
  if [ -z "$Le_LinkOrder" ]; then
    Le_LinkOrder="$(echo "$responseHeaders" | grep -i '^Location.*$' | _tail_n 1 | tr -d "\r\n \t" | cut -d ":" -f 2-)"
  fi

  _savedomainconf "Le_LinkOrder" "$Le_LinkOrder"

  _link_cert_retry=0
  _MAX_CERT_RETRY=30
  while [ "$_link_cert_retry" -lt "$_MAX_CERT_RETRY" ]; do
    if _contains "$response" "\"status\":\"valid\""; then
      _debug "Order status is valid."
      Le_LinkCert="$(echo "$response" | _egrep_o '"certificate" *: *"[^"]*"' | cut -d '"' -f 4)"
      _debug Le_LinkCert "$Le_LinkCert"
      if [ -z "$Le_LinkCert" ]; then
        _err "Sign error, can not find Le_LinkCert"
        _err "$response"
        _on_issue_err "$_post_hook"
        return 1
      fi
      break
    elif _contains "$response" "\"processing\""; then
      _info "Order status is processing, lets sleep and retry."
      _retryafter=$(echo "$responseHeaders" | grep -i "^Retry-After *:" | cut -d : -f 2 | tr -d ' ' | tr -d '\r')
      _debug "_retryafter" "$_retryafter"
      if [ "$_retryafter" ]; then
        _info "Retry after: $_retryafter"
        _sleep $_retryafter
      else
        _sleep 2
      fi
    else
      _err "Sign error, wrong status"
      _err "$response"
      _on_issue_err "$_post_hook"
      return 1
    fi
    #the order is processing, so we are going to poll order status
    if [ -z "$Le_LinkOrder" ]; then
      _err "Sign error, can not get order link location header"
      _err "responseHeaders" "$responseHeaders"
      _on_issue_err "$_post_hook"
      return 1
    fi
    _info "Polling order status: $Le_LinkOrder"
    if ! _send_signed_request "$Le_LinkOrder"; then
      _err "Sign failed, can not post to Le_LinkOrder cert:$Le_LinkOrder."
      _err "$response"
      _on_issue_err "$_post_hook"
      return 1
    fi
    _link_cert_retry="$(_math $_link_cert_retry + 1)"
  done

  if [ -z "$Le_LinkCert" ]; then
    _err "Sign failed, can not get Le_LinkCert, retry time limit."
    _err "$response"
    _on_issue_err "$_post_hook"
    return 1
  fi
  _info "Downloading cert."
  _info "Le_LinkCert" "$Le_LinkCert"
  if ! _send_signed_request "$Le_LinkCert"; then
    _err "Sign failed, can not download cert:$Le_LinkCert."
    _err "$response"
    _on_issue_err "$_post_hook"
    return 1
  fi

  echo "$response" >"$CERT_PATH"
  _split_cert_chain "$CERT_PATH" "$CERT_FULLCHAIN_PATH" "$CA_CERT_PATH"

  if [ "$_preferred_chain" ] && [ -f "$CERT_FULLCHAIN_PATH" ]; then
    if [ "$DEBUG" ]; then
      _debug "default chain issuers: " "$(_get_chain_issuers "$CERT_FULLCHAIN_PATH")"
    fi
    if ! _match_issuer "$CERT_FULLCHAIN_PATH" "$_preferred_chain"; then
      rels="$(echo "$responseHeaders" | tr -d ' <>' | grep -i "^link:" | grep -i 'rel="alternate"' | cut -d : -f 2- | cut -d ';' -f 1)"
      _debug2 "rels" "$rels"
      for rel in $rels; do
        _info "Try rel: $rel"
        if ! _send_signed_request "$rel"; then
          _err "Sign failed, can not download cert:$rel"
          _err "$response"
          continue
        fi
        _relcert="$CERT_PATH.alt"
        _relfullchain="$CERT_FULLCHAIN_PATH.alt"
        _relca="$CA_CERT_PATH.alt"
        echo "$response" >"$_relcert"
        _split_cert_chain "$_relcert" "$_relfullchain" "$_relca"
        if [ "$DEBUG" ]; then
          _debug "rel chain issuers: " "$(_get_chain_issuers "$_relfullchain")"
        fi
        if _match_issuer "$_relfullchain" "$_preferred_chain"; then
          _info "Matched issuer in: $rel"
          cat $_relcert >"$CERT_PATH"
          cat $_relfullchain >"$CERT_FULLCHAIN_PATH"
          cat $_relca >"$CA_CERT_PATH"
          rm -f "$_relcert"
          rm -f "$_relfullchain"
          rm -f "$_relca"
          break
        fi
        rm -f "$_relcert"
        rm -f "$_relfullchain"
        rm -f "$_relca"
      done
    fi
  fi

  _debug "Le_LinkCert" "$Le_LinkCert"
  _savedomainconf "Le_LinkCert" "$Le_LinkCert"

  if [ -z "$Le_LinkCert" ] || ! _checkcert "$CERT_PATH"; then
    response="$(echo "$response" | _dbase64 "multiline" | tr -d '\0' | _normalizeJson)"
    _err "Sign failed: $(echo "$response" | _egrep_o '"detail":"[^"]*"')"
    _on_issue_err "$_post_hook"
    return 1
  fi

  if [ "$Le_LinkCert" ]; then
    _info "$(__green "Cert success.")"
    cat "$CERT_PATH"

    _info "Your cert is in: $(__green "$CERT_PATH")"

    if [ -f "$CERT_KEY_PATH" ]; then
      _info "Your cert key is in: $(__green "$CERT_KEY_PATH")"
    fi

    if [ ! "$USER_PATH" ] || [ ! "$_ACME_IN_CRON" ]; then
      USER_PATH="$PATH"
      _saveaccountconf "USER_PATH" "$USER_PATH"
    fi
  fi

  [ -f "$CA_CERT_PATH" ] && _info "The intermediate CA cert is in: $(__green "$CA_CERT_PATH")"
  [ -f "$CERT_FULLCHAIN_PATH" ] && _info "And the full chain certs is there: $(__green "$CERT_FULLCHAIN_PATH")"

  Le_CertCreateTime=$(_time)
  _savedomainconf "Le_CertCreateTime" "$Le_CertCreateTime"

  Le_CertCreateTimeStr=$(date -u)
  _savedomainconf "Le_CertCreateTimeStr" "$Le_CertCreateTimeStr"

  if [ -z "$Le_RenewalDays" ] || [ "$Le_RenewalDays" -lt "0" ]; then
    Le_RenewalDays="$DEFAULT_RENEW"
  else
    _savedomainconf "Le_RenewalDays" "$Le_RenewalDays"
  fi

  if [ "$CA_BUNDLE" ]; then
    _saveaccountconf CA_BUNDLE "$CA_BUNDLE"
  else
    _clearaccountconf "CA_BUNDLE"
  fi

  if [ "$CA_PATH" ]; then
    _saveaccountconf CA_PATH "$CA_PATH"
  else
    _clearaccountconf "CA_PATH"
  fi

  if [ "$HTTPS_INSECURE" ]; then
    _saveaccountconf HTTPS_INSECURE "$HTTPS_INSECURE"
  else
    _clearaccountconf "HTTPS_INSECURE"
  fi

  if [ "$Le_Listen_V4" ]; then
    _savedomainconf "Le_Listen_V4" "$Le_Listen_V4"
    _cleardomainconf Le_Listen_V6
  elif [ "$Le_Listen_V6" ]; then
    _savedomainconf "Le_Listen_V6" "$Le_Listen_V6"
    _cleardomainconf Le_Listen_V4
  fi

  if [ "$Le_ForceNewDomainKey" = "1" ]; then
    _savedomainconf "Le_ForceNewDomainKey" "$Le_ForceNewDomainKey"
  else
    _cleardomainconf Le_ForceNewDomainKey
  fi

  Le_NextRenewTime=$(_math "$Le_CertCreateTime" + "$Le_RenewalDays" \* 24 \* 60 \* 60)

  Le_NextRenewTimeStr=$(_time2str "$Le_NextRenewTime")
  _savedomainconf "Le_NextRenewTimeStr" "$Le_NextRenewTimeStr"

  Le_NextRenewTime=$(_math "$Le_NextRenewTime" - 86400)
  _savedomainconf "Le_NextRenewTime" "$Le_NextRenewTime"

  if [ "$_real_cert$_real_key$_real_ca$_reload_cmd$_real_fullchain" ]; then
    _savedomainconf "Le_RealCertPath" "$_real_cert"
    _savedomainconf "Le_RealCACertPath" "$_real_ca"
    _savedomainconf "Le_RealKeyPath" "$_real_key"
    _savedomainconf "Le_ReloadCmd" "$_reload_cmd" "base64"
    _savedomainconf "Le_RealFullChainPath" "$_real_fullchain"
    if ! _installcert "$_main_domain" "$_real_cert" "$_real_key" "$_real_ca" "$_real_fullchain" "$_reload_cmd"; then
      return 1
    fi
  fi

  if ! _on_issue_success "$_post_hook" "$_renew_hook"; then
    _err "Call hook error."
    return 1
  fi
}

#in_out_cert   out_fullchain   out_ca
_split_cert_chain() {
  _certf="$1"
  _fullchainf="$2"
  _caf="$3"
  if [ "$(grep -- "$BEGIN_CERT" "$_certf" | wc -l)" -gt "1" ]; then
    _debug "Found cert chain"
    cat "$_certf" >"$_fullchainf"
    _end_n="$(grep -n -- "$END_CERT" "$_fullchainf" | _head_n 1 | cut -d : -f 1)"
    _debug _end_n "$_end_n"
    sed -n "1,${_end_n}p" "$_fullchainf" >"$_certf"
    _end_n="$(_math $_end_n + 1)"
    sed -n "${_end_n},9999p" "$_fullchainf" >"$_caf"
  fi
}

#domain  [isEcc]
renew() {
  Le_Domain="$1"
  if [ -z "$Le_Domain" ]; then
    _usage "Usage: $PROJECT_ENTRY --renew --domain <domain.tld> [--ecc]"
    return 1
  fi

  _isEcc="$2"

  _initpath "$Le_Domain" "$_isEcc"

  _info "$(__green "Renew: '$Le_Domain'")"
  if [ ! -f "$DOMAIN_CONF" ]; then
    _info "'$Le_Domain' is not an issued domain, skip."
    return $RENEW_SKIP
  fi

  if [ "$Le_RenewalDays" ]; then
    _savedomainconf Le_RenewalDays "$Le_RenewalDays"
  fi

  . "$DOMAIN_CONF"
  _debug Le_API "$Le_API"
  if [ -z "$Le_API" ] || [ "$CA_LETSENCRYPT_V1" = "$Le_API" ]; then
    #if this is from an old version, Le_API is empty,
    #so, we force to use letsencrypt server
    Le_API="$CA_LETSENCRYPT_V2"
  fi

  if [ "$Le_API" ]; then
    if [ "$Le_API" != "$ACME_DIRECTORY" ]; then
      _clearAPI
    fi
    export ACME_DIRECTORY="$Le_API"
    #reload ca configs
    ACCOUNT_KEY_PATH=""
    ACCOUNT_JSON_PATH=""
    CA_CONF=""
    _debug3 "initpath again."
    _initpath "$Le_Domain" "$_isEcc"
    _initAPI
  fi

  if [ -z "$FORCE" ] && [ "$Le_NextRenewTime" ] && [ "$(_time)" -lt "$Le_NextRenewTime" ]; then
    _info "Skip, Next renewal time is: $(__green "$Le_NextRenewTimeStr")"
    _info "Add '$(__red '--force')' to force to renew."
    return "$RENEW_SKIP"
  fi

  if [ "$_ACME_IN_CRON" = "1" ] && [ -z "$Le_CertCreateTime" ]; then
    _info "Skip invalid cert for: $Le_Domain"
    return $RENEW_SKIP
  fi

  _ACME_IS_RENEW="1"
  Le_ReloadCmd="$(_readdomainconf Le_ReloadCmd)"
  Le_PreHook="$(_readdomainconf Le_PreHook)"
  Le_PostHook="$(_readdomainconf Le_PostHook)"
  Le_RenewHook="$(_readdomainconf Le_RenewHook)"
  Le_Preferred_Chain="$(_readdomainconf Le_Preferred_Chain)"
  issue "$Le_Webroot" "$Le_Domain" "$Le_Alt" "$Le_Keylength" "$Le_RealCertPath" "$Le_RealKeyPath" "$Le_RealCACertPath" "$Le_ReloadCmd" "$Le_RealFullChainPath" "$Le_PreHook" "$Le_PostHook" "$Le_RenewHook" "$Le_LocalAddress" "$Le_ChallengeAlias" "$Le_Preferred_Chain"
  res="$?"
  if [ "$res" != "0" ]; then
    return "$res"
  fi

  if [ "$Le_DeployHook" ]; then
    _deploy "$Le_Domain" "$Le_DeployHook"
    res="$?"
  fi

  _ACME_IS_RENEW=""

  return "$res"
}

#renewAll  [stopRenewOnError]
renewAll() {
  _initpath
  _stopRenewOnError="$1"
  _debug "_stopRenewOnError" "$_stopRenewOnError"
  _ret="0"
  _success_msg=""
  _error_msg=""
  _skipped_msg=""
  _error_level=$NOTIFY_LEVEL_SKIP
  _notify_code=$RENEW_SKIP
  _set_level=${NOTIFY_LEVEL:-$NOTIFY_LEVEL_DEFAULT}
  _debug "_set_level" "$_set_level"
  for di in "${CERT_HOME}"/*.*/; do
    _debug di "$di"
    if ! [ -d "$di" ]; then
      _debug "Not a directory, skip: $di"
      continue
    fi
    d=$(basename "$di")
    _debug d "$d"
    (
      if _endswith "$d" "$ECC_SUFFIX"; then
        _isEcc=$(echo "$d" | cut -d "$ECC_SEP" -f 2)
        d=$(echo "$d" | cut -d "$ECC_SEP" -f 1)
      fi
      renew "$d" "$_isEcc"
    )
    rc="$?"
    _debug "Return code: $rc"
    if [ "$rc" = "0" ]; then
      if [ $_error_level -gt $NOTIFY_LEVEL_RENEW ]; then
        _error_level="$NOTIFY_LEVEL_RENEW"
        _notify_code=0
      fi
      if [ "$_ACME_IN_CRON" ]; then
        if [ $_set_level -ge $NOTIFY_LEVEL_RENEW ]; then
          if [ "$NOTIFY_MODE" = "$NOTIFY_MODE_CERT" ]; then
            _send_notify "Renew $d success" "Good, the cert is renewed." "$NOTIFY_HOOK" 0
          fi
        fi
      fi
      _success_msg="${_success_msg}    $d
"
    elif [ "$rc" = "$RENEW_SKIP" ]; then
      if [ $_error_level -gt $NOTIFY_LEVEL_SKIP ]; then
        _error_level="$NOTIFY_LEVEL_SKIP"
        _notify_code=$RENEW_SKIP
      fi
      if [ "$_ACME_IN_CRON" ]; then
        if [ $_set_level -ge $NOTIFY_LEVEL_SKIP ]; then
          if [ "$NOTIFY_MODE" = "$NOTIFY_MODE_CERT" ]; then
            _send_notify "Renew $d skipped" "Good, the cert is skipped." "$NOTIFY_HOOK" "$RENEW_SKIP"
          fi
        fi
      fi
      _info "Skipped $d"
      _skipped_msg="${_skipped_msg}    $d
"
    else
      if [ $_error_level -gt $NOTIFY_LEVEL_ERROR ]; then
        _error_level="$NOTIFY_LEVEL_ERROR"
        _notify_code=1
      fi
      if [ "$_ACME_IN_CRON" ]; then
        if [ $_set_level -ge $NOTIFY_LEVEL_ERROR ]; then
          if [ "$NOTIFY_MODE" = "$NOTIFY_MODE_CERT" ]; then
            _send_notify "Renew $d error" "There is an error." "$NOTIFY_HOOK" 1
          fi
        fi
      fi
      _error_msg="${_error_msg}    $d
"
      if [ "$_stopRenewOnError" ]; then
        _err "Error renew $d,  stop now."
        _ret="$rc"
        break
      else
        _ret="$rc"
        _err "Error renew $d."
      fi
    fi
  done
  _debug _error_level "$_error_level"
  _debug _set_level "$_set_level"
  if [ "$_ACME_IN_CRON" ] && [ $_error_level -le $_set_level ]; then
    if [ -z "$NOTIFY_MODE" ] || [ "$NOTIFY_MODE" = "$NOTIFY_MODE_BULK" ]; then
      _msg_subject="Renew"
      if [ "$_error_msg" ]; then
        _msg_subject="${_msg_subject} Error"
        _msg_data="Error certs:
${_error_msg}
"
      fi
      if [ "$_success_msg" ]; then
        _msg_subject="${_msg_subject} Success"
        _msg_data="${_msg_data}Success certs:
${_success_msg}
"
      fi
      if [ "$_skipped_msg" ]; then
        _msg_subject="${_msg_subject} Skipped"
        _msg_data="${_msg_data}Skipped certs:
${_skipped_msg}
"
      fi

      _send_notify "$_msg_subject" "$_msg_data" "$NOTIFY_HOOK" "$_notify_code"
    fi
  fi

  return "$_ret"
}

#csr webroot
signcsr() {
  _csrfile="$1"
  _csrW="$2"
  if [ -z "$_csrfile" ] || [ -z "$_csrW" ]; then
    _usage "Usage: $PROJECT_ENTRY --sign-csr --csr <csr-file> --webroot <directory>"
    return 1
  fi

  _real_cert="$3"
  _real_key="$4"
  _real_ca="$5"
  _reload_cmd="$6"
  _real_fullchain="$7"
  _pre_hook="${8}"
  _post_hook="${9}"
  _renew_hook="${10}"
  _local_addr="${11}"
  _challenge_alias="${12}"
  _preferred_chain="${13}"

  _csrsubj=$(_readSubjectFromCSR "$_csrfile")
  if [ "$?" != "0" ]; then
    _err "Can not read subject from csr: $_csrfile"
    return 1
  fi
  _debug _csrsubj "$_csrsubj"
  if _contains "$_csrsubj" ' ' || ! _contains "$_csrsubj" '.'; then
    _info "It seems that the subject: $_csrsubj is not a valid domain name. Drop it."
    _csrsubj=""
  fi

  _csrdomainlist=$(_readSubjectAltNamesFromCSR "$_csrfile")
  if [ "$?" != "0" ]; then
    _err "Can not read domain list from csr: $_csrfile"
    return 1
  fi
  _debug "_csrdomainlist" "$_csrdomainlist"

  if [ -z "$_csrsubj" ]; then
    _csrsubj="$(_getfield "$_csrdomainlist" 1)"
    _debug _csrsubj "$_csrsubj"
    _csrdomainlist="$(echo "$_csrdomainlist" | cut -d , -f 2-)"
    _debug "_csrdomainlist" "$_csrdomainlist"
  fi

  if [ -z "$_csrsubj" ]; then
    _err "Can not read subject from csr: $_csrfile"
    return 1
  fi

  _csrkeylength=$(_readKeyLengthFromCSR "$_csrfile")
  if [ "$?" != "0" ] || [ -z "$_csrkeylength" ]; then
    _err "Can not read key length from csr: $_csrfile"
    return 1
  fi

  _initpath "$_csrsubj" "$_csrkeylength"
  mkdir -p "$DOMAIN_PATH"

  _info "Copy csr to: $CSR_PATH"
  cp "$_csrfile" "$CSR_PATH"

  issue "$_csrW" "$_csrsubj" "$_csrdomainlist" "$_csrkeylength" "$_real_cert" "$_real_key" "$_real_ca" "$_reload_cmd" "$_real_fullchain" "$_pre_hook" "$_post_hook" "$_renew_hook" "$_local_addr" "$_challenge_alias" "$_preferred_chain"

}

showcsr() {
  _csrfile="$1"
  _csrd="$2"
  if [ -z "$_csrfile" ] && [ -z "$_csrd" ]; then
    _usage "Usage: $PROJECT_ENTRY --show-csr --csr <csr-file>"
    return 1
  fi

  _initpath

  _csrsubj=$(_readSubjectFromCSR "$_csrfile")
  if [ "$?" != "0" ] || [ -z "$_csrsubj" ]; then
    _err "Can not read subject from csr: $_csrfile"
    return 1
  fi

  _info "Subject=$_csrsubj"

  _csrdomainlist=$(_readSubjectAltNamesFromCSR "$_csrfile")
  if [ "$?" != "0" ]; then
    _err "Can not read domain list from csr: $_csrfile"
    return 1
  fi
  _debug "_csrdomainlist" "$_csrdomainlist"

  _info "SubjectAltNames=$_csrdomainlist"

  _csrkeylength=$(_readKeyLengthFromCSR "$_csrfile")
  if [ "$?" != "0" ] || [ -z "$_csrkeylength" ]; then
    _err "Can not read key length from csr: $_csrfile"
    return 1
  fi
  _info "KeyLength=$_csrkeylength"
}

#listraw  domain
list() {
  _raw="$1"
  _domain="$2"
  _initpath

  _sep="|"
  if [ "$_raw" ]; then
    if [ -z "$_domain" ]; then
      printf "%s\n" "Main_Domain${_sep}KeyLength${_sep}SAN_Domains${_sep}CA${_sep}Created${_sep}Renew"
    fi
    for di in "${CERT_HOME}"/*.*/; do
      d=$(basename "$di")
      _debug d "$d"
      (
        if _endswith "$d" "$ECC_SUFFIX"; then
          _isEcc="ecc"
          d=$(echo "$d" | cut -d "$ECC_SEP" -f 1)
        fi
        DOMAIN_CONF="$di/$d.conf"
        if [ -f "$DOMAIN_CONF" ]; then
          . "$DOMAIN_CONF"
          _ca="$(_getCAShortName "$Le_API")"
          if [ -z "$_domain" ]; then
            printf "%s\n" "$Le_Domain${_sep}\"$Le_Keylength\"${_sep}$Le_Alt${_sep}$_ca${_sep}$Le_CertCreateTimeStr${_sep}$Le_NextRenewTimeStr"
          else
            if [ "$_domain" = "$d" ]; then
              cat "$DOMAIN_CONF"
            fi
          fi
        fi
      )
    done
  else
    if _exists column; then
      list "raw" "$_domain" | column -t -s "$_sep"
    else
      list "raw" "$_domain" | tr "$_sep" '\t'
    fi
  fi

}

_deploy() {
  _d="$1"
  _hooks="$2"

  for _d_api in $(echo "$_hooks" | tr ',' " "); do
    _deployApi="$(_findHook "$_d" $_SUB_FOLDER_DEPLOY "$_d_api")"
    if [ -z "$_deployApi" ]; then
      _err "The deploy hook $_d_api is not found."
      return 1
    fi
    _debug _deployApi "$_deployApi"

    if ! (
      if ! . "$_deployApi"; then
        _err "Load file $_deployApi error. Please check your api file and try again."
        return 1
      fi

      d_command="${_d_api}_deploy"
      if ! _exists "$d_command"; then
        _err "It seems that your api file is not correct, it must have a function named: $d_command"
        return 1
      fi

      if ! $d_command "$_d" "$CERT_KEY_PATH" "$CERT_PATH" "$CA_CERT_PATH" "$CERT_FULLCHAIN_PATH"; then
        _err "Error deploy for domain:$_d"
        return 1
      fi
    ); then
      _err "Deploy error."
      return 1
    else
      _info "$(__green Success)"
    fi
  done
}

#domain hooks
deploy() {
  _d="$1"
  _hooks="$2"
  _isEcc="$3"
  if [ -z "$_hooks" ]; then
    _usage "Usage: $PROJECT_ENTRY --deploy --domain <domain.tld> --deploy-hook <hookname> [--ecc] "
    return 1
  fi

  _initpath "$_d" "$_isEcc"
  if [ ! -d "$DOMAIN_PATH" ]; then
    _err "The domain '$_d' is not a cert name. You must use the cert name to specify the cert to install."
    _err "Can not find path:'$DOMAIN_PATH'"
    return 1
  fi

  . "$DOMAIN_CONF"

  _savedomainconf Le_DeployHook "$_hooks"

  _deploy "$_d" "$_hooks"
}

installcert() {
  _main_domain="$1"
  if [ -z "$_main_domain" ]; then
    _usage "Usage: $PROJECT_ENTRY --install-cert --domain <domain.tld> [--ecc] [--cert-file <file>] [--key-file <file>] [--ca-file <file>] [ --reloadcmd <command>] [--fullchain-file <file>]"
    return 1
  fi

  _real_cert="$2"
  _real_key="$3"
  _real_ca="$4"
  _reload_cmd="$5"
  _real_fullchain="$6"
  _isEcc="$7"

  _initpath "$_main_domain" "$_isEcc"
  if [ ! -d "$DOMAIN_PATH" ]; then
    _err "The domain '$_main_domain' is not a cert name. You must use the cert name to specify the cert to install."
    _err "Can not find path:'$DOMAIN_PATH'"
    return 1
  fi

  _savedomainconf "Le_RealCertPath" "$_real_cert"
  _savedomainconf "Le_RealCACertPath" "$_real_ca"
  _savedomainconf "Le_RealKeyPath" "$_real_key"
  _savedomainconf "Le_ReloadCmd" "$_reload_cmd" "base64"
  _savedomainconf "Le_RealFullChainPath" "$_real_fullchain"

  _installcert "$_main_domain" "$_real_cert" "$_real_key" "$_real_ca" "$_real_fullchain" "$_reload_cmd"
}

#domain  cert  key  ca  fullchain reloadcmd backup-prefix
_installcert() {
  _main_domain="$1"
  _real_cert="$2"
  _real_key="$3"
  _real_ca="$4"
  _real_fullchain="$5"
  _reload_cmd="$6"
  _backup_prefix="$7"

  if [ "$_real_cert" = "$NO_VALUE" ]; then
    _real_cert=""
  fi
  if [ "$_real_key" = "$NO_VALUE" ]; then
    _real_key=""
  fi
  if [ "$_real_ca" = "$NO_VALUE" ]; then
    _real_ca=""
  fi
  if [ "$_reload_cmd" = "$NO_VALUE" ]; then
    _reload_cmd=""
  fi
  if [ "$_real_fullchain" = "$NO_VALUE" ]; then
    _real_fullchain=""
  fi

  _backup_path="$DOMAIN_BACKUP_PATH/$_backup_prefix"
  mkdir -p "$_backup_path"

  if [ "$_real_cert" ]; then
    _info "Installing cert to: $_real_cert"
    if [ -f "$_real_cert" ] && [ ! "$_ACME_IS_RENEW" ]; then
      cp "$_real_cert" "$_backup_path/cert.bak"
    fi
    cat "$CERT_PATH" >"$_real_cert" || return 1
  fi

  if [ "$_real_ca" ]; then
    _info "Installing CA to: $_real_ca"
    if [ "$_real_ca" = "$_real_cert" ]; then
      echo "" >>"$_real_ca"
      cat "$CA_CERT_PATH" >>"$_real_ca" || return 1
    else
      if [ -f "$_real_ca" ] && [ ! "$_ACME_IS_RENEW" ]; then
        cp "$_real_ca" "$_backup_path/ca.bak"
      fi
      cat "$CA_CERT_PATH" >"$_real_ca" || return 1
    fi
  fi

  if [ "$_real_key" ]; then
    _info "Installing key to: $_real_key"
    if [ -f "$_real_key" ] && [ ! "$_ACME_IS_RENEW" ]; then
      cp "$_real_key" "$_backup_path/key.bak"
    fi
    if [ -f "$_real_key" ]; then
      cat "$CERT_KEY_PATH" >"$_real_key" || return 1
    else
      cat "$CERT_KEY_PATH" >"$_real_key" || return 1
      chmod 600 "$_real_key"
    fi
  fi

  if [ "$_real_fullchain" ]; then
    _info "Installing full chain to: $_real_fullchain"
    if [ -f "$_real_fullchain" ] && [ ! "$_ACME_IS_RENEW" ]; then
      cp "$_real_fullchain" "$_backup_path/fullchain.bak"
    fi
    cat "$CERT_FULLCHAIN_PATH" >"$_real_fullchain" || return 1
  fi

  if [ "$_reload_cmd" ]; then
    _info "Run reload cmd: $_reload_cmd"
    if (
      export CERT_PATH
      export CERT_KEY_PATH
      export CA_CERT_PATH
      export CERT_FULLCHAIN_PATH
      export Le_Domain="$_main_domain"
      cd "$DOMAIN_PATH" && eval "$_reload_cmd"
    ); then
      _info "$(__green "Reload success")"
    else
      _err "Reload error for :$Le_Domain"
    fi
  fi

}

__read_password() {
  unset _pp
  prompt="Enter Password:"
  while IFS= read -p "$prompt" -r -s -n 1 char; do
    if [ "$char" = $'\0' ]; then
      break
    fi
    prompt='*'
    _pp="$_pp$char"
  done
  echo "$_pp"
}

_install_win_taskscheduler() {
  _lesh="$1"
  _centry="$2"
  _randomminute="$3"
  if ! _exists cygpath; then
    _err "cygpath not found"
    return 1
  fi
  if ! _exists schtasks; then
    _err "schtasks.exe is not found, are you on Windows?"
    return 1
  fi
  _winbash="$(cygpath -w $(which bash))"
  _debug _winbash "$_winbash"
  if [ -z "$_winbash" ]; then
    _err "can not find bash path"
    return 1
  fi
  _myname="$(whoami)"
  _debug "_myname" "$_myname"
  if [ -z "$_myname" ]; then
    _err "can not find my user name"
    return 1
  fi
  _debug "_lesh" "$_lesh"

  _info "To install scheduler task in your Windows account, you must input your windows password."
  _info "$PROJECT_NAME doesn't save your password."
  _info "Please input your Windows password for: $(__green "$_myname")"
  _password="$(__read_password)"
  #SCHTASKS.exe '/create' '/SC' 'DAILY' '/TN' "$_WINDOWS_SCHEDULER_NAME" '/F' '/ST' "00:$_randomminute" '/RU' "$_myname" '/RP' "$_password" '/TR' "$_winbash -l -c '$_lesh --cron --home \"$LE_WORKING_DIR\" $_centry'" >/dev/null
  echo SCHTASKS.exe '/create' '/SC' 'DAILY' '/TN' "$_WINDOWS_SCHEDULER_NAME" '/F' '/ST' "00:$_randomminute" '/RU' "$_myname" '/RP' "$_password" '/TR' "\"$_winbash -l -c '$_lesh --cron --home \"$LE_WORKING_DIR\" $_centry'\"" | cmd.exe >/dev/null
  echo

}

_uninstall_win_taskscheduler() {
  if ! _exists schtasks; then
    _err "schtasks.exe is not found, are you on Windows?"
    return 1
  fi
  if ! echo SCHTASKS /query /tn "$_WINDOWS_SCHEDULER_NAME" | cmd.exe >/dev/null; then
    _debug "scheduler $_WINDOWS_SCHEDULER_NAME is not found."
  else
    _info "Removing $_WINDOWS_SCHEDULER_NAME"
    echo SCHTASKS /delete /f /tn "$_WINDOWS_SCHEDULER_NAME" | cmd.exe >/dev/null
  fi
}

#confighome
installcronjob() {
  _c_home="$1"
  _initpath
  _CRONTAB="crontab"
  if [ -f "$LE_WORKING_DIR/$PROJECT_ENTRY" ]; then
    lesh="\"$LE_WORKING_DIR\"/$PROJECT_ENTRY"
  else
    _err "Can not install cronjob, $PROJECT_ENTRY not found."
    return 1
  fi
  if [ "$_c_home" ]; then
    _c_entry="--config-home \"$_c_home\" "
  fi
  _t=$(_time)
  random_minute=$(_math $_t % 60)

  if ! _exists "$_CRONTAB" && _exists "fcrontab"; then
    _CRONTAB="fcrontab"
  fi

  if ! _exists "$_CRONTAB"; then
    if _exists cygpath && _exists schtasks.exe; then
      _info "It seems you are on Windows,  let's install Windows scheduler task."
      if _install_win_taskscheduler "$lesh" "$_c_entry" "$random_minute"; then
        _info "Install Windows scheduler task success."
        return 0
      else
        _err "Install Windows scheduler task failed."
        return 1
      fi
    fi
    _err "crontab/fcrontab doesn't exist, so, we can not install cron jobs."
    _err "All your certs will not be renewed automatically."
    _err "You must add your own cron job to call '$PROJECT_ENTRY --cron' everyday."
    return 1
  fi
  _info "Installing cron job"
  if ! $_CRONTAB -l | grep "$PROJECT_ENTRY --cron"; then
    if _exists uname && uname -a | grep SunOS >/dev/null; then
      $_CRONTAB -l | {
        cat
        echo "$random_minute 0 * * * $lesh --cron --home \"$LE_WORKING_DIR\" $_c_entry> /dev/null"
      } | $_CRONTAB --
    else
      $_CRONTAB -l | {
        cat
        echo "$random_minute 0 * * * $lesh --cron --home \"$LE_WORKING_DIR\" $_c_entry> /dev/null"
      } | $_CRONTAB -
    fi
  fi
  if [ "$?" != "0" ]; then
    _err "Install cron job failed. You need to manually renew your certs."
    _err "Or you can add cronjob by yourself:"
    _err "$lesh --cron --home \"$LE_WORKING_DIR\" > /dev/null"
    return 1
  fi
}

uninstallcronjob() {
  _CRONTAB="crontab"
  if ! _exists "$_CRONTAB" && _exists "fcrontab"; then
    _CRONTAB="fcrontab"
  fi

  if ! _exists "$_CRONTAB"; then
    if _exists cygpath && _exists schtasks.exe; then
      _info "It seems you are on Windows,  let's uninstall Windows scheduler task."
      if _uninstall_win_taskscheduler; then
        _info "Uninstall Windows scheduler task success."
        return 0
      else
        _err "Uninstall Windows scheduler task failed."
        return 1
      fi
    fi
    return
  fi
  _info "Removing cron job"
  cr="$($_CRONTAB -l | grep "$PROJECT_ENTRY --cron")"
  if [ "$cr" ]; then
    if _exists uname && uname -a | grep SunOS >/dev/null; then
      $_CRONTAB -l | sed "/$PROJECT_ENTRY --cron/d" | $_CRONTAB --
    else
      $_CRONTAB -l | sed "/$PROJECT_ENTRY --cron/d" | $_CRONTAB -
    fi
    LE_WORKING_DIR="$(echo "$cr" | cut -d ' ' -f 9 | tr -d '"')"
    _info LE_WORKING_DIR "$LE_WORKING_DIR"
    if _contains "$cr" "--config-home"; then
      LE_CONFIG_HOME="$(echo "$cr" | cut -d ' ' -f 11 | tr -d '"')"
      _debug LE_CONFIG_HOME "$LE_CONFIG_HOME"
    fi
  fi
  _initpath

}

#domain  isECC  revokeReason
revoke() {
  Le_Domain="$1"
  if [ -z "$Le_Domain" ]; then
    _usage "Usage: $PROJECT_ENTRY --revoke --domain <domain.tld> [--ecc]"
    return 1
  fi

  _isEcc="$2"
  _reason="$3"
  if [ -z "$_reason" ]; then
    _reason="0"
  fi
  _initpath "$Le_Domain" "$_isEcc"
  if [ ! -f "$DOMAIN_CONF" ]; then
    _err "$Le_Domain is not a issued domain, skip."
    return 1
  fi

  if [ ! -f "$CERT_PATH" ]; then
    _err "Cert for $Le_Domain $CERT_PATH is not found, skip."
    return 1
  fi

  . "$DOMAIN_CONF"
  _debug Le_API "$Le_API"

  if [ "$Le_API" ]; then
    if [ "$Le_API" != "$ACME_DIRECTORY" ]; then
      _clearAPI
    fi
    export ACME_DIRECTORY="$Le_API"
    #reload ca configs
    ACCOUNT_KEY_PATH=""
    ACCOUNT_JSON_PATH=""
    CA_CONF=""
    _debug3 "initpath again."
    _initpath "$Le_Domain" "$_isEcc"
    _initAPI
  fi

  cert="$(_getfile "${CERT_PATH}" "${BEGIN_CERT}" "${END_CERT}" | tr -d "\r\n" | _url_replace)"

  if [ -z "$cert" ]; then
    _err "Cert for $Le_Domain is empty found, skip."
    return 1
  fi

  _initAPI

  data="{\"certificate\": \"$cert\",\"reason\":$_reason}"

  uri="${ACME_REVOKE_CERT}"

  if [ -f "$CERT_KEY_PATH" ]; then
    _info "Try domain key first."
    if _send_signed_request "$uri" "$data" "" "$CERT_KEY_PATH"; then
      if [ -z "$response" ]; then
        _info "Revoke success."
        rm -f "$CERT_PATH"
        return 0
      else
        _err "Revoke error by domain key."
        _err "$response"
      fi
    fi
  else
    _info "Domain key file doesn't exist."
  fi

  _info "Try account key."

  if _send_signed_request "$uri" "$data" "" "$ACCOUNT_KEY_PATH"; then
    if [ -z "$response" ]; then
      _info "Revoke success."
      rm -f "$CERT_PATH"
      return 0
    else
      _err "Revoke error."
      _debug "$response"
    fi
  fi
  return 1
}

#domain  ecc
remove() {
  Le_Domain="$1"
  if [ -z "$Le_Domain" ]; then
    _usage "Usage: $PROJECT_ENTRY --remove --domain <domain.tld> [--ecc]"
    return 1
  fi

  _isEcc="$2"

  _initpath "$Le_Domain" "$_isEcc"
  _removed_conf="$DOMAIN_CONF.removed"
  if [ ! -f "$DOMAIN_CONF" ]; then
    if [ -f "$_removed_conf" ]; then
      _err "$Le_Domain is already removed, You can remove the folder by yourself: $DOMAIN_PATH"
    else
      _err "$Le_Domain is not a issued domain, skip."
    fi
    return 1
  fi

  if mv "$DOMAIN_CONF" "$_removed_conf"; then
    _info "$Le_Domain is removed, the key and cert files are in $(__green $DOMAIN_PATH)"
    _info "You can remove them by yourself."
    return 0
  else
    _err "Remove $Le_Domain failed."
    return 1
  fi
}

#domain vtype
_deactivate() {
  _d_domain="$1"
  _d_type="$2"
  _initpath "$_d_domain" "$_d_type"

  . "$DOMAIN_CONF"
  _debug Le_API "$Le_API"

  if [ "$Le_API" ]; then
    if [ "$Le_API" != "$ACME_DIRECTORY" ]; then
      _clearAPI
    fi
    export ACME_DIRECTORY="$Le_API"
    #reload ca configs
    ACCOUNT_KEY_PATH=""
    ACCOUNT_JSON_PATH=""
    CA_CONF=""
    _debug3 "initpath again."
    _initpath "$Le_Domain" "$_d_type"
    _initAPI
  fi

  _identifiers="{\"type\":\"dns\",\"value\":\"$_d_domain\"}"
  if ! _send_signed_request "$ACME_NEW_ORDER" "{\"identifiers\": [$_identifiers]}"; then
    _err "Can not get domain new order."
    return 1
  fi
  _authorizations_seg="$(echo "$response" | _egrep_o '"authorizations" *: *\[[^\]*\]' | cut -d '[' -f 2 | tr -d ']' | tr -d '"')"
  _debug2 _authorizations_seg "$_authorizations_seg"
  if [ -z "$_authorizations_seg" ]; then
    _err "_authorizations_seg not found."
    _clearup
    _on_issue_err "$_post_hook"
    return 1
  fi

  authzUri="$_authorizations_seg"
  _debug2 "authzUri" "$authzUri"
  if ! _send_signed_request "$authzUri"; then
    _err "get to authz error."
    _err "_authorizations_seg" "$_authorizations_seg"
    _err "authzUri" "$authzUri"
    _clearup
    _on_issue_err "$_post_hook"
    return 1
  fi

  response="$(echo "$response" | _normalizeJson)"
  _debug2 response "$response"
  _URL_NAME="url"

  entries="$(echo "$response" | tr '][' '==' | _egrep_o "challenges\": *=[^=]*=" | tr '}{' '\n\n' | grep "\"status\": *\"valid\"")"
  if [ -z "$entries" ]; then
    _info "No valid entries found."
    if [ -z "$thumbprint" ]; then
      thumbprint="$(__calc_account_thumbprint)"
    fi
    _debug "Trigger validation."
    vtype="$VTYPE_DNS"
    entry="$(echo "$response" | _egrep_o '[^\{]*"type":"'$vtype'"[^\}]*')"
    _debug entry "$entry"
    if [ -z "$entry" ]; then
      _err "Error, can not get domain token $d"
      return 1
    fi
    token="$(echo "$entry" | _egrep_o '"token":"[^"]*' | cut -d : -f 2 | tr -d '"')"
    _debug token "$token"

    uri="$(echo "$entry" | _egrep_o "\"$_URL_NAME\":\"[^\"]*" | cut -d : -f 2,3 | tr -d '"')"
    _debug uri "$uri"

    keyauthorization="$token.$thumbprint"
    _debug keyauthorization "$keyauthorization"
    __trigger_validation "$uri" "$keyauthorization"

  fi

  _d_i=0
  _d_max_retry=$(echo "$entries" | wc -l)
  while [ "$_d_i" -lt "$_d_max_retry" ]; do
    _info "Deactivate: $_d_domain"
    _d_i="$(_math $_d_i + 1)"
    entry="$(echo "$entries" | sed -n "${_d_i}p")"
    _debug entry "$entry"

    if [ -z "$entry" ]; then
      _info "No more valid entry found."
      break
    fi

    _vtype="$(echo "$entry" | _egrep_o '"type": *"[^"]*"' | cut -d : -f 2 | tr -d '"')"
    _debug _vtype "$_vtype"
    _info "Found $_vtype"

    uri="$(echo "$entry" | _egrep_o "\"$_URL_NAME\":\"[^\"]*\"" | tr -d '" ' | cut -d : -f 2-)"
    _debug uri "$uri"

    if [ "$_d_type" ] && [ "$_d_type" != "$_vtype" ]; then
      _info "Skip $_vtype"
      continue
    fi

    _info "Deactivate: $_vtype"

    _djson="{\"status\":\"deactivated\"}"

    if _send_signed_request "$authzUri" "$_djson" && _contains "$response" '"deactivated"'; then
      _info "Deactivate: $_vtype success."
    else
      _err "Can not deactivate $_vtype."
      break
    fi

  done
  _debug "$_d_i"
  if [ "$_d_i" -eq "$_d_max_retry" ]; then
    _info "Deactivated success!"
  else
    _err "Deactivate failed."
  fi

}

deactivate() {
  _d_domain_list="$1"
  _d_type="$2"
  _initpath
  _initAPI
  _debug _d_domain_list "$_d_domain_list"
  if [ -z "$(echo $_d_domain_list | cut -d , -f 1)" ]; then
    _usage "Usage: $PROJECT_ENTRY --deactivate --domain <domain.tld> [--domain <domain2.tld> ...]"
    return 1
  fi
  for _d_dm in $(echo "$_d_domain_list" | tr ',' ' '); do
    if [ -z "$_d_dm" ] || [ "$_d_dm" = "$NO_VALUE" ]; then
      continue
    fi
    if ! _deactivate "$_d_dm" "$_d_type"; then
      return 1
    fi
  done
}

# Detect profile file if not specified as environment variable
_detect_profile() {
  if [ -n "$PROFILE" -a -f "$PROFILE" ]; then
    echo "$PROFILE"
    return
  fi

  DETECTED_PROFILE=''
  SHELLTYPE="$(basename "/$SHELL")"

  if [ "$SHELLTYPE" = "bash" ]; then
    if [ -f "$HOME/.bashrc" ]; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    fi
  elif [ "$SHELLTYPE" = "zsh" ]; then
    DETECTED_PROFILE="$HOME/.zshrc"
  fi

  if [ -z "$DETECTED_PROFILE" ]; then
    if [ -f "$HOME/.profile" ]; then
      DETECTED_PROFILE="$HOME/.profile"
    elif [ -f "$HOME/.bashrc" ]; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    elif [ -f "$HOME/.zshrc" ]; then
      DETECTED_PROFILE="$HOME/.zshrc"
    fi
  fi

  echo "$DETECTED_PROFILE"
}

_initconf() {
  _initpath
  if [ ! -f "$ACCOUNT_CONF_PATH" ]; then
    echo "

#LOG_FILE=\"$DEFAULT_LOG_FILE\"
#LOG_LEVEL=1

#AUTO_UPGRADE=\"1\"

#NO_TIMESTAMP=1

    " >"$ACCOUNT_CONF_PATH"
  fi
}

# nocron
_precheck() {
  _nocron="$1"

  if ! _exists "curl" && ! _exists "wget"; then
    _err "Please install curl or wget first, we need to access http resources."
    return 1
  fi

  if [ -z "$_nocron" ]; then
    if ! _exists "crontab" && ! _exists "fcrontab"; then
      if _exists cygpath && _exists schtasks.exe; then
        _info "It seems you are on Windows,  we will install Windows scheduler task."
      else
        _err "It is recommended to install crontab first. try to install 'cron, crontab, crontabs or vixie-cron'."
        _err "We need to set cron job to renew the certs automatically."
        _err "Otherwise, your certs will not be able to be renewed automatically."
        if [ -z "$FORCE" ]; then
          _err "Please add '--force' and try install again to go without crontab."
          _err "./$PROJECT_ENTRY --install --force"
          return 1
        fi
      fi
    fi
  fi

  if ! _exists "${ACME_OPENSSL_BIN:-openssl}"; then
    _err "Please install openssl first. ACME_OPENSSL_BIN=$ACME_OPENSSL_BIN"
    _err "We need openssl to generate keys."
    return 1
  fi

  if ! _exists "socat"; then
    _err "It is recommended to install socat first."
    _err "We use socat for standalone server if you use standalone mode."
    _err "If you don't use standalone mode, just ignore this warning."
  fi

  return 0
}

_setShebang() {
  _file="$1"
  _shebang="$2"
  if [ -z "$_shebang" ]; then
    _usage "Usage: file shebang"
    return 1
  fi
  cp "$_file" "$_file.tmp"
  echo "$_shebang" >"$_file"
  sed -n 2,99999p "$_file.tmp" >>"$_file"
  rm -f "$_file.tmp"
}

#confighome
_installalias() {
  _c_home="$1"
  _initpath

  _envfile="$LE_WORKING_DIR/$PROJECT_ENTRY.env"
  if [ "$_upgrading" ] && [ "$_upgrading" = "1" ]; then
    echo "$(cat "$_envfile")" | sed "s|^LE_WORKING_DIR.*$||" >"$_envfile"
    echo "$(cat "$_envfile")" | sed "s|^alias le.*$||" >"$_envfile"
    echo "$(cat "$_envfile")" | sed "s|^alias le.sh.*$||" >"$_envfile"
  fi

  if [ "$_c_home" ]; then
    _c_entry=" --config-home '$_c_home'"
  fi

  _setopt "$_envfile" "export LE_WORKING_DIR" "=" "\"$LE_WORKING_DIR\""
  if [ "$_c_home" ]; then
    _setopt "$_envfile" "export LE_CONFIG_HOME" "=" "\"$LE_CONFIG_HOME\""
  else
    _sed_i "/^export LE_CONFIG_HOME/d" "$_envfile"
  fi
  _setopt "$_envfile" "alias $PROJECT_ENTRY" "=" "\"$LE_WORKING_DIR/$PROJECT_ENTRY$_c_entry\""

  _profile="$(_detect_profile)"
  if [ "$_profile" ]; then
    _debug "Found profile: $_profile"
    _info "Installing alias to '$_profile'"
    _setopt "$_profile" ". \"$_envfile\""
    _info "OK, Close and reopen your terminal to start using $PROJECT_NAME"
  else
    _info "No profile is found, you will need to go into $LE_WORKING_DIR to use $PROJECT_NAME"
  fi

  #for csh
  _cshfile="$LE_WORKING_DIR/$PROJECT_ENTRY.csh"
  _csh_profile="$HOME/.cshrc"
  if [ -f "$_csh_profile" ]; then
    _info "Installing alias to '$_csh_profile'"
    _setopt "$_cshfile" "setenv LE_WORKING_DIR" " " "\"$LE_WORKING_DIR\""
    if [ "$_c_home" ]; then
      _setopt "$_cshfile" "setenv LE_CONFIG_HOME" " " "\"$LE_CONFIG_HOME\""
    else
      _sed_i "/^setenv LE_CONFIG_HOME/d" "$_cshfile"
    fi
    _setopt "$_cshfile" "alias $PROJECT_ENTRY" " " "\"$LE_WORKING_DIR/$PROJECT_ENTRY$_c_entry\""
    _setopt "$_csh_profile" "source \"$_cshfile\""
  fi

  #for tcsh
  _tcsh_profile="$HOME/.tcshrc"
  if [ -f "$_tcsh_profile" ]; then
    _info "Installing alias to '$_tcsh_profile'"
    _setopt "$_cshfile" "setenv LE_WORKING_DIR" " " "\"$LE_WORKING_DIR\""
    if [ "$_c_home" ]; then
      _setopt "$_cshfile" "setenv LE_CONFIG_HOME" " " "\"$LE_CONFIG_HOME\""
    fi
    _setopt "$_cshfile" "alias $PROJECT_ENTRY" " " "\"$LE_WORKING_DIR/$PROJECT_ENTRY$_c_entry\""
    _setopt "$_tcsh_profile" "source \"$_cshfile\""
  fi

}

# nocron confighome noprofile accountemail
install() {

  if [ -z "$LE_WORKING_DIR" ]; then
    LE_WORKING_DIR="$DEFAULT_INSTALL_HOME"
  fi

  _nocron="$1"
  _c_home="$2"
  _noprofile="$3"
  _accountemail="$4"

  if ! _initpath; then
    _err "Install failed."
    return 1
  fi
  if [ "$_nocron" ]; then
    _debug "Skip install cron job"
  fi

  if [ "$_ACME_IN_CRON" != "1" ]; then
    if ! _precheck "$_nocron"; then
      _err "Pre-check failed, can not install."
      return 1
    fi
  fi

  if [ -z "$_c_home" ] && [ "$LE_CONFIG_HOME" != "$LE_WORKING_DIR" ]; then
    _info "Using config home: $LE_CONFIG_HOME"
    _c_home="$LE_CONFIG_HOME"
  fi

  #convert from le
  if [ -d "$HOME/.le" ]; then
    for envfile in "le.env" "le.sh.env"; do
      if [ -f "$HOME/.le/$envfile" ]; then
        if grep "le.sh" "$HOME/.le/$envfile" >/dev/null; then
          _upgrading="1"
          _info "You are upgrading from le.sh"
          _info "Renaming \"$HOME/.le\" to $LE_WORKING_DIR"
          mv "$HOME/.le" "$LE_WORKING_DIR"
          mv "$LE_WORKING_DIR/$envfile" "$LE_WORKING_DIR/$PROJECT_ENTRY.env"
          break
        fi
      fi
    done
  fi

  _info "Installing to $LE_WORKING_DIR"

  if [ ! -d "$LE_WORKING_DIR" ]; then
    if ! mkdir -p "$LE_WORKING_DIR"; then
      _err "Can not create working dir: $LE_WORKING_DIR"
      return 1
    fi

    chmod 700 "$LE_WORKING_DIR"
  fi

  if [ ! -d "$LE_CONFIG_HOME" ]; then
    if ! mkdir -p "$LE_CONFIG_HOME"; then
      _err "Can not create config dir: $LE_CONFIG_HOME"
      return 1
    fi

    chmod 700 "$LE_CONFIG_HOME"
  fi

  cp "$PROJECT_ENTRY" "$LE_WORKING_DIR/" && chmod +x "$LE_WORKING_DIR/$PROJECT_ENTRY"

  if [ "$?" != "0" ]; then
    _err "Install failed, can not copy $PROJECT_ENTRY"
    return 1
  fi

  _info "Installed to $LE_WORKING_DIR/$PROJECT_ENTRY"

  if [ "$_ACME_IN_CRON" != "1" ] && [ -z "$_noprofile" ]; then
    _installalias "$_c_home"
  fi

  for subf in $_SUB_FOLDERS; do
    if [ -d "$subf" ]; then
      mkdir -p "$LE_WORKING_DIR/$subf"
      cp "$subf"/* "$LE_WORKING_DIR"/"$subf"/
    fi
  done

  if [ ! -f "$ACCOUNT_CONF_PATH" ]; then
    _initconf
  fi

  if [ "$_DEFAULT_ACCOUNT_CONF_PATH" != "$ACCOUNT_CONF_PATH" ]; then
    _setopt "$_DEFAULT_ACCOUNT_CONF_PATH" "ACCOUNT_CONF_PATH" "=" "\"$ACCOUNT_CONF_PATH\""
  fi

  if [ "$_DEFAULT_CERT_HOME" != "$CERT_HOME" ]; then
    _saveaccountconf "CERT_HOME" "$CERT_HOME"
  fi

  if [ "$_DEFAULT_ACCOUNT_KEY_PATH" != "$ACCOUNT_KEY_PATH" ]; then
    _saveaccountconf "ACCOUNT_KEY_PATH" "$ACCOUNT_KEY_PATH"
  fi

  if [ -z "$_nocron" ]; then
    installcronjob "$_c_home"
  fi

  if [ -z "$NO_DETECT_SH" ]; then
    #Modify shebang
    if _exists bash; then
      _bash_path="$(bash -c "command -v bash 2>/dev/null")"
      if [ -z "$_bash_path" ]; then
        _bash_path="$(bash -c 'echo $SHELL')"
      fi
    fi
    if [ "$_bash_path" ]; then
      _info "Good, bash is found, so change the shebang to use bash as preferred."
      _shebang='#!'"$_bash_path"
      _setShebang "$LE_WORKING_DIR/$PROJECT_ENTRY" "$_shebang"
      for subf in $_SUB_FOLDERS; do
        if [ -d "$LE_WORKING_DIR/$subf" ]; then
          for _apifile in "$LE_WORKING_DIR/$subf/"*.sh; do
            _setShebang "$_apifile" "$_shebang"
          done
        fi
      done
    fi
  fi

  if [ "$_accountemail" ]; then
    _saveaccountconf "ACCOUNT_EMAIL" "$_accountemail"
  fi

  _info OK
}

# nocron
uninstall() {
  _nocron="$1"
  if [ -z "$_nocron" ]; then
    uninstallcronjob
  fi
  _initpath

  _uninstallalias

  rm -f "$LE_WORKING_DIR/$PROJECT_ENTRY"
  _info "The keys and certs are in \"$(__green "$LE_CONFIG_HOME")\", you can remove them by yourself."

}

_uninstallalias() {
  _initpath

  _profile="$(_detect_profile)"
  if [ "$_profile" ]; then
    _info "Uninstalling alias from: '$_profile'"
    text="$(cat "$_profile")"
    echo "$text" | sed "s|^.*\"$LE_WORKING_DIR/$PROJECT_NAME.env\"$||" >"$_profile"
  fi

  _csh_profile="$HOME/.cshrc"
  if [ -f "$_csh_profile" ]; then
    _info "Uninstalling alias from: '$_csh_profile'"
    text="$(cat "$_csh_profile")"
    echo "$text" | sed "s|^.*\"$LE_WORKING_DIR/$PROJECT_NAME.csh\"$||" >"$_csh_profile"
  fi

  _tcsh_profile="$HOME/.tcshrc"
  if [ -f "$_tcsh_profile" ]; then
    _info "Uninstalling alias from: '$_csh_profile'"
    text="$(cat "$_tcsh_profile")"
    echo "$text" | sed "s|^.*\"$LE_WORKING_DIR/$PROJECT_NAME.csh\"$||" >"$_tcsh_profile"
  fi

}

cron() {
  export _ACME_IN_CRON=1
  _initpath
  _info "$(__green "===Starting cron===")"
  if [ "$AUTO_UPGRADE" = "1" ]; then
    export LE_WORKING_DIR
    (
      if ! upgrade; then
        _err "Cron:Upgrade failed!"
        return 1
      fi
    )
    . "$LE_WORKING_DIR/$PROJECT_ENTRY" >/dev/null

    if [ -t 1 ]; then
      __INTERACTIVE="1"
    fi

    _info "Auto upgraded to: $VER"
  fi
  renewAll
  _ret="$?"
  _ACME_IN_CRON=""
  _info "$(__green "===End cron===")"
  exit $_ret
}

version() {
  echo "$PROJECT"
  echo "v$VER"
}

# subject content hooks code
_send_notify() {
  _nsubject="$1"
  _ncontent="$2"
  _nhooks="$3"
  _nerror="$4"

  if [ "$NOTIFY_LEVEL" = "$NOTIFY_LEVEL_DISABLE" ]; then
    _debug "The NOTIFY_LEVEL is $NOTIFY_LEVEL, disabled, just return."
    return 0
  fi

  if [ -z "$_nhooks" ]; then
    _debug "The NOTIFY_HOOK is empty, just return."
    return 0
  fi

  _send_err=0
  for _n_hook in $(echo "$_nhooks" | tr ',' " "); do
    _n_hook_file="$(_findHook "" $_SUB_FOLDER_NOTIFY "$_n_hook")"
    _info "Sending via: $_n_hook"
    _debug "Found $_n_hook_file for $_n_hook"
    if [ -z "$_n_hook_file" ]; then
      _err "Can not find the hook file for $_n_hook"
      continue
    fi
    if ! (
      if ! . "$_n_hook_file"; then
        _err "Load file $_n_hook_file error. Please check your api file and try again."
        return 1
      fi

      d_command="${_n_hook}_send"
      if ! _exists "$d_command"; then
        _err "It seems that your api file is not correct, it must have a function named: $d_command"
        return 1
      fi

      if ! $d_command "$_nsubject" "$_ncontent" "$_nerror"; then
        _err "Error send message by $d_command"
        return 1
      fi

      return 0
    ); then
      _err "Set $_n_hook_file error."
      _send_err=1
    else
      _info "$_n_hook $(__green Success)"
    fi
  done
  return $_send_err

}

# hook
_set_notify_hook() {
  _nhooks="$1"

  _test_subject="Hello, this is a notification from $PROJECT_NAME"
  _test_content="If you receive this message, your notification works."

  _send_notify "$_test_subject" "$_test_content" "$_nhooks" 0

}

#[hook] [level] [mode]
setnotify() {
  _nhook="$1"
  _nlevel="$2"
  _nmode="$3"

  _initpath

  if [ -z "$_nhook$_nlevel$_nmode" ]; then
    _usage "Usage: $PROJECT_ENTRY --set-notify [--notify-hook <hookname>] [--notify-level <0|1|2|3>] [--notify-mode <0|1>]"
    _usage "$_NOTIFY_WIKI"
    return 1
  fi

  if [ "$_nlevel" ]; then
    _info "Set notify level to: $_nlevel"
    export "NOTIFY_LEVEL=$_nlevel"
    _saveaccountconf "NOTIFY_LEVEL" "$NOTIFY_LEVEL"
  fi

  if [ "$_nmode" ]; then
    _info "Set notify mode to: $_nmode"
    export "NOTIFY_MODE=$_nmode"
    _saveaccountconf "NOTIFY_MODE" "$NOTIFY_MODE"
  fi

  if [ "$_nhook" ]; then
    _info "Set notify hook to: $_nhook"
    if [ "$_nhook" = "$NO_VALUE" ]; then
      _info "Clear notify hook"
      _clearaccountconf "NOTIFY_HOOK"
    else
      if _set_notify_hook "$_nhook"; then
        export NOTIFY_HOOK="$_nhook"
        _saveaccountconf "NOTIFY_HOOK" "$NOTIFY_HOOK"
        return 0
      else
        _err "Can not set notify hook to: $_nhook"
        return 1
      fi
    fi
  fi

}

showhelp() {
  _initpath
  version
  echo "Usage: $PROJECT_ENTRY <command> ... [parameters ...]
Commands:
  -h, --help               Show this help message.
  -v, --version            Show version info.
  --install                Install $PROJECT_NAME to your system.
  --uninstall              Uninstall $PROJECT_NAME, and uninstall the cron job.
  --upgrade                Upgrade $PROJECT_NAME to the latest code from $PROJECT.
  --issue                  Issue a cert.
  --deploy                 Deploy the cert to your server.
  -i, --install-cert       Install the issued cert to apache/nginx or any other server.
  -r, --renew              Renew a cert.
  --renew-all              Renew all the certs.
  --revoke                 Revoke a cert.
  --remove                 Remove the cert from list of certs known to $PROJECT_NAME.
  --list                   List all the certs.
  --to-pkcs12              Export the certificate and key to a pfx file.
  --to-pkcs8               Convert to pkcs8 format.
  --sign-csr               Issue a cert from an existing csr.
  --show-csr               Show the content of a csr.
  -ccr, --create-csr       Create CSR, professional use.
  --create-domain-key      Create an domain private key, professional use.
  --update-account         Update account info.
  --register-account       Register account key.
  --deactivate-account     Deactivate the account.
  --create-account-key     Create an account private key, professional use.
  --install-cronjob        Install the cron job to renew certs, you don't need to call this. The 'install' command can automatically install the cron job.
  --uninstall-cronjob      Uninstall the cron job. The 'uninstall' command can do this automatically.
  --cron                   Run cron job to renew all the certs.
  --set-notify             Set the cron notification hook, level or mode.
  --deactivate             Deactivate the domain authz, professional use.
  --set-default-ca         Used with '--server', Set the default CA to use.
                           See: $_SERVER_WIKI


Parameters:
  -d, --domain <domain.tld>         Specifies a domain, used to issue, renew or revoke etc.
  --challenge-alias <domain.tld>    The challenge domain alias for DNS alias mode.
                                    See: $_DNS_ALIAS_WIKI

  --domain-alias <domain.tld>       The domain alias for DNS alias mode.
                                    See: $_DNS_ALIAS_WIKI

  --preferred-chain <chain>         If the CA offers multiple certificate chains, prefer the chain with an issuer matching this Subject Common Name.
                                    If no match, the default offered chain will be used. (default: empty)
                                    See: $_PREFERRED_CHAIN_WIKI

  -f, --force                       Force install, force cert renewal or override sudo restrictions.
  --staging, --test                 Use staging server, for testing.
  --debug [0|1|2|3]                 Output debug info. Defaults to 1 if argument is omitted.
  --output-insecure                 Output all the sensitive messages.
                                    By default all the credentials/sensitive messages are hidden from the output/debug/log for security.
  -w, --webroot <directory>         Specifies the web root folder for web root mode.
  --standalone                      Use standalone mode.
  --alpn                            Use standalone alpn mode.
  --stateless                       Use stateless mode.
                                    See: $_STATELESS_WIKI

  --apache                          Use apache mode.
  --dns [dns_hook]                  Use dns manual mode or dns api. Defaults to manual mode when argument is omitted.
                                    See: $_DNS_API_WIKI

  --dnssleep <seconds>              The time in seconds to wait for all the txt records to propagate in dns api mode.
                                    It's not necessary to use this by default, $PROJECT_NAME polls dns status by DOH automatically.
  -k, --keylength <bits>            Specifies the domain key length: 2048, 3072, 4096, 8192 or ec-256, ec-384, ec-521.
  -ak, --accountkeylength <bits>    Specifies the account key length: 2048, 3072, 4096
  --log [file]                      Specifies the log file. Defaults to \"$DEFAULT_LOG_FILE\" if argument is omitted.
  --log-level <1|2>                 Specifies the log level, default is 1.
  --syslog <0|3|6|7>                Syslog level, 0: disable syslog, 3: error, 6: info, 7: debug.
  --eab-kid <eab_key_id>            Key Identifier for External Account Binding.
  --eab-hmac-key <eab_hmac_key>     HMAC key for External Account Binding.


  These parameters are to install the cert to nginx/apache or any other server after issue/renew a cert:

  --cert-file <file>                Path to copy the cert file to after issue/renew..
  --key-file <file>                 Path to copy the key file to after issue/renew.
  --ca-file <file>                  Path to copy the intermediate cert file to after issue/renew.
  --fullchain-file <file>           Path to copy the fullchain cert file to after issue/renew.
  --reloadcmd <command>             Command to execute after issue/renew to reload the server.

  --server <server_uri>             ACME Directory Resource URI. (default: $DEFAULT_CA)
                                    See: $_SERVER_WIKI

  --accountconf <file>              Specifies a customized account config file.
  --home <directory>                Specifies the home dir for $PROJECT_NAME.
  --cert-home <directory>           Specifies the home dir to save all the certs, only valid for '--install' command.
  --config-home <directory>         Specifies the home dir to save all the configurations.
  --useragent <string>              Specifies the user agent string. it will be saved for future use too.
  -m, --email <email>               Specifies the account email, only valid for the '--install' and '--update-account' command.
  --accountkey <file>               Specifies the account key path, only valid for the '--install' command.
  --days <ndays>                    Specifies the days to renew the cert when using '--issue' command. The default value is $DEFAULT_RENEW days.
  --httpport <port>                 Specifies the standalone listening port. Only valid if the server is behind a reverse proxy or load balancer.
  --tlsport <port>                  Specifies the standalone tls listening port. Only valid if the server is behind a reverse proxy or load balancer.
  --local-address <ip>              Specifies the standalone/tls server listening address, in case you have multiple ip addresses.
  --listraw                         Only used for '--list' command, list the certs in raw format.
  -se, --stop-renew-on-error        Only valid for '--renew-all' command. Stop if one cert has error in renewal.
  --insecure                        Do not check the server certificate, in some devices, the api server's certificate may not be trusted.
  --ca-bundle <file>                Specifies the path to the CA certificate bundle to verify api server's certificate.
  --ca-path <directory>             Specifies directory containing CA certificates in PEM format, used by wget or curl.
  --no-cron                         Only valid for '--install' command, which means: do not install the default cron job.
                                    In this case, the certs will not be renewed automatically.
  --no-profile                      Only valid for '--install' command, which means: do not install aliases to user profile.
  --no-color                        Do not output color text.
  --force-color                     Force output of color text. Useful for non-interactive use with the aha tool for HTML E-Mails.
  --ecc                             Specifies to use the ECC cert. Valid for '--install-cert', '--renew', '--revoke', '--to-pkcs12' and '--create-csr'
  --csr <file>                      Specifies the input csr.
  --pre-hook <command>              Command to be run before obtaining any certificates.
  --post-hook <command>             Command to be run after attempting to obtain/renew certificates. Runs regardless of whether obtain/renew succeeded or failed.
  --renew-hook <command>            Command to be run after each successfully renewed certificate.
  --deploy-hook <hookname>          The hook file to deploy cert
  --ocsp, --ocsp-must-staple        Generate OCSP-Must-Staple extension.
  --always-force-new-domain-key     Generate new domain key on renewal. Otherwise, the domain key is not changed by default.
  --auto-upgrade [0|1]              Valid for '--upgrade' command, indicating whether to upgrade automatically in future. Defaults to 1 if argument is omitted.
  --listen-v4                       Force standalone/tls server to listen at ipv4.
  --listen-v6                       Force standalone/tls server to listen at ipv6.
  --openssl-bin <file>              Specifies a custom openssl bin location.
  --use-wget                        Force to use wget, if you have both curl and wget installed.
  --yes-I-know-dns-manual-mode-enough-go-ahead-please  Force use of dns manual mode.
                                    See:  $_DNS_MANUAL_WIKI

  -b, --branch <branch>             Only valid for '--upgrade' command, specifies the branch name to upgrade to.
  --notify-level <0|1|2|3>          Set the notification level:  Default value is $NOTIFY_LEVEL_DEFAULT.
                                    0: disabled, no notification will be sent.
                                    1: send notifications only when there is an error.
                                    2: send notifications when a cert is successfully renewed, or there is an error.
                                    3: send notifications when a cert is skipped, renewed, or error.
  --notify-mode <0|1>               Set notification mode. Default value is $NOTIFY_MODE_DEFAULT.
                                    0: Bulk mode. Send all the domain's notifications in one message(mail).
                                    1: Cert mode. Send a message for every single cert.
  --notify-hook <hookname>          Set the notify hook
  --revoke-reason <0-10>            The reason for revocation, can be used in conjunction with the '--revoke' command.
                                    See: $_REVOKE_WIKI

  --password <password>             Add a password to exported pfx file. Use with --to-pkcs12.


"
}

installOnline() {
  _info "Installing from online archive."

  _branch="$BRANCH"
  if [ -z "$_branch" ]; then
    _branch="master"
  fi

  target="$PROJECT/archive/$_branch.tar.gz"
  _info "Downloading $target"
  localname="$_branch.tar.gz"
  if ! _get "$target" >$localname; then
    _err "Download error."
    return 1
  fi
  (
    _info "Extracting $localname"
    if ! (tar xzf $localname || gtar xzf $localname); then
      _err "Extraction error."
      exit 1
    fi

    cd "$PROJECT_NAME-$_branch"
    chmod +x $PROJECT_ENTRY
    if ./$PROJECT_ENTRY --install "$@"; then
      _info "Install success!"
      _initpath
      _saveaccountconf "UPGRADE_HASH" "$(_getUpgradeHash)"
    fi

    cd ..

    rm -rf "$PROJECT_NAME-$_branch"
    rm -f "$localname"
  )
}

_getRepoHash() {
  _hash_path=$1
  shift
  _hash_url="https://api.github.com/repos/acmesh-official/$PROJECT_NAME/git/refs/$_hash_path"
  _get $_hash_url | tr -d "\r\n" | tr '{},' '\n\n\n' | grep '"sha":' | cut -d '"' -f 4
}

_getUpgradeHash() {
  _b="$BRANCH"
  if [ -z "$_b" ]; then
    _b="master"
  fi
  _hash=$(_getRepoHash "heads/$_b")
  if [ -z "$_hash" ]; then _hash=$(_getRepoHash "tags/$_b"); fi
  echo $_hash
}

upgrade() {
  if (
    _initpath
    [ -z "$FORCE" ] && [ "$(_getUpgradeHash)" = "$(_readaccountconf "UPGRADE_HASH")" ] && _info "Already uptodate!" && exit 0
    export LE_WORKING_DIR
    cd "$LE_WORKING_DIR"
    installOnline "--nocron" "--noprofile"
  ); then
    _info "Upgrade success!"
    exit 0
  else
    _err "Upgrade failed!"
    exit 1
  fi
}

_processAccountConf() {
  if [ "$_useragent" ]; then
    _saveaccountconf "USER_AGENT" "$_useragent"
  elif [ "$USER_AGENT" ] && [ "$USER_AGENT" != "$DEFAULT_USER_AGENT" ]; then
    _saveaccountconf "USER_AGENT" "$USER_AGENT"
  fi

  if [ "$_openssl_bin" ]; then
    _saveaccountconf "ACME_OPENSSL_BIN" "$_openssl_bin"
  elif [ "$ACME_OPENSSL_BIN" ] && [ "$ACME_OPENSSL_BIN" != "$DEFAULT_OPENSSL_BIN" ]; then
    _saveaccountconf "ACME_OPENSSL_BIN" "$ACME_OPENSSL_BIN"
  fi

  if [ "$_auto_upgrade" ]; then
    _saveaccountconf "AUTO_UPGRADE" "$_auto_upgrade"
  elif [ "$AUTO_UPGRADE" ]; then
    _saveaccountconf "AUTO_UPGRADE" "$AUTO_UPGRADE"
  fi

  if [ "$_use_wget" ]; then
    _saveaccountconf "ACME_USE_WGET" "$_use_wget"
  elif [ "$ACME_USE_WGET" ]; then
    _saveaccountconf "ACME_USE_WGET" "$ACME_USE_WGET"
  fi

}

_checkSudo() {
  if [ "$SUDO_GID" ] && [ "$SUDO_COMMAND" ] && [ "$SUDO_USER" ] && [ "$SUDO_UID" ]; then
    if [ "$SUDO_USER" = "root" ] && [ "$SUDO_UID" = "0" ]; then
      #it's root using sudo, no matter it's using sudo or not, just fine
      return 0
    fi
    if [ -n "$SUDO_COMMAND" ]; then
      #it's a normal user doing "sudo su", or `sudo -i` or `sudo -s`, or `sudo su acmeuser1`
      _endswith "$SUDO_COMMAND" /bin/su || _contains "$SUDO_COMMAND" "/bin/su " || grep "^$SUDO_COMMAND\$" /etc/shells >/dev/null 2>&1
      return $?
    fi
    #otherwise
    return 1
  fi
  return 0
}

#server  #keylength
_selectServer() {
  _server="$1"
  _skeylength="$2"
  _server_lower="$(echo "$_server" | _lower_case)"
  _sindex=0
  for snames in $CA_NAMES; do
    snames="$(echo "$snames" | _lower_case)"
    _sindex="$(_math $_sindex + 1)"
    _debug2 "_selectServer try snames" "$snames"
    for sname in $(echo "$snames" | tr ',' ' '); do
      if [ "$_server_lower" = "$sname" ]; then
        _debug2 "_selectServer match $sname"
        _serverdir="$(_getfield "$CA_SERVERS" $_sindex)"
        if [ "$_serverdir" = "$CA_SSLCOM_RSA" ] && _isEccKey "$_skeylength"; then
          _serverdir="$CA_SSLCOM_ECC"
        fi
        _debug "Selected server: $_serverdir"
        ACME_DIRECTORY="$_serverdir"
        export ACME_DIRECTORY
        return
      fi
    done
  done
  ACME_DIRECTORY="$_server"
  export ACME_DIRECTORY
}

#url
_getCAShortName() {
  caurl="$1"
  if [ -z "$caurl" ]; then
    caurl="$DEFAULT_CA"
  fi
  if [ "$CA_SSLCOM_ECC" = "$caurl" ]; then
    caurl="$CA_SSLCOM_RSA" #just hack to get the short name
  fi
  caurl_lower="$(echo $caurl | _lower_case)"
  _sindex=0
  for surl in $(echo "$CA_SERVERS" | _lower_case | tr , ' '); do
    _sindex="$(_math $_sindex + 1)"
    if [ "$caurl_lower" = "$surl" ]; then
      _nindex=0
      for snames in $CA_NAMES; do
        _nindex="$(_math $_nindex + 1)"
        if [ $_nindex -ge $_sindex ]; then
          _getfield "$snames" 1
          return
        fi
      done
    fi
  done
  echo "$caurl"
}

#set default ca to $ACME_DIRECTORY
setdefaultca() {
  if [ -z "$ACME_DIRECTORY" ]; then
    _err "Please give a --server parameter."
    return 1
  fi
  _saveaccountconf "DEFAULT_ACME_SERVER" "$ACME_DIRECTORY"
  _info "Changed default CA to: $(__green "$ACME_DIRECTORY")"
}

_process() {
  _CMD=""
  _domain=""
  _altdomains="$NO_VALUE"
  _webroot=""
  _challenge_alias=""
  _keylength=""
  _accountkeylength=""
  _cert_file=""
  _key_file=""
  _ca_file=""
  _fullchain_file=""
  _reloadcmd=""
  _password=""
  _accountconf=""
  _useragent=""
  _accountemail=""
  _accountkey=""
  _certhome=""
  _confighome=""
  _httpport=""
  _tlsport=""
  _dnssleep=""
  _listraw=""
  _stopRenewOnError=""
  #_insecure=""
  _ca_bundle=""
  _ca_path=""
  _nocron=""
  _noprofile=""
  _ecc=""
  _csr=""
  _pre_hook=""
  _post_hook=""
  _renew_hook=""
  _deploy_hook=""
  _logfile=""
  _log=""
  _local_address=""
  _log_level=""
  _auto_upgrade=""
  _listen_v4=""
  _listen_v6=""
  _openssl_bin=""
  _syslog=""
  _use_wget=""
  _server=""
  _notify_hook=""
  _notify_level=""
  _notify_mode=""
  _revoke_reason=""
  _eab_kid=""
  _eab_hmac_key=""
  _preferred_chain=""
  while [ ${#} -gt 0 ]; do
    case "${1}" in

    --help | -h)
      showhelp
      return
      ;;
    --version | -v)
      version
      return
      ;;
    --install)
      _CMD="install"
      ;;
    --install-online)
      shift
      installOnline "$@"
      return
      ;;
    --uninstall)
      _CMD="uninstall"
      ;;
    --upgrade)
      _CMD="upgrade"
      ;;
    --issue)
      _CMD="issue"
      ;;
    --deploy)
      _CMD="deploy"
      ;;
    --sign-csr | --signcsr)
      _CMD="signcsr"
      ;;
    --show-csr | --showcsr)
      _CMD="showcsr"
      ;;
    -i | --install-cert | --installcert)
      _CMD="installcert"
      ;;
    --renew | -r)
      _CMD="renew"
      ;;
    --renew-all | --renewAll | --renewall)
      _CMD="renewAll"
      ;;
    --revoke)
      _CMD="revoke"
      ;;
    --remove)
      _CMD="remove"
      ;;
    --list)
      _CMD="list"
      ;;
    --install-cronjob | --installcronjob)
      _CMD="installcronjob"
      ;;
    --uninstall-cronjob | --uninstallcronjob)
      _CMD="uninstallcronjob"
      ;;
    --cron)
      _CMD="cron"
      ;;
    --to-pkcs12 | --to-pkcs | --toPkcs)
      _CMD="toPkcs"
      ;;
    --to-pkcs8 | --toPkcs8)
      _CMD="toPkcs8"
      ;;
    --create-account-key | --createAccountKey | --createaccountkey | -cak)
      _CMD="createAccountKey"
      ;;
    --create-domain-key | --createDomainKey | --createdomainkey | -cdk)
      _CMD="createDomainKey"
      ;;
    -ccr | --create-csr | --createCSR | --createcsr)
      _CMD="createCSR"
      ;;
    --deactivate)
      _CMD="deactivate"
      ;;
    --update-account | --updateaccount)
      _CMD="updateaccount"
      ;;
    --register-account | --registeraccount)
      _CMD="registeraccount"
      ;;
    --deactivate-account)
      _CMD="deactivateaccount"
      ;;
    --set-notify)
      _CMD="setnotify"
      ;;
    --set-default-ca)
      _CMD="setdefaultca"
      ;;
    -d | --domain)
      _dvalue="$2"

      if [ "$_dvalue" ]; then
        if _startswith "$_dvalue" "-"; then
          _err "'$_dvalue' is not a valid domain for parameter '$1'"
          return 1
        fi
        if _is_idn "$_dvalue" && ! _exists idn; then
          _err "It seems that $_dvalue is an IDN( Internationalized Domain Names), please install 'idn' command first."
          return 1
        fi

        if [ -z "$_domain" ]; then
          _domain="$_dvalue"
        else
          if [ "$_altdomains" = "$NO_VALUE" ]; then
            _altdomains="$_dvalue"
          else
            _altdomains="$_altdomains,$_dvalue"
          fi
        fi
      fi

      shift
      ;;

    -f | --force)
      FORCE="1"
      ;;
    --staging | --test)
      STAGE="1"
      ;;
    --server)
      _server="$2"
      shift
      ;;
    --debug)
      if [ -z "$2" ] || _startswith "$2" "-"; then
        DEBUG="$DEBUG_LEVEL_DEFAULT"
      else
        DEBUG="$2"
        shift
      fi
      ;;
    --output-insecure)
      export OUTPUT_INSECURE=1
      ;;
    -w | --webroot)
      wvalue="$2"
      if [ -z "$_webroot" ]; then
        _webroot="$wvalue"
      else
        _webroot="$_webroot,$wvalue"
      fi
      shift
      ;;
    --challenge-alias)
      cvalue="$2"
      _challenge_alias="$_challenge_alias$cvalue,"
      shift
      ;;
    --domain-alias)
      cvalue="$DNS_ALIAS_PREFIX$2"
      _challenge_alias="$_challenge_alias$cvalue,"
      shift
      ;;
    --standalone)
      wvalue="$NO_VALUE"
      if [ -z "$_webroot" ]; then
        _webroot="$wvalue"
      else
        _webroot="$_webroot,$wvalue"
      fi
      ;;
    --alpn)
      wvalue="$W_ALPN"
      if [ -z "$_webroot" ]; then
        _webroot="$wvalue"
      else
        _webroot="$_webroot,$wvalue"
      fi
      ;;
    --stateless)
      wvalue="$MODE_STATELESS"
      if [ -z "$_webroot" ]; then
        _webroot="$wvalue"
      else
        _webroot="$_webroot,$wvalue"
      fi
      ;;
    --local-address)
      lvalue="$2"
      _local_address="$_local_address$lvalue,"
      shift
      ;;
    --apache)
      wvalue="apache"
      if [ -z "$_webroot" ]; then
        _webroot="$wvalue"
      else
        _webroot="$_webroot,$wvalue"
      fi
      ;;
    --nginx)
      wvalue="$NGINX"
      if [ "$2" ] && ! _startswith "$2" "-"; then
        wvalue="$NGINX$2"
        shift
      fi
      if [ -z "$_webroot" ]; then
        _webroot="$wvalue"
      else
        _webroot="$_webroot,$wvalue"
      fi
      ;;
    --dns)
      wvalue="$W_DNS"
      if [ "$2" ] && ! _startswith "$2" "-"; then
        wvalue="$2"
        shift
      fi
      if [ -z "$_webroot" ]; then
        _webroot="$wvalue"
      else
        _webroot="$_webroot,$wvalue"
      fi
      ;;
    --dnssleep)
      _dnssleep="$2"
      Le_DNSSleep="$_dnssleep"
      shift
      ;;
    --keylength | -k)
      _keylength="$2"
      shift
      ;;
    -ak | --accountkeylength)
      _accountkeylength="$2"
      shift
      ;;
    --cert-file | --certpath)
      _cert_file="$2"
      shift
      ;;
    --key-file | --keypath)
      _key_file="$2"
      shift
      ;;
    --ca-file | --capath)
      _ca_file="$2"
      shift
      ;;
    --fullchain-file | --fullchainpath)
      _fullchain_file="$2"
      shift
      ;;
    --reloadcmd | --reloadCmd)
      _reloadcmd="$2"
      shift
      ;;
    --password)
      _password="$2"
      shift
      ;;
    --accountconf)
      _accountconf="$2"
      ACCOUNT_CONF_PATH="$_accountconf"
      shift
      ;;
    --home)
      LE_WORKING_DIR="$2"
      shift
      ;;
    --cert-home | --certhome)
      _certhome="$2"
      CERT_HOME="$_certhome"
      shift
      ;;
    --config-home)
      _confighome="$2"
      LE_CONFIG_HOME="$_confighome"
      shift
      ;;
    --useragent)
      _useragent="$2"
      USER_AGENT="$_useragent"
      shift
      ;;
    -m | --email | --accountemail)
      _accountemail="$2"
      export ACCOUNT_EMAIL="$_accountemail"
      shift
      ;;
    --accountkey)
      _accountkey="$2"
      ACCOUNT_KEY_PATH="$_accountkey"
      shift
      ;;
    --days)
      _days="$2"
      Le_RenewalDays="$_days"
      shift
      ;;
    --httpport)
      _httpport="$2"
      Le_HTTPPort="$_httpport"
      shift
      ;;
    --tlsport)
      _tlsport="$2"
      Le_TLSPort="$_tlsport"
      shift
      ;;
    --listraw)
      _listraw="raw"
      ;;
    -se | --stop-renew-on-error | --stopRenewOnError | --stoprenewonerror)
      _stopRenewOnError="1"
      ;;
    --insecure)
      #_insecure="1"
      HTTPS_INSECURE="1"
      ;;
    --ca-bundle)
      _ca_bundle="$(_readlink "$2")"
      CA_BUNDLE="$_ca_bundle"
      shift
      ;;
    --ca-path)
      _ca_path="$2"
      CA_PATH="$_ca_path"
      shift
      ;;
    --no-cron | --nocron)
      _nocron="1"
      ;;
    --no-profile | --noprofile)
      _noprofile="1"
      ;;
    --no-color)
      export ACME_NO_COLOR=1
      ;;
    --force-color)
      export ACME_FORCE_COLOR=1
      ;;
    --ecc)
      _ecc="isEcc"
      ;;
    --csr)
      _csr="$2"
      shift
      ;;
    --pre-hook)
      _pre_hook="$2"
      shift
      ;;
    --post-hook)
      _post_hook="$2"
      shift
      ;;
    --renew-hook)
      _renew_hook="$2"
      shift
      ;;
    --deploy-hook)
      if [ -z "$2" ] || _startswith "$2" "-"; then
        _usage "Please specify a value for '--deploy-hook'"
        return 1
      fi
      _deploy_hook="$_deploy_hook$2,"
      shift
      ;;
    --ocsp-must-staple | --ocsp)
      Le_OCSP_Staple="1"
      ;;
    --always-force-new-domain-key)
      if [ -z "$2" ] || _startswith "$2" "-"; then
        Le_ForceNewDomainKey=1
      else
        Le_ForceNewDomainKey="$2"
        shift
      fi
      ;;
    --yes-I-know-dns-manual-mode-enough-go-ahead-please)
      export FORCE_DNS_MANUAL=1
      ;;
    --log | --logfile)
      _log="1"
      _logfile="$2"
      if _startswith "$_logfile" '-'; then
        _logfile=""
      else
        shift
      fi
      LOG_FILE="$_logfile"
      if [ -z "$LOG_LEVEL" ]; then
        LOG_LEVEL="$DEFAULT_LOG_LEVEL"
      fi
      ;;
    --log-level)
      _log_level="$2"
      LOG_LEVEL="$_log_level"
      shift
      ;;
    --syslog)
      if ! _startswith "$2" '-'; then
        _syslog="$2"
        shift
      fi
      if [ -z "$_syslog" ]; then
        _syslog="$SYSLOG_LEVEL_DEFAULT"
      fi
      ;;
    --auto-upgrade)
      _auto_upgrade="$2"
      if [ -z "$_auto_upgrade" ] || _startswith "$_auto_upgrade" '-'; then
        _auto_upgrade="1"
      else
        shift
      fi
      AUTO_UPGRADE="$_auto_upgrade"
      ;;
    --listen-v4)
      _listen_v4="1"
      Le_Listen_V4="$_listen_v4"
      ;;
    --listen-v6)
      _listen_v6="1"
      Le_Listen_V6="$_listen_v6"
      ;;
    --openssl-bin)
      _openssl_bin="$2"
      ACME_OPENSSL_BIN="$_openssl_bin"
      shift
      ;;
    --use-wget)
      _use_wget="1"
      ACME_USE_WGET="1"
      ;;
    --branch | -b)
      export BRANCH="$2"
      shift
      ;;
    --notify-hook)
      _nhook="$2"
      if _startswith "$_nhook" "-"; then
        _err "'$_nhook' is not a hook name for '$1'"
        return 1
      fi
      if [ "$_notify_hook" ]; then
        _notify_hook="$_notify_hook,$_nhook"
      else
        _notify_hook="$_nhook"
      fi
      shift
      ;;
    --notify-level)
      _nlevel="$2"
      if _startswith "$_nlevel" "-"; then
        _err "'$_nlevel' is not a integer for '$1'"
        return 1
      fi
      _notify_level="$_nlevel"
      shift
      ;;
    --notify-mode)
      _nmode="$2"
      if _startswith "$_nmode" "-"; then
        _err "'$_nmode' is not a integer for '$1'"
        return 1
      fi
      _notify_mode="$_nmode"
      shift
      ;;
    --revoke-reason)
      _revoke_reason="$2"
      if _startswith "$_revoke_reason" "-"; then
        _err "'$_revoke_reason' is not a integer for '$1'"
        return 1
      fi
      shift
      ;;
    --eab-kid)
      _eab_kid="$2"
      shift
      ;;
    --eab-hmac-key)
      _eab_hmac_key="$2"
      shift
      ;;
    --preferred-chain)
      _preferred_chain="$2"
      shift
      ;;
    *)
      _err "Unknown parameter : $1"
      return 1
      ;;
    esac

    shift 1
  done

  if [ "$_server" ]; then
    _selectServer "$_server" "${_ecc:-$_keylength}"
  fi

  if [ "${_CMD}" != "install" ]; then
    if [ "$__INTERACTIVE" ] && ! _checkSudo; then
      if [ -z "$FORCE" ]; then
        #Use "echo" here, instead of _info. it's too early
        echo "It seems that you are using sudo, please read this link first:"
        echo "$_SUDO_WIKI"
        return 1
      fi
    fi
    __initHome
    if [ "$_log" ]; then
      if [ -z "$_logfile" ]; then
        _logfile="$DEFAULT_LOG_FILE"
      fi
    fi
    if [ "$_logfile" ]; then
      _saveaccountconf "LOG_FILE" "$_logfile"
      LOG_FILE="$_logfile"
    fi

    if [ "$_log_level" ]; then
      _saveaccountconf "LOG_LEVEL" "$_log_level"
      LOG_LEVEL="$_log_level"
    fi

    if [ "$_syslog" ]; then
      if _exists logger; then
        if [ "$_syslog" = "0" ]; then
          _clearaccountconf "SYS_LOG"
        else
          _saveaccountconf "SYS_LOG" "$_syslog"
        fi
        SYS_LOG="$_syslog"
      else
        _err "The 'logger' command is not found, can not enable syslog."
        _clearaccountconf "SYS_LOG"
        SYS_LOG=""
      fi
    fi

    _processAccountConf
  fi

  _debug2 LE_WORKING_DIR "$LE_WORKING_DIR"

  if [ "$DEBUG" ]; then
    version
    if [ "$_server" ]; then
      _debug "Using server: $_server"
    fi
  fi
  _debug "Running cmd: ${_CMD}"
  case "${_CMD}" in
  install) install "$_nocron" "$_confighome" "$_noprofile" "$_accountemail" ;;
  uninstall) uninstall "$_nocron" ;;
  upgrade) upgrade ;;
  issue)
    issue "$_webroot" "$_domain" "$_altdomains" "$_keylength" "$_cert_file" "$_key_file" "$_ca_file" "$_reloadcmd" "$_fullchain_file" "$_pre_hook" "$_post_hook" "$_renew_hook" "$_local_address" "$_challenge_alias" "$_preferred_chain"
    ;;
  deploy)
    deploy "$_domain" "$_deploy_hook" "$_ecc"
    ;;
  signcsr)
    signcsr "$_csr" "$_webroot" "$_cert_file" "$_key_file" "$_ca_file" "$_reloadcmd" "$_fullchain_file" "$_pre_hook" "$_post_hook" "$_renew_hook" "$_local_address" "$_challenge_alias" "$_preferred_chain"
    ;;
  showcsr)
    showcsr "$_csr" "$_domain"
    ;;
  installcert)
    installcert "$_domain" "$_cert_file" "$_key_file" "$_ca_file" "$_reloadcmd" "$_fullchain_file" "$_ecc"
    ;;
  renew)
    renew "$_domain" "$_ecc"
    ;;
  renewAll)
    renewAll "$_stopRenewOnError"
    ;;
  revoke)
    revoke "$_domain" "$_ecc" "$_revoke_reason"
    ;;
  remove)
    remove "$_domain" "$_ecc"
    ;;
  deactivate)
    deactivate "$_domain,$_altdomains"
    ;;
  registeraccount)
    registeraccount "$_accountkeylength" "$_eab_kid" "$_eab_hmac_key"
    ;;
  updateaccount)
    updateaccount
    ;;
  deactivateaccount)
    deactivateaccount
    ;;
  list)
    list "$_listraw" "$_domain"
    ;;
  installcronjob) installcronjob "$_confighome" ;;
  uninstallcronjob) uninstallcronjob ;;
  cron) cron ;;
  toPkcs)
    toPkcs "$_domain" "$_password" "$_ecc"
    ;;
  toPkcs8)
    toPkcs8 "$_domain" "$_ecc"
    ;;
  createAccountKey)
    createAccountKey "$_accountkeylength"
    ;;
  createDomainKey)
    createDomainKey "$_domain" "$_keylength"
    ;;
  createCSR)
    createCSR "$_domain" "$_altdomains" "$_ecc"
    ;;
  setnotify)
    setnotify "$_notify_hook" "$_notify_level" "$_notify_mode"
    ;;
  setdefaultca)
    setdefaultca
    ;;
  *)
    if [ "$_CMD" ]; then
      _err "Invalid command: $_CMD"
    fi
    showhelp
    return 1
    ;;
  esac
  _ret="$?"
  if [ "$_ret" != "0" ]; then
    return $_ret
  fi

  if [ "${_CMD}" = "install" ]; then
    if [ "$_log" ]; then
      if [ -z "$LOG_FILE" ]; then
        LOG_FILE="$DEFAULT_LOG_FILE"
      fi
      _saveaccountconf "LOG_FILE" "$LOG_FILE"
    fi

    if [ "$_log_level" ]; then
      _saveaccountconf "LOG_LEVEL" "$_log_level"
    fi

    if [ "$_syslog" ]; then
      if _exists logger; then
        if [ "$_syslog" = "0" ]; then
          _clearaccountconf "SYS_LOG"
        else
          _saveaccountconf "SYS_LOG" "$_syslog"
        fi
      else
        _err "The 'logger' command is not found, can not enable syslog."
        _clearaccountconf "SYS_LOG"
        SYS_LOG=""
      fi
    fi

    _processAccountConf
  fi

}

main() {
  [ -z "$1" ] && showhelp && return
  if _startswith "$1" '-'; then _process "$@"; else "$@"; fi
}

main "$@"
