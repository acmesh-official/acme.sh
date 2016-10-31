#!/usr/bin/env sh

VER=2.6.2

PROJECT_NAME="acme.sh"

PROJECT_ENTRY="acme.sh"

PROJECT="https://github.com/Neilpang/$PROJECT_NAME"

DEFAULT_INSTALL_HOME="$HOME/.$PROJECT_NAME"
_SCRIPT_="$0"

_SUB_FOLDERS="dnsapi deploy"

DEFAULT_CA="https://acme-v01.api.letsencrypt.org"
DEFAULT_AGREEMENT="https://letsencrypt.org/documents/LE-SA-v1.1.1-August-1-2016.pdf"

DEFAULT_USER_AGENT="$PROJECT_ENTRY client v$VER : $PROJECT"
DEFAULT_ACCOUNT_EMAIL=""

STAGE_CA="https://acme-staging.api.letsencrypt.org"

VTYPE_HTTP="http-01"
VTYPE_DNS="dns-01"
VTYPE_TLS="tls-sni-01"
VTYPE_TLS2="tls-sni-02"

LOCAL_ANY_ADDRESS="0.0.0.0"

MAX_RENEW=60

DEFAULT_DNS_SLEEP=120

NO_VALUE="no"

W_TLS="tls"

STATE_VERIFIED="verified_ok"

BEGIN_CSR="-----BEGIN CERTIFICATE REQUEST-----"
END_CSR="-----END CERTIFICATE REQUEST-----"

BEGIN_CERT="-----BEGIN CERTIFICATE-----"
END_CERT="-----END CERTIFICATE-----"

RENEW_SKIP=2

ECC_SEP="_"
ECC_SUFFIX="${ECC_SEP}ecc"

LOG_LEVEL_1=1
LOG_LEVEL_2=2
LOG_LEVEL_3=3
DEFAULT_LOG_LEVEL="$LOG_LEVEL_1"

_DEBUG_WIKI="https://github.com/Neilpang/acme.sh/wiki/How-to-debug-acme.sh"

__INTERACTIVE=""
if [ -t 1 ] ; then
  __INTERACTIVE="1"
fi

__green() {
  if [ "$__INTERACTIVE" ] ; then
    printf '\033[1;31;32m'
  fi
  printf -- "$1"
  if [ "$__INTERACTIVE" ] ; then
    printf '\033[0m'
  fi
}

__red() {
  if [ "$__INTERACTIVE" ] ; then
    printf '\033[1;31;40m'
  fi
  printf -- "$1"
  if [ "$__INTERACTIVE" ] ; then
    printf '\033[0m'
  fi
}


_printargs() {
  if [ -z "$2" ] ; then
    printf -- "[$(date)] $1"
  else
    printf -- "[$(date)] $1='$2'"
  fi
  printf "\n"
}


_log() {
  [ -z "$LOG_FILE" ] && return
  _printargs "$@" >> $LOG_FILE
}

_info() {
  _log "$@"
  _printargs "$@"
}


_err() {
  _log "$@"
  printf -- "[$(date)] " >&2
  if [ -z "$2" ] ; then
    __red "$1" >&2
  else
    __red "$1='$2'" >&2
  fi
  printf "\n" >&2
  return 1
}

_usage() {
  __red "$@"  >&2
  printf "\n" >&2
}


_debug() {
  if [ -z "$LOG_LEVEL" ] || [ "$LOG_LEVEL" -ge "$LOG_LEVEL_1" ] ; then
    _log "$@"
  fi
  if [ -z "$DEBUG" ] ; then
    return
  fi
  _printargs "$@" >&2
}

_debug2() {
  if [ "$LOG_LEVEL" ] && [ "$LOG_LEVEL" -ge "$LOG_LEVEL_2" ] ; then
    _log "$@"
  fi
  if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ] ; then
    _debug "$@"
  fi
}

_debug3() {
  if [ "$LOG_LEVEL" ] && [ "$LOG_LEVEL" -ge "$LOG_LEVEL_3" ] ; then
    _log "$@"
  fi
  if [ "$DEBUG" ] && [ "$DEBUG" -ge "3" ] ; then
    _debug "$@"
  fi
}

_startswith(){
  _str="$1"
  _sub="$2"
  echo "$_str" | grep "^$_sub" >/dev/null 2>&1
}

_endswith(){
  _str="$1"
  _sub="$2"
  echo "$_str" | grep -- "$_sub\$" >/dev/null 2>&1
}

_contains(){
  _str="$1"
  _sub="$2"
  echo "$_str" | grep -- "$_sub" >/dev/null 2>&1
}

_hasfield() {
  _str="$1"
  _field="$2"
  _sep="$3"
  if [ -z "$_field" ] ; then
    _usage "Usage: str field  [sep]"
    return 1
  fi
  
  if [ -z "$_sep" ] ; then
    _sep=","
  fi
  
  for f in $(echo "$_str" |  tr ',' ' ') ; do
    if [ "$f" = "$_field" ] ; then
      _debug2 "'$_str' contains '$_field'"
      return 0 #contains ok
    fi
  done
  _debug2 "'$_str' does not contain '$_field'"
  return 1 #not contains 
}

_getfield(){
  _str="$1"
  _findex="$2"
  _sep="$3"
  
  if [ -z "$_findex" ] ; then
    _usage "Usage: str field  [sep]"
    return 1
  fi
  
  if [ -z "$_sep" ] ; then
    _sep=","
  fi

  _ffi=$_findex
  while [ "$_ffi" -gt "0" ]
  do
    _fv="$(echo "$_str" |  cut -d $_sep -f $_ffi)"
    if [ "$_fv" ] ; then
      printf -- "%s" "$_fv"
      return 0
    fi
    _ffi="$(_math $_ffi - 1)"
  done
  
  printf -- "%s" "$_str"

}

_exists(){
  cmd="$1"
  if [ -z "$cmd" ] ; then
    _usage "Usage: _exists cmd"
    return 1
  fi
  if type command >/dev/null 2>&1 ; then
    command -v "$cmd" >/dev/null 2>&1
  else
    type "$cmd" >/dev/null 2>&1
  fi
  ret="$?"
  _debug3 "$cmd exists=$ret"
  return $ret
}

#a + b
_math(){
  expr "$@"
}

_h_char_2_dec() {
  _ch=$1
  case "${_ch}" in
    a|A)
      printf "10"
        ;;
    b|B)
      printf "11"
        ;;
    c|C)
      printf "12"
        ;;
    d|D)
      printf "13"
        ;;
    e|E)
      printf "14"
        ;;
    f|F)
      printf "15"
        ;;
    *)
      printf "%s" "$_ch"
        ;;
  esac

}


_URGLY_PRINTF=""
if [ "$(printf '\x41')" != 'A' ] ; then
  _URGLY_PRINTF=1
fi

_h2b() {
  hex=$(cat)
  i=1
  j=2
  if _exists let ; then
    uselet="1"
  fi
  _debug3 uselet "$uselet"
  _debug3 _URGLY_PRINTF "$_URGLY_PRINTF"
  while true ; do
    if [ -z "$_URGLY_PRINTF" ] ; then
      h="$(printf $hex | cut -c $i-$j)"
      if [ -z "$h" ] ; then
        break;
      fi
      printf "\x$h"
    else
      ic="$(printf $hex | cut -c $i)"
      jc="$(printf $hex | cut -c $j)"
      if [ -z "$ic$jc" ] ; then
        break;
      fi
      ic="$(_h_char_2_dec "$ic")"
      jc="$(_h_char_2_dec "$jc")"
      printf '\'"$(printf %o "$(_math $ic \* 16 + $jc)")"
    fi
    if [ "$uselet" ] ; then
      let "i+=2" >/dev/null
      let "j+=2" >/dev/null
    else
      i="$(_math $i + 2)"
      j="$(_math $j + 2)"
    fi    
  done
}

#options file
_sed_i() {
  options="$1"
  filename="$2"
  if [ -z "$filename" ] ; then
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
    echo "$text" | sed "$options" > "$filename"
  fi
}

_egrep_o() {
  if _contains "$(egrep -o 2>&1)" "egrep: illegal option -- o" ; then
    sed -n 's/.*\('"$1"'\).*/\1/p'
  else
    egrep -o "$1"
  fi
}

#Usage: file startline endline
_getfile() {
  filename="$1"
  startline="$2"
  endline="$3"
  if [ -z "$endline" ] ; then
    _usage "Usage: file startline endline"
    return 1
  fi
  
  i="$(grep -n --  "$startline"  "$filename" | cut -d : -f 1)"
  if [ -z "$i" ] ; then
    _err "Can not find start line: $startline"
    return 1
  fi
  i="$(_math "$i" + 1)"
  _debug i "$i"
  
  j="$(grep -n --  "$endline"  "$filename" | cut -d : -f 1)"
  if [ -z "$j" ] ; then
    _err "Can not find end line: $endline"
    return 1
  fi
  j="$(_math "$j" - 1)"
  _debug j "$j"
  
  sed -n "$i,${j}p"  "$filename"

}

#Usage: multiline
_base64() {
  if [ "$1" ] ; then
    openssl base64 -e
  else
    openssl base64 -e | tr -d '\r\n'
  fi
}

#Usage: multiline
_dbase64() {
  if [ "$1" ] ; then
    openssl base64 -d -A
  else
    openssl base64 -d
  fi
}

#Usage: hashalg  [outputhex]
#Output Base64-encoded digest
_digest() {
  alg="$1"
  if [ -z "$alg" ] ; then
    _usage "Usage: _digest hashalg"
    return 1
  fi
  
  outputhex="$2"
  
  if [ "$alg" = "sha256" ] || [ "$alg" = "sha1" ]; then
    if [ "$outputhex" ] ; then
      openssl dgst -$alg -hex | cut -d = -f 2 | tr -d ' '
    else
      openssl dgst -$alg -binary | _base64
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
  if [ -z "$alg" ] ; then
    _usage "Usage: _sign keyfile hashalg"
    return 1
  fi
  
  _sign_openssl="openssl   dgst -sign $keyfile "
  if [ "$alg" = "sha256" ] ; then
    _sign_openssl="$_sign_openssl -$alg"
  else
    _err "$alg is not supported yet"
    return 1
  fi
  
  if grep "BEGIN RSA PRIVATE KEY" "$keyfile" > /dev/null 2>&1 ; then
    $_sign_openssl | _base64
  elif grep "BEGIN EC PRIVATE KEY" "$keyfile" > /dev/null 2>&1 ; then
    _signedECText="$($_sign_openssl | openssl asn1parse -inform DER)"
    _debug3 "_signedECText" "$_signedECText"
    _ec_r="$(echo "$_signedECText" | _head_n 2 | _tail_n 1 | cut -d : -f 4 | tr -d "\r\n")"
    _debug3 "_ec_r" "$_ec_r"
    _ec_s="$(echo "$_signedECText" | _head_n 3 | _tail_n 1 | cut -d : -f 4 | tr -d "\r\n")"
    _debug3 "_ec_s" "$_ec_s"
    printf "%s" "$_ec_r$_ec_s" | _h2b | _base64
  else
    _err "Unknown key file format."
    return 1
  fi
  
}

#keylength
_isEccKey() {
  _length="$1"

  if [ -z "$_length" ] ;then
    return 1
  fi

  [ "$_length" != "1024" ] \
  && [ "$_length" != "2048" ] \
  && [ "$_length" != "3072" ] \
  && [ "$_length" != "4096" ] \
  && [ "$_length" != "8192" ]
}

# _createkey  2048|ec-256   file
_createkey() {
  length="$1"
  f="$2"
  eccname="$length"
  if _startswith "$length" "ec-" ; then
    length=$(printf $length | cut -d '-' -f 2-100)

    if [ "$length" = "256" ] ; then
      eccname="prime256v1"
    fi
    if [ "$length" = "384" ] ; then
      eccname="secp384r1"
    fi
    if [ "$length" = "521" ] ; then
      eccname="secp521r1"
    fi

  fi

  if [ -z "$length" ] ; then
     length=2048
  fi
  
  _debug "Use length $length"

  if _isEccKey "$length" ; then
    _debug "Using ec name: $eccname"
    openssl ecparam  -name $eccname -genkey 2>/dev/null > "$f"
  else
    _debug "Using RSA: $length"
    openssl genrsa $length 2>/dev/null > "$f"
  fi

  if [ "$?" != "0" ] ; then
    _err "Create key error."
    return 1
  fi
}


#domain
_is_idn() {
  _is_idn_d="$1"
  _debug2 _is_idn_d "$_is_idn_d"
  _idn_temp=$(printf "%s" "$_is_idn_d" | tr -d '[0-9]' | tr -d '[a-z]' | tr -d 'A-Z' | tr -d '.,-')
  _debug2 _idn_temp "$_idn_temp"
  [ "$_idn_temp" ]
}

#aa.com
#aa.com,bb.com,cc.com
_idn() {
  __idn_d="$1"
  if ! _is_idn "$__idn_d" ; then
    printf "%s" "$__idn_d"
    return 0
  fi
  
  if _exists idn ; then
    if _contains "$__idn_d" ',' ; then
      _i_first="1"
      for f in $(echo "$__idn_d" |  tr ',' ' ') ; do
        [ -z "$f" ] && continue
        if [ -z "$_i_first" ] ; then
          printf "%s" ","
        else
          _i_first=""
        fi
        idn "$f" | tr -d "\r\n"
      done
    else
      idn "$__idn_d" | tr -d "\r\n"
    fi
  else
    _err "Please install idn to process IDN names."
  fi
}

#_createcsr  cn  san_list  keyfile csrfile conf
_createcsr() {
  _debug _createcsr
  domain="$1"
  domainlist="$2"
  csrkey="$3"
  csr="$4"
  csrconf="$5"
  _debug2 domain "$domain"
  _debug2 domainlist "$domainlist"
  _debug2 csrkey "$csrkey"
  _debug2 csr "$csr"
  _debug2 csrconf "$csrconf"
  
  printf "[ req_distinguished_name ]\n[ req ]\ndistinguished_name = req_distinguished_name\nreq_extensions = v3_req\n[ v3_req ]\n\nkeyUsage = nonRepudiation, digitalSignature, keyEncipherment" > "$csrconf"
  
  if [ -z "$domainlist" ] || [ "$domainlist" = "$NO_VALUE" ]; then
    #single domain
    _info "Single domain" "$domain"
  else
    domainlist="$(_idn $domainlist)"
    _debug2 domainlist "$domainlist"
    if _contains "$domainlist" "," ; then
      alt="DNS:$(echo $domainlist | sed "s/,/,DNS:/g")"
    else
      alt="DNS:$domainlist"
    fi
    #multi 
    _info "Multi domain" "$alt"
    printf -- "\nsubjectAltName=$alt" >> "$csrconf"
  fi
  if [ "$Le_OCSP_Stable" ] ; then
    _savedomainconf Le_OCSP_Stable "$Le_OCSP_Stable"
    printf -- "\nbasicConstraints = CA:FALSE\n1.3.6.1.5.5.7.1.24=DER:30:03:02:01:05" >> "$csrconf"
  fi
  
  _csr_cn="$(_idn "$domain")"
  _debug2 _csr_cn "$_csr_cn"
  openssl req -new -sha256 -key "$csrkey" -subj "/CN=$_csr_cn" -config "$csrconf" -out "$csr"
}

#_signcsr key  csr  conf cert
_signcsr() {
  key="$1"
  csr="$2"
  conf="$3"
  cert="$4"
  _debug "_signcsr"
  
  _msg="$(openssl x509 -req -days 365  -in "$csr"  -signkey "$key"  -extensions v3_req -extfile "$conf" -out "$cert"  2>&1)"
  _ret="$?"
  _debug "$_msg"
  return $_ret
}

#_csrfile
_readSubjectFromCSR() {
  _csrfile="$1"
  if [ -z "$_csrfile" ] ; then
    _usage "_readSubjectFromCSR mycsr.csr"
    return 1
  fi
  openssl req  -noout  -in  "$_csrfile"  -subject | _egrep_o "CN=.*" | cut -d = -f 2 |  cut -d / -f 1 | tr -d '\n'
}

#_csrfile
#echo comma separated domain list
_readSubjectAltNamesFromCSR() {
  _csrfile="$1"
  if [ -z "$_csrfile" ] ; then
    _usage "_readSubjectAltNamesFromCSR mycsr.csr"
    return 1
  fi
  
  _csrsubj="$(_readSubjectFromCSR "$_csrfile")"
  _debug _csrsubj "$_csrsubj"
  
  _dnsAltnames="$(openssl req  -noout -text  -in  "$_csrfile" | grep "^ *DNS:.*" | tr -d ' \n')"
  _debug _dnsAltnames "$_dnsAltnames"
  
  if _contains "$_dnsAltnames," "DNS:$_csrsubj," ; then
    _debug "AltNames contains subject"
    _dnsAltnames="$(printf "%s" "$_dnsAltnames," | sed "s/DNS:$_csrsubj,//g")"
  else
    _debug "AltNames doesn't contain subject"
  fi
  
  printf "%s" "$_dnsAltnames" | sed "s/DNS://g"
}

#_csrfile 
_readKeyLengthFromCSR() {
  _csrfile="$1"
  if [ -z "$_csrfile" ] ; then
    _usage "_readKeyLengthFromCSR mycsr.csr"
    return 1
  fi
  
  _outcsr="$(openssl req  -noout -text  -in  "$_csrfile")"
  if _contains "$_outcsr" "Public Key Algorithm: id-ecPublicKey" ; then
    _debug "ECC CSR"
    echo "$_outcsr" | _egrep_o "^ *ASN1 OID:.*" | cut -d ':' -f 2 | tr -d ' '
  else
    _debug "RSA CSR"
    echo "$_outcsr" | _egrep_o "^ *Public-Key:.*" | cut -d '(' -f 2 | cut -d ' ' -f 1
  fi
}


_ss() {
  _port="$1"
  
  if _exists "ss" ; then
    _debug "Using: ss"
    ss -ntpl | grep ":$_port "
    return 0
  fi

  if _exists "netstat" ; then
    _debug "Using: netstat"
    if netstat -h 2>&1 | grep "\-p proto" >/dev/null ; then
      #for windows version netstat tool
      netstat -an -p tcp | grep "LISTENING" | grep ":$_port "
    else
      if netstat -help 2>&1 | grep "\-p protocol" >/dev/null ; then
        netstat -an -p tcp | grep LISTEN | grep ":$_port "
      elif netstat -help 2>&1 | grep -- '-P protocol' >/dev/null ; then
        #for solaris
        netstat -an -P tcp | grep "\.$_port " | grep "LISTEN"
      else
        netstat -ntpl | grep ":$_port "
      fi
    fi
    return 0
  fi

  return 1
}

#domain [password] [isEcc]
toPkcs() {
  domain="$1"
  pfxPassword="$2"
  if [ -z "$domain" ] ; then
    _usage "Usage: $PROJECT_ENTRY --toPkcs -d domain [--password pfx-password]"
    return 1
  fi

  _isEcc="$3"
  
  _initpath "$domain" "$_isEcc"

  if [ "$pfxPassword" ] ; then
    openssl pkcs12 -export -out "$CERT_PFX_PATH" -inkey "$CERT_KEY_PATH" -in "$CERT_PATH" -certfile "$CA_CERT_PATH" -password "pass:$pfxPassword"
  else
    openssl pkcs12 -export -out "$CERT_PFX_PATH" -inkey "$CERT_KEY_PATH" -in "$CERT_PATH" -certfile "$CA_CERT_PATH"
  fi
  
  if [ "$?" = "0" ] ; then
    _info "Success, Pfx is exported to: $CERT_PFX_PATH"
  fi

}

#[2048]  
createAccountKey() {
  _info "Creating account key"
  if [ -z "$1" ] ; then
    _usage "Usage: $PROJECT_ENTRY --createAccountKey --accountkeylength 2048"
    return
  fi
  
  length=$1
  
  if [ -z "$length" ] || [ "$length" = "$NO_VALUE" ] ; then
    _debug "Use default length 2048"
    length=2048
  fi
  _debug length "$length"
  _initpath

  if [ -f "$ACCOUNT_KEY_PATH" ] ; then
    _info "Account key exists, skip"
    return
  else
    #generate account key
    _createkey "$length" "$ACCOUNT_KEY_PATH"
  fi

}

#domain [length]
createDomainKey() {
  _info "Creating domain key"
  if [ -z "$1" ] ; then
    _usage "Usage: $PROJECT_ENTRY --createDomainKey -d domain.com  [ --keylength 2048 ]"
    return
  fi
  
  domain=$1
  length=$2
  
  _initpath $domain "$length"  

  if [ ! -f "$CERT_KEY_PATH" ] || ( [ "$FORCE" ] && ! [ "$IS_RENEW" ] ); then 
    _createkey "$length" "$CERT_KEY_PATH"
  else
    if [ "$IS_RENEW" ] ; then
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
  if [ -z "$1" ] ; then
    _usage "Usage: $PROJECT_ENTRY --createCSR -d domain1.com [-d domain2.com  -d domain3.com ... ]"
    return
  fi
  
  domain="$1"
  domainlist="$2"
  _isEcc="$3"
  
  _initpath "$domain" "$_isEcc"
  
  if [ -f "$CSR_PATH" ]  && [ "$IS_RENEW" ] && [ -z "$FORCE" ]; then
    _info "CSR exists, skip"
    return
  fi
  
  if [ ! -f "$CERT_KEY_PATH" ] ; then
    _err "The key file is not found: $CERT_KEY_PATH"
    _err "Please create the key file first."
    return 1
  fi
  _createcsr "$domain" "$domainlist" "$CERT_KEY_PATH" "$CSR_PATH" "$DOMAIN_SSL_CONF"
  
}

_urlencode() {
  __n=$(cat)
  echo $__n | tr '/+' '_-' | tr -d '= '
}

_time2str() {
  #BSD
  if date -u -d@$1 2>/dev/null ; then
    return
  fi
  
  #Linux
  if date -u -r $1 2>/dev/null ; then
    return
  fi
  
  #Soaris
  if _exists adb ; then
    echo $(echo "0t${1}=Y" | adb)
  fi
  
}

_normalizeJson() {
  sed "s/\" *: *\([\"{\[]\)/\":\1/g" | sed "s/^ *\([^ ]\)/\1/" | tr -d "\r\n"
}

_stat() {
  #Linux
  if stat -c '%U:%G' "$1" 2>/dev/null ; then
    return
  fi
  
  #BSD
  if stat -f  '%Su:%Sg' "$1" 2>/dev/null ; then
    return
  fi
  
  return 1; #error, 'stat' not found
}

#keyfile
_calcjwk() {
  keyfile="$1"
  if [ -z "$keyfile" ] ; then
    _usage "Usage: _calcjwk keyfile"
    return 1
  fi
  
  if [ "$JWK_HEADER" ] && [ "$__CACHED_JWK_KEY_FILE" = "$keyfile" ] ; then
    _debug2 "Use cached jwk for file: $__CACHED_JWK_KEY_FILE"
    return 0
  fi
  
  
  EC_SIGN=""
  if grep "BEGIN RSA PRIVATE KEY" "$keyfile" > /dev/null 2>&1 ; then
    _debug "RSA key"
    pub_exp=$(openssl rsa -in $keyfile  -noout -text | grep "^publicExponent:"| cut -d '(' -f 2 | cut -d 'x' -f 2 | cut -d ')' -f 1)
    if [ "${#pub_exp}" = "5" ] ; then
      pub_exp=0$pub_exp
    fi
    _debug3 pub_exp "$pub_exp"
    
    e=$(echo $pub_exp | _h2b | _base64)
    _debug3 e "$e"
    
    modulus=$(openssl rsa -in $keyfile -modulus -noout | cut -d '=' -f 2 )
    _debug3 modulus "$modulus"
    n="$(printf "%s" "$modulus"| _h2b | _base64 | _urlencode )"
    jwk='{"e": "'$e'", "kty": "RSA", "n": "'$n'"}'
    _debug3 jwk "$jwk"
    
    JWK_HEADER='{"alg": "RS256", "jwk": '$jwk'}'
    JWK_HEADERPLACE_PART1='{"nonce": "'
    JWK_HEADERPLACE_PART2='", "alg": "RS256", "jwk": '$jwk'}'
  elif grep "BEGIN EC PRIVATE KEY" "$keyfile" > /dev/null 2>&1 ; then
    _debug "EC key"
    EC_SIGN="1"
    crv="$(openssl ec  -in $keyfile  -noout -text 2>/dev/null | grep "^NIST CURVE:" | cut -d ":" -f 2 | tr -d " \r\n")"
    _debug3 crv "$crv"
    
    pubi="$(openssl ec  -in $keyfile  -noout -text 2>/dev/null | grep -n pub: | cut -d : -f 1)"
    pubi=$(_math $pubi + 1)
    _debug3 pubi "$pubi"
    
    pubj="$(openssl ec  -in $keyfile  -noout -text 2>/dev/null | grep -n "ASN1 OID:"  | cut -d : -f 1)"
    pubj=$(_math $pubj - 1)
    _debug3 pubj "$pubj"
    
    pubtext="$(openssl ec  -in $keyfile  -noout -text 2>/dev/null | sed  -n "$pubi,${pubj}p" | tr -d " \n\r")"
    _debug3 pubtext "$pubtext"
    
    xlen="$(printf "$pubtext" | tr -d ':' | wc -c)"
    xlen=$(_math $xlen / 4)
    _debug3 xlen "$xlen"

    xend=$(_math "$xlen" + 1)
    x="$(printf $pubtext | cut -d : -f 2-$xend)"
    _debug3 x "$x"
    
    x64="$(printf $x | tr -d : | _h2b | _base64 | _urlencode)"
    _debug3 x64 "$x64"

    xend=$(_math "$xend" + 1)
    y="$(printf $pubtext | cut -d : -f $xend-10000)"
    _debug3 y "$y"
    
    y64="$(printf $y | tr -d : | _h2b | _base64 | _urlencode)"
    _debug3 y64 "$y64"
   
    jwk='{"crv": "'$crv'", "kty": "EC", "x": "'$x64'", "y": "'$y64'"}'
    _debug3 jwk "$jwk"
    
    JWK_HEADER='{"alg": "ES256", "jwk": '$jwk'}'
    JWK_HEADERPLACE_PART1='{"nonce": "'
    JWK_HEADERPLACE_PART2='", "alg": "ES256", "jwk": '$jwk'}'
  else
    _err "Only RSA or EC key is supported."
    return 1
  fi

  _debug3 JWK_HEADER "$JWK_HEADER"
  __CACHED_JWK_KEY_FILE="$keyfile"
}

_time() {
  date -u "+%s"
}

_mktemp() {
  if _exists mktemp ; then
    if mktemp 2>/dev/null ; then
      return
    elif _contains "$(mktemp 2>&1)" "-t prefix" && mktemp -t "$PROJECT_NAME" 2>/dev/null ; then
      #for Mac osx
      return
    fi
  fi
  if [ -d "/tmp" ] ; then
    echo "/tmp/${PROJECT_NAME}wefADf24sf.$(_time).tmp"
    return 0
  fi
  _err "Can not create temp file."
}

_inithttp() {

  if [ -z "$HTTP_HEADER" ] || ! touch "$HTTP_HEADER" ; then
    HTTP_HEADER="$(_mktemp)"
    _debug2 HTTP_HEADER "$HTTP_HEADER"
  fi
  
  if [ "$__HTTP_INITIALIZED" ] ; then 
    if [ "$_ACME_CURL$_ACME_WGET" ] ; then
      _debug2 "Http already initialized."
      return 0
    fi
  fi
  
  if [ -z "$_ACME_CURL" ] && _exists "curl" ; then
    _ACME_CURL="curl -L --silent --dump-header $HTTP_HEADER "
    if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ] ; then
      _CURL_DUMP="$(_mktemp)"
      _ACME_CURL="$_ACME_CURL --trace-ascii $_CURL_DUMP "
    fi

    if [ "$CA_BUNDLE" ] ; then
      _ACME_CURL="$_ACME_CURL --cacert $CA_BUNDLE "
    fi

    if [ "$HTTPS_INSECURE" ] ; then
      _ACME_CURL="$_ACME_CURL --insecure  "
    fi
  fi
  
  if [ -z "$_ACME_WGET" ] && _exists "wget"; then
    _ACME_WGET="wget -q"
    if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ] ; then
      _ACME_WGET="$_ACME_WGET -d "
    fi
    if [ "$CA_BUNDLE" ] ; then
      _ACME_WGET="$_ACME_WGET --ca-certificate $CA_BUNDLE "
    fi
    if [ "$HTTPS_INSECURE" ] ; then
      _ACME_WGET="$_ACME_WGET --no-check-certificate "
    fi
  fi
  
  __HTTP_INITIALIZED=1

}


# body  url [needbase64] [POST|PUT]
_post() {
  body="$1"
  url="$2"
  needbase64="$3"
  httpmethod="$4"

  if [ -z "$httpmethod" ] ; then
    httpmethod="POST"
  fi
  _debug $httpmethod
  _debug "url" "$url"
  _debug2 "body" "$body"
  
  _inithttp
  
  if [ "$_ACME_CURL" ] ; then
    _CURL="$_ACME_CURL"
    _debug "_CURL" "$_CURL"
    if [ "$needbase64" ] ; then
      response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" --data "$body" "$url" | _base64)"
    else
      response="$($_CURL --user-agent "$USER_AGENT" -X $httpmethod -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" --data "$body" "$url" )"
    fi
    _ret="$?"
    if [ "$_ret" != "0" ] ; then
      _err "Please refer to https://curl.haxx.se/libcurl/c/libcurl-errors.html for error code: $_ret"
      if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ] ; then
        _err "Here is the curl dump log:"
        _err "$(cat "$_CURL_DUMP")"
      fi
    fi
  elif [ "$_ACME_WGET" ] ; then
    _debug "_ACME_WGET" "$_ACME_WGET"
    if [ "$needbase64" ] ; then
      if [ "$httpmethod" = "POST" ] ; then
        response="$($_ACME_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --post-data="$body" "$url" 2>"$HTTP_HEADER" | _base64)"
      else
        response="$($_ACME_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --method $httpmethod --body-data="$body" "$url" 2>"$HTTP_HEADER" | _base64)"
      fi
    else
      if [ "$httpmethod" = "POST" ] ; then
        response="$($_ACME_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --post-data="$body" "$url" 2>"$HTTP_HEADER")"
      else
        response="$($_ACME_WGET -S -O - --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --method $httpmethod --body-data="$body" "$url" 2>"$HTTP_HEADER")"
      fi
    fi
    _ret="$?"
    if [ "$_ret" = "8" ] ; then
      _ret=0
      _debug "wget returns 8, the server returns a 'Bad request' respons, lets process the response later."
    fi
    if [ "$_ret" != "0" ] ; then
      _err "Please refer to https://www.gnu.org/software/wget/manual/html_node/Exit-Status.html for error code: $_ret" 
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
  _debug GET
  url="$1"
  onlyheader="$2"
  t="$3"
  _debug url $url
  _debug "timeout" "$t"

  _inithttp

  if [ "$_ACME_CURL" ] ; then
    _CURL="$_ACME_CURL"
    if [ "$t" ] ; then
      _CURL="$_CURL --connect-timeout $t"
    fi
    _debug "_CURL" "$_CURL"
    if [ "$onlyheader" ] ; then
      $_CURL -I --user-agent "$USER_AGENT" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" $url
    else
      $_CURL    --user-agent "$USER_AGENT" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" $url
    fi
    ret=$?
    if [ "$ret" != "0" ] ; then
      _err "Please refer to https://curl.haxx.se/libcurl/c/libcurl-errors.html for error code: $ret"
      if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ] ; then
        _err "Here is the curl dump log:"
        _err "$(cat "$_CURL_DUMP")"
      fi
    fi
  elif [ "$_ACME_WGET" ] ; then
    _WGET="$_ACME_WGET"
    if [ "$t" ] ; then
      _WGET="$_WGET --timeout=$t"
    fi
    _debug "_WGET" "$_WGET"
    if [ "$onlyheader" ] ; then
      $_WGET --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" -S -O /dev/null $url 2>&1 | sed 's/^[ ]*//g'
    else
      $_WGET --user-agent="$USER_AGENT" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1"    -O - $url
    fi
    ret=$?
    if [ "$_ret" = "8" ] ; then
      _ret=0
      _debug "wget returns 8, the server returns a 'Bad request' respons, lets process the response later."
    fi
    if [ "$ret" != "0" ] ; then
      _err "Please refer to https://www.gnu.org/software/wget/manual/html_node/Exit-Status.html for error code: $ret" 
    fi
  else
    ret=$?
    _err "Neither curl nor wget is found, can not do GET."
  fi
  _debug "ret" "$ret"
  return $ret
}

_head_n() {
  head -n $1
}

_tail_n() {
  if ! tail -n $1 2>/dev/null ; then
    #fix for solaris
    tail -$1
  fi
}

# url  payload needbase64  keyfile
_send_signed_request() {
  url=$1
  payload=$2
  needbase64=$3
  keyfile=$4
  if [ -z "$keyfile" ] ; then
    keyfile="$ACCOUNT_KEY_PATH"
  fi
  _debug url $url
  _debug payload "$payload"
  
  if ! _calcjwk "$keyfile" ; then
    return 1
  fi

  payload64=$(printf "%s" "$payload" | _base64 | _urlencode)
  _debug3 payload64 $payload64
  
  if [ -z "$_CACHED_NONCE" ] ; then
    _debug2 "Get nonce."
    nonceurl="$API/directory"
    _headers="$(_get $nonceurl "onlyheader")"
    
    if [ "$?" != "0" ] ; then
      _err "Can not connect to $nonceurl to get nonce."
      return 1
    fi
    
    _debug3 _headers "$_headers"
    
    _CACHED_NONCE="$( echo "$_headers" | grep "Replay-Nonce:" | _head_n 1 | tr -d "\r\n " | cut -d ':' -f 2)"
  else
    _debug2 "Use _CACHED_NONCE" "$_CACHED_NONCE"
  fi
  nonce="$_CACHED_NONCE"
  _debug3 nonce "$nonce"
  
  protected="$JWK_HEADERPLACE_PART1$nonce$JWK_HEADERPLACE_PART2"
  _debug3 protected "$protected"
  
  protected64="$(printf "$protected" | _base64 | _urlencode)"
  _debug3 protected64 "$protected64"

  sig=$(printf "%s" "$protected64.$payload64" |  _sign  "$keyfile" "sha256" | _urlencode)
  _debug3 sig "$sig"
  
  body="{\"header\": $JWK_HEADER, \"protected\": \"$protected64\", \"payload\": \"$payload64\", \"signature\": \"$sig\"}"
  _debug3 body "$body"
  

  response="$(_post "$body" $url "$needbase64")"
  _CACHED_NONCE=""
  if [ "$?" != "0" ] ; then
    _err "Can not post to $url"
    return 1
  fi
  _debug2 original "$response"
  
  response="$( echo "$response" | _normalizeJson )"

  responseHeaders="$(cat "$HTTP_HEADER")"
  
  _debug2 responseHeaders "$responseHeaders"
  _debug2 response  "$response"
  code="$(grep "^HTTP" $HTTP_HEADER | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n" )"
  _debug code $code
  
  _CACHED_NONCE="$(echo "$responseHeaders" | grep "Replay-Nonce:" | _head_n 1 | tr -d "\r\n " | cut -d ':' -f 2)"

}


#setopt "file"  "opt"  "="  "value" [";"]
_setopt() {
  __conf="$1"
  __opt="$2"
  __sep="$3"
  __val="$4"
  __end="$5"
  if [ -z "$__opt" ] ; then 
    _usage usage: _setopt  '"file"  "opt"  "="  "value" [";"]'
    return
  fi
  if [ ! -f "$__conf" ] ; then
    touch "$__conf"
  fi

  if grep -n "^$__opt$__sep" "$__conf" > /dev/null ; then
    _debug3 OK
    if _contains "$__val" "&" ; then
      __val="$(echo $__val | sed 's/&/\\&/g')"
    fi
    text="$(cat $__conf)"
    echo "$text" | sed "s|^$__opt$__sep.*$|$__opt$__sep$__val$__end|" > "$__conf"

  elif grep -n "^#$__opt$__sep" "$__conf" > /dev/null ; then
    if _contains "$__val" "&" ; then
      __val="$(echo $__val | sed 's/&/\\&/g')"
    fi
    text="$(cat $__conf)"
    echo "$text" | sed "s|^#$__opt$__sep.*$|$__opt$__sep$__val$__end|" > "$__conf"

  else
    _debug3 APP
    echo "$__opt$__sep$__val$__end" >> "$__conf"
  fi
  _debug2 "$(grep -n "^$__opt$__sep" $__conf)"
}


#_save_conf  file key  value
#save to conf
_save_conf() {
  _s_c_f="$1"
  _sdkey="$2"
  _sdvalue="$3"
  if [ "$_s_c_f" ] ; then
    _setopt "$_s_c_f" "$_sdkey" "=" "'$_sdvalue'"
  else
    _err "config file is empty, can not save $_sdkey=$_sdvalue"
  fi
}

#_clear_conf file  key
_clear_conf() {
  _c_c_f="$1"
  _sdkey="$2"
  if [ "$_c_c_f" ] ; then
    _sed_i "s/^$_sdkey.*$//"  "$_c_c_f"
  else
    _err "config file is empty, can not clear"
  fi
}

#_read_conf file  key
_read_conf() {
  _r_c_f="$1"
  _sdkey="$2"
  if [ -f "$_r_c_f" ] ; then
  (
    eval $(grep "^$_sdkey *=" "$_r_c_f")
    eval "printf \"%s\" \"\$$_sdkey\""
  )
  else
    _err "config file is empty, can not read $_sdkey"
  fi
}


#_savedomainconf   key  value
#save to domain.conf
_savedomainconf() {
  _save_conf "$DOMAIN_CONF" "$1" "$2"
}

#_cleardomainconf   key
_cleardomainconf() {
  _clear_conf "$DOMAIN_CONF" "$1"
}

#_readdomainconf   key
_readdomainconf() {
  _read_conf "$DOMAIN_CONF" "$1"
}

#_saveaccountconf  key  value
_saveaccountconf() {
  _save_conf "$ACCOUNT_CONF_PATH" "$1" "$2"
}

#_clearaccountconf   key
_clearaccountconf() {
  _clear_conf "$ACCOUNT_CONF_PATH" "$1"
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
  _debug "ncaddr" "$ncaddr"

  _debug "startserver: $$"
  nchelp="$(nc -h 2>&1)"
  
  _debug Le_HTTPPort "$Le_HTTPPort"
  _debug Le_Listen_V4 "$Le_Listen_V4"
  _debug Le_Listen_V6 "$Le_Listen_V6"
  _NC="nc"
  
  if [ "$Le_Listen_V4" ] ; then
    _NC="$_NC -4"
  elif [ "$Le_Listen_V6" ] ; then
    _NC="$_NC -6"
  fi
  
  if echo "$nchelp" | grep "\-q[ ,]" >/dev/null ; then
    _NC="$_NC -q 1 -l $ncaddr"
  else
    if echo "$nchelp" | grep "GNU netcat" >/dev/null && echo "$nchelp" | grep "\-c, \-\-close" >/dev/null ; then
      _NC="$_NC -c -l $ncaddr"
    elif echo "$nchelp" | grep "\-N" |grep "Shutdown the network socket after EOF on stdin"  >/dev/null ; then
      _NC="$_NC -N -l $ncaddr"
    else
      _NC="$_NC -l $ncaddr"
    fi
  fi


  _debug "_NC" "$_NC"

  #for centos ncat
  if _contains "$nchelp" "nmap.org" ; then
    _debug "Using ncat: nmap.org"
    if [ "$DEBUG" ] ; then
      if printf "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC  $Le_HTTPPort ; then
        return
      fi
    else 
      if printf "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC  $Le_HTTPPort > /dev/null 2>&1; then
        return
      fi
    fi
    _err "ncat listen error."
  fi
  
#  while true ; do
    if [ "$DEBUG" ] ; then
      if ! printf "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC -p $Le_HTTPPort ; then
        printf "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC  $Le_HTTPPort ;
      fi
    else
      if ! printf "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC -p $Le_HTTPPort > /dev/null 2>&1; then
        printf "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC  $Le_HTTPPort > /dev/null 2>&1
      fi      
    fi
    if [ "$?" != "0" ] ; then
      _err "nc listen error."
      exit 1
    fi
#  done
}

_stopserver(){
  pid="$1"
  _debug "pid" "$pid"
  if [ -z "$pid" ] ; then
    return
  fi

  _debug2 "Le_HTTPPort" "$Le_HTTPPort"
  if [ "$Le_HTTPPort" ] ; then
    if [ "$DEBUG" ] && [ "$DEBUG" -gt "3" ] ; then
      _get "http://localhost:$Le_HTTPPort" "" 1
    else
      _get "http://localhost:$Le_HTTPPort" "" 1 >/dev/null 2>&1
    fi
  fi
  
  _debug2 "Le_TLSPort" "$Le_TLSPort"
  if [ "$Le_TLSPort" ] ; then
    if [ "$DEBUG" ] && [ "$DEBUG" -gt "3" ] ; then
      _get "https://localhost:$Le_TLSPort" "" 1
      _get "https://localhost:$Le_TLSPort" "" 1
    else
      _get "https://localhost:$Le_TLSPort" "" 1 >/dev/null 2>&1
      _get "https://localhost:$Le_TLSPort" "" 1 >/dev/null 2>&1
    fi
  fi
}

# sleep sec
_sleep() {
  _sleep_sec="$1"
  if [ "$__INTERACTIVE" ] ; then
    _sleep_c="$_sleep_sec"
    while [ "$_sleep_c" -ge "0" ] ;
    do 
      printf "\r      \r"
      __green "$_sleep_c"
      _sleep_c="$(_math $_sleep_c - 1)"
      sleep 1
    done
    printf "\r"
  else
    sleep "$_sleep_sec"
  fi
}

# _starttlsserver  san_a  san_b port content _ncaddr
_starttlsserver() {
  _info "Starting tls server."
  san_a="$1"
  san_b="$2"
  port="$3"
  content="$4"
  opaddr="$5"
  
  _debug san_a "$san_a"
  _debug san_b "$san_b"
  _debug port "$port"
  
  #create key TLS_KEY
  if ! _createkey "2048" "$TLS_KEY" ; then
    _err "Create tls validation key error."
    return 1
  fi
  
  #create csr
  alt="$san_a"
  if [ "$san_b" ] ; then
    alt="$alt,$san_b"
  fi
  if ! _createcsr "tls.acme.sh" "$alt" "$TLS_KEY" "$TLS_CSR" "$TLS_CONF"  ; then
    _err "Create tls validation csr error."
    return 1
  fi
  
  #self signed
  if ! _signcsr "$TLS_KEY"  "$TLS_CSR"  "$TLS_CONF" "$TLS_CERT" ; then
    _err "Create tls validation cert error."
    return 1
  fi
  
  __S_OPENSSL="openssl s_server -cert $TLS_CERT  -key $TLS_KEY "
  if [ "$opaddr" ] ; then
    __S_OPENSSL="$__S_OPENSSL -accept $opaddr:$port"
  else
    __S_OPENSSL="$__S_OPENSSL -accept $port"
  fi

  _debug Le_Listen_V4 "$Le_Listen_V4"
  _debug Le_Listen_V6 "$Le_Listen_V6"
  if [ "$Le_Listen_V4" ] ; then
    __S_OPENSSL="$__S_OPENSSL -4"
  elif [ "$Le_Listen_V6" ] ; then
    __S_OPENSSL="$__S_OPENSSL -6"
  fi
  
  #start openssl
  _debug "$__S_OPENSSL"
  if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ] ; then
    (printf "HTTP/1.1 200 OK\r\n\r\n$content" | $__S_OPENSSL  -tlsextdebug ) &
  else
    (printf "HTTP/1.1 200 OK\r\n\r\n$content" | $__S_OPENSSL  >/dev/null 2>&1) &
  fi

  serverproc="$!"
  sleep 1
  _debug serverproc $serverproc
}

#file
_readlink() {
  _rf="$1"
  if ! readlink -f "$_rf" 2>/dev/null; then
    if _startswith "$_rf" "\./$PROJECT_ENTRY" ; then
      printf -- "%s" "$(pwd)/$PROJECT_ENTRY"
      return 0
    fi
    readlink  "$_rf"
  fi
}

__initHome() {
  if [ -z "$_SCRIPT_HOME" ] ; then
    if _exists readlink && _exists dirname ; then
      _debug "Lets find script dir."
      _debug "_SCRIPT_" "$_SCRIPT_"
      _script="$(_readlink "$_SCRIPT_")"
      _debug "_script" "$_script"
      _script_home="$(dirname "$_script")"
      _debug "_script_home" "$_script_home"
      if [ -d "$_script_home" ] ; then
        _SCRIPT_HOME="$_script_home"
      else
        _err "It seems the script home is not correct:$_script_home"
      fi
    fi
  fi


  if [ -z "$LE_WORKING_DIR" ] ; then
    if [ -f "$DEFAULT_INSTALL_HOME/account.conf" ] ; then
      _debug "It seems that $PROJECT_NAME is already installed in $DEFAULT_INSTALL_HOME"
      LE_WORKING_DIR="$DEFAULT_INSTALL_HOME"
    else
      LE_WORKING_DIR="$_SCRIPT_HOME"
    fi
  fi
  
  if [ -z "$LE_WORKING_DIR" ] ; then
    _debug "Using default home:$DEFAULT_INSTALL_HOME"
    LE_WORKING_DIR="$DEFAULT_INSTALL_HOME"
  fi
  export LE_WORKING_DIR

  _DEFAULT_ACCOUNT_CONF_PATH="$LE_WORKING_DIR/account.conf"

  if [ -z "$ACCOUNT_CONF_PATH" ] ; then
    if [ -f "$_DEFAULT_ACCOUNT_CONF_PATH" ] ; then
      . "$_DEFAULT_ACCOUNT_CONF_PATH"
    fi
  fi
  
  if [ -z "$ACCOUNT_CONF_PATH" ] ; then
    ACCOUNT_CONF_PATH="$_DEFAULT_ACCOUNT_CONF_PATH"
  fi
  
  DEFAULT_LOG_FILE="$LE_WORKING_DIR/$PROJECT_NAME.log"
  
  DEFAULT_CA_HOME="$LE_WORKING_DIR/ca"
}

#[domain]  [keylength]
_initpath() {

  __initHome

  if [ -f "$ACCOUNT_CONF_PATH" ] ; then
    . "$ACCOUNT_CONF_PATH"
  fi

  if [ "$IN_CRON" ] ; then
    if [ ! "$_USER_PATH_EXPORTED" ] ; then
      _USER_PATH_EXPORTED=1
      export PATH="$USER_PATH:$PATH"
    fi
  fi
  
  if [ -z "$CA_HOME" ] ; then
    CA_HOME="$DEFAULT_CA_HOME"
  fi

  if [ -z "$API" ] ; then
    if [ -z "$STAGE" ] ; then
      API="$DEFAULT_CA"
    else
      API="$STAGE_CA"
      _info "Using stage api:$API"
    fi  
  fi
  
  _API_HOST="$(echo "$API" | cut -d : -f 2 | tr -d '/')"
  CA_DIR="$CA_HOME/$_API_HOST"
  
  _DEFAULT_CA_CONF="$CA_DIR/ca.conf"
  
  if [ -z "$CA_CONF" ] ; then
    CA_CONF="$_DEFAULT_CA_CONF"
  fi
  
  if [ -f "$CA_CONF" ] ; then
    . "$CA_CONF"
  fi

  if [ -z "$ACME_DIR" ] ; then
    ACME_DIR="/home/.acme"
  fi
  
  if [ -z "$APACHE_CONF_BACKUP_DIR" ] ; then
    APACHE_CONF_BACKUP_DIR="$LE_WORKING_DIR"
  fi
  
  if [ -z "$USER_AGENT" ] ; then
    USER_AGENT="$DEFAULT_USER_AGENT"
  fi
  
  if [ -z "$HTTP_HEADER" ] ; then
    HTTP_HEADER="$LE_WORKING_DIR/http.header"
  fi

  _OLD_ACCOUNT_KEY="$LE_WORKING_DIR/account.key"
  _OLD_ACCOUNT_JSON="$LE_WORKING_DIR/account.json"
  
  _DEFAULT_ACCOUNT_KEY_PATH="$CA_DIR/account.key"
  _DEFAULT_ACCOUNT_JSON_PATH="$CA_DIR/account.json"
  if [ -z "$ACCOUNT_KEY_PATH" ] ; then
    ACCOUNT_KEY_PATH="$_DEFAULT_ACCOUNT_KEY_PATH"
  fi
  
  if [ -z "$ACCOUNT_JSON_PATH" ] ; then
    ACCOUNT_JSON_PATH="$_DEFAULT_ACCOUNT_JSON_PATH"
  fi
  
  
  _DEFAULT_CERT_HOME="$LE_WORKING_DIR"
  if [ -z "$CERT_HOME" ] ; then
    CERT_HOME="$_DEFAULT_CERT_HOME"
  fi

  if [ -z "$1" ] ; then
    return 0
  fi
  
  mkdir -p "$CA_DIR"
  
  domain="$1"
  _ilength="$2"

  if [ -z "$DOMAIN_PATH" ] ; then
    domainhome="$CERT_HOME/$domain"
    domainhomeecc="$CERT_HOME/$domain$ECC_SUFFIX"
    
    DOMAIN_PATH="$domainhome"
    
    if _isEccKey "$_ilength" ; then
      DOMAIN_PATH="$domainhomeecc"
    else
      if [ ! -d "$domainhome" ] && [ -d "$domainhomeecc" ] ; then
        _info "The domain '$domain' seems to have a ECC cert already, please add '$(__red "--ecc")' parameter if you want to use that cert."
      fi
    fi
    _debug DOMAIN_PATH "$DOMAIN_PATH"
  fi
  
  if [ ! -d "$DOMAIN_PATH" ] ; then
    if ! mkdir -p "$DOMAIN_PATH" ; then
      _err "Can not create domain path: $DOMAIN_PATH"
      return 1
    fi
  fi
  
  if [ -z "$DOMAIN_CONF" ] ; then
    DOMAIN_CONF="$DOMAIN_PATH/$domain.conf"
  fi
  
  if [ -z "$DOMAIN_SSL_CONF" ] ; then
    DOMAIN_SSL_CONF="$DOMAIN_PATH/$domain.csr.conf"
  fi
  
  if [ -z "$CSR_PATH" ] ; then
    CSR_PATH="$DOMAIN_PATH/$domain.csr"
  fi
  if [ -z "$CERT_KEY_PATH" ] ; then 
    CERT_KEY_PATH="$DOMAIN_PATH/$domain.key"
  fi
  if [ -z "$CERT_PATH" ] ; then
    CERT_PATH="$DOMAIN_PATH/$domain.cer"
  fi
  if [ -z "$CA_CERT_PATH" ] ; then
    CA_CERT_PATH="$DOMAIN_PATH/ca.cer"
  fi
  if [ -z "$CERT_FULLCHAIN_PATH" ] ; then
    CERT_FULLCHAIN_PATH="$DOMAIN_PATH/fullchain.cer"
  fi
  if [ -z "$CERT_PFX_PATH" ] ; then
    CERT_PFX_PATH="$DOMAIN_PATH/$domain.pfx"
  fi
  
  if [ -z "$TLS_CONF" ] ; then
    TLS_CONF="$DOMAIN_PATH/tls.valdation.conf"
  fi
  if [ -z "$TLS_CERT" ] ; then
    TLS_CERT="$DOMAIN_PATH/tls.valdation.cert"
  fi
  if [ -z "$TLS_KEY" ] ; then
    TLS_KEY="$DOMAIN_PATH/tls.valdation.key"
  fi
  if [ -z "$TLS_CSR" ] ; then
    TLS_CSR="$DOMAIN_PATH/tls.valdation.csr"
  fi
  
}


_apachePath() {
  _APACHECTL="apachectl"
  if ! _exists apachectl ; then
    if _exists apache2ctl ; then
       _APACHECTL="apache2ctl"
    else
      _err "'apachectl not found. It seems that apache is not installed, or you are not root user.'"
      _err "Please use webroot mode to try again."
      return 1
    fi
  fi
  httpdconfname="$($_APACHECTL -V | grep SERVER_CONFIG_FILE= | cut -d = -f 2 | tr -d '"' )"
  _debug httpdconfname "$httpdconfname"
  if _startswith "$httpdconfname" '/' ; then
    httpdconf="$httpdconfname"
    httpdconfname="$(basename $httpdconfname)"
  else
    httpdroot="$($_APACHECTL -V | grep HTTPD_ROOT= | cut -d = -f 2 | tr -d '"' )"
    _debug httpdroot "$httpdroot"
    httpdconf="$httpdroot/$httpdconfname"
    httpdconfname="$(basename $httpdconfname)"
  fi
  _debug httpdconf "$httpdconf"
  _debug httpdconfname "$httpdconfname"
  if [ ! -f "$httpdconf" ] ; then
    _err "Apache Config file not found" "$httpdconf"
    return 1
  fi
  return 0
}

_restoreApache() {
  if [ -z "$usingApache" ] ; then
    return 0
  fi
  _initpath
  if ! _apachePath ; then
    return 1
  fi
  
  if [ ! -f "$APACHE_CONF_BACKUP_DIR/$httpdconfname" ] ; then
    _debug "No config file to restore."
    return 0
  fi
  
  cat "$APACHE_CONF_BACKUP_DIR/$httpdconfname" > "$httpdconf"
  _debug "Restored: $httpdconf."
  if ! $_APACHECTL  -t >/dev/null 2>&1 ; then
    _err "Sorry, restore apache config error, please contact me."
    return 1;
  fi
  _debug "Restored successfully."
  rm -f "$APACHE_CONF_BACKUP_DIR/$httpdconfname"
  return 0  
}

_setApache() {
  _initpath
  if ! _apachePath ; then
    return 1
  fi

  #test the conf first
  _info "Checking if there is an error in the apache config file before starting."
  _msg="$($_APACHECTL  -t  2>&1 )"
  if [ "$?" != "0" ] ; then
    _err "Sorry, apache config file has error, please fix it first, then try again."
    _err "Don't worry, there is nothing changed to your system."
    _err "$_msg"
    return 1;
  else
    _info "OK"
  fi
  
  #backup the conf
  _debug "Backup apache config file" "$httpdconf"
  if ! cp "$httpdconf" "$APACHE_CONF_BACKUP_DIR/" ; then
    _err "Can not backup apache config file, so abort. Don't worry, the apache config is not changed."
    _err "This might be a bug of $PROJECT_NAME , pleae report issue: $PROJECT"
    return 1
  fi
  _info "JFYI, Config file $httpdconf is backuped to $APACHE_CONF_BACKUP_DIR/$httpdconfname"
  _info "In case there is an error that can not be restored automatically, you may try restore it yourself."
  _info "The backup file will be deleted on sucess, just forget it."
  
  #add alias
  
  apacheVer="$($_APACHECTL -V | grep "Server version:" | cut -d : -f 2 | cut -d " " -f 2 | cut -d '/' -f 2 )"
  _debug "apacheVer" "$apacheVer"
  apacheMajer="$(echo "$apacheVer" | cut -d . -f 1)"
  apacheMinor="$(echo "$apacheVer" | cut -d . -f 2)"

  if [ "$apacheVer" ] && [ "$apacheMajer$apacheMinor" -ge "24" ] ; then
    echo "
Alias /.well-known/acme-challenge  $ACME_DIR

<Directory $ACME_DIR >
Require all granted
</Directory>
  " >> "$httpdconf"
  else
    echo "
Alias /.well-known/acme-challenge  $ACME_DIR

<Directory $ACME_DIR >
Order allow,deny
Allow from all
</Directory>
  " >> "$httpdconf"
  fi

  _msg="$($_APACHECTL  -t  2>&1 )"
  if [ "$?" != "0" ] ; then
    _err "Sorry, apache config error"
    if _restoreApache ; then
      _err "The apache config file is restored."
    else
      _err "Sorry, The apache config file can not be restored, please report bug."
    fi
    return 1;
  fi
  
  if [ ! -d "$ACME_DIR" ] ; then
    mkdir -p "$ACME_DIR"
    chmod 755 "$ACME_DIR"
  fi
  
  if ! $_APACHECTL  graceful ; then
    _err "Sorry, $_APACHECTL  graceful error, please contact me."
    _restoreApache
    return 1;
  fi
  usingApache="1"
  return 0
}

_clearup() {
  _stopserver $serverproc
  serverproc=""
  _restoreApache
  _clearupdns
  if [ -z "$DEBUG" ] ; then
    rm -f "$TLS_CONF"
    rm -f "$TLS_CERT"
    rm -f "$TLS_KEY"
    rm -f "$TLS_CSR"
  fi
}

_clearupdns() {
  _debug "_clearupdns"
  if [ "$dnsadded" != 1 ] || [ -z "$vlist" ] ; then
    _info "Dns not added, skip."
    return
  fi

  ventries=$(echo "$vlist" |  tr ',' ' ' )
  for ventry in $ventries
  do
    d=$(echo $ventry | cut -d $sep -f 1)
    keyauthorization=$(echo $ventry | cut -d $sep -f 2)
    vtype=$(echo $ventry | cut -d $sep -f 4)
    _currentRoot=$(echo $ventry | cut -d $sep -f 5)

    if [ "$keyauthorization" = "$STATE_VERIFIED" ] ; then
      _info "$d is already verified, skip $vtype."
      continue
    fi

    if [ "$vtype" != "$VTYPE_DNS" ] ; then
      _info "Skip $d for $vtype"
      continue
    fi
    
    d_api="$(_findHook $d dnsapi $_currentRoot)"
    _debug d_api "$d_api"
    
    if [ -z "$d_api" ] ; then
      _info "Not Found domain api file: $d_api"
      continue
    fi
    
    (
      if ! . $d_api ; then
        _err "Load file $d_api error. Please check your api file and try again."
        return 1
      fi
      
      rmcommand="${_currentRoot}_rm"
      if ! _exists $rmcommand ; then 
        _err "It seems that your api file doesn't define $rmcommand"
        return 1
      fi
      
      txtdomain="_acme-challenge.$d"
      
      if ! $rmcommand $txtdomain ; then
        _err "Error removing txt for domain:$txtdomain"
        return 1
      fi
    )
        
  done
}

# webroot  removelevel tokenfile
_clearupwebbroot() {
  __webroot="$1"
  if [ -z "$__webroot" ] ; then
    _debug "no webroot specified, skip"
    return 0
  fi
  
  _rmpath=""
  if [ "$2" = '1' ] ; then
    _rmpath="$__webroot/.well-known"
  elif [ "$2" = '2' ] ; then
    _rmpath="$__webroot/.well-known/acme-challenge"
  elif [ "$2" = '3' ] ; then
    _rmpath="$__webroot/.well-known/acme-challenge/$3"
  else
    _debug "Skip for removelevel:$2"
  fi
  
  if [ "$_rmpath" ] ; then
    if [ "$DEBUG" ] ; then
      _debug "Debugging, skip removing: $_rmpath"
    else
      rm -rf "$_rmpath"
    fi
  fi
  
  return 0

}

_on_before_issue() {
  _debug _on_before_issue
  if _hasfield "$Le_Webroot" "$NO_VALUE" ; then
    if ! _exists "nc" ; then
      _err "Please install netcat(nc) tools first."
      return 1
    fi
  elif ! _hasfield "$Le_Webroot" "$W_TLS" ; then
    #no need to check anymore
    return 0
  fi

  _debug Le_LocalAddress "$Le_LocalAddress"
  
  alldomains=$(echo "$Le_Domain,$Le_Alt" |  tr ',' ' ' )
  _index=1
  _currentRoot=""
  _addrIndex=1
  for d in $alldomains   
  do
    _debug "Check for domain" $d
    _currentRoot="$(_getfield "$Le_Webroot" $_index)"
    _debug "_currentRoot" "$_currentRoot"
    _index=$(_math $_index + 1)
    _checkport=""
    if [ "$_currentRoot" = "$NO_VALUE" ] ; then
      _info "Standalone mode."
      if [ -z "$Le_HTTPPort" ] ; then
        Le_HTTPPort=80
      else
        _savedomainconf "Le_HTTPPort"  "$Le_HTTPPort"
      fi
      _checkport="$Le_HTTPPort"
    elif [ "$_currentRoot" = "$W_TLS" ] ; then
      _info "Standalone tls mode."
      if [ -z "$Le_TLSPort" ] ; then
        Le_TLSPort=443
      else
        _savedomainconf "Le_TLSPort"  "$Le_TLSPort"
      fi
      _checkport="$Le_TLSPort"
    fi
    
    if [ "$_checkport" ] ; then
      _debug _checkport "$_checkport"
      _checkaddr="$(_getfield "$Le_LocalAddress" $_addrIndex)"
      _debug _checkaddr "$_checkaddr"
      
      _addrIndex="$(_math $_addrIndex + 1)"
      
      _netprc="$(_ss "$_checkport" | grep "$_checkport")"
      netprc="$(echo "$_netprc" | grep "$_checkaddr")"
      if [ -z "$netprc" ] ; then
        netprc="$(echo "$_netprc" | grep "$LOCAL_ANY_ADDRESS")"
      fi
      if [ "$netprc" ] ; then
        _err "$netprc"
        _err "tcp port $_checkport is already used by $(echo "$netprc" | cut -d :  -f 4)"
        _err "Please stop it first"
        return 1
      fi
    fi
  done

  if _hasfield "$Le_Webroot" "apache" ; then
    if ! _setApache ; then
      _err "set up apache error. Report error to me."
      return 1
    fi
  else
    usingApache=""
  fi

  #run pre hook
  if [ "$Le_PreHook" ] ; then
    _info "Run pre hook:'$Le_PreHook'"
    if ! (
      cd "$DOMAIN_PATH" && eval "$Le_PreHook"
    ) ; then
      _err "Error when run pre hook."
      return 1
    fi
  fi
}

_on_issue_err() {
  _debug _on_issue_err
  if [ "$LOG_FILE" ] ; then
    _err "Please check log file for more details: $LOG_FILE"
  else
    _err "Please use add '--debug' or '--log' to check more details."
    _err "See: $_DEBUG_WIKI"
  fi
  
  #run the post hook
  if [ "$Le_PostHook" ] ; then
    _info "Run post hook:'$Le_PostHook'"
    if ! (
      cd "$DOMAIN_PATH" && eval "$Le_PostHook"
    ) ; then
      _err "Error when run post hook."
      return 1
    fi
  fi
}

_on_issue_success() {
  _debug _on_issue_success
  #run the post hook
  if [ "$Le_PostHook" ] ; then
    _info "Run post hook:'$Le_PostHook'"
    if ! (
      cd "$DOMAIN_PATH" && eval "$Le_PostHook"
    ) ; then
      _err "Error when run post hook."
      return 1
    fi
  fi
  
  #run renew hook
  if [ "$IS_RENEW" ] && [ "$Le_RenewHook" ] ; then
    _info "Run renew hook:'$Le_RenewHook'"
    if ! (
      cd "$DOMAIN_PATH" && eval "$Le_RenewHook"
    ) ; then
      _err "Error when run renew hook."
      return 1
    fi
  fi  
  
}

updateaccount() {
  _initpath
  _regAccount
}

registeraccount() {
  _initpath
  _regAccount
}

__calcAccountKeyHash() {
  [ -f "$ACCOUNT_KEY_PATH" ] && cat "$ACCOUNT_KEY_PATH" | _digest sha256
}

_regAccount() {
  _initpath
  
  if [ ! -f "$ACCOUNT_KEY_PATH" ] && [ -f "$_OLD_ACCOUNT_KEY" ]; then
    _info "mv $_OLD_ACCOUNT_KEY to $ACCOUNT_KEY_PATH"
    mv "$_OLD_ACCOUNT_KEY" "$ACCOUNT_KEY_PATH"
  fi
  
  if [ ! -f "$ACCOUNT_JSON_PATH" ] && [ -f "$_OLD_ACCOUNT_JSON" ]; then
    _info "mv $_OLD_ACCOUNT_JSON to $ACCOUNT_JSON_PATH"
    mv "$_OLD_ACCOUNT_JSON" "$ACCOUNT_JSON_PATH"
  fi
  
  if [ ! -f "$ACCOUNT_KEY_PATH" ] ; then
    _acck="no"
    if [ "$Le_Keylength" ] ; then
      _acck="$Le_Keylength"
    fi
    if ! createAccountKey "$_acck" ; then
      _err "Create account key error."
      return 1
    fi
  fi
  
  if ! _calcjwk "$ACCOUNT_KEY_PATH" ; then
    return 1
  fi

  _updateTos=""
  _reg_res="new-reg"
  while true ;
  do
    _debug AGREEMENT "$AGREEMENT"
    
    regjson='{"resource": "'$_reg_res'", "agreement": "'$AGREEMENT'"}'

    if [ "$ACCOUNT_EMAIL" ] ; then
      regjson='{"resource": "'$_reg_res'", "contact": ["mailto: '$ACCOUNT_EMAIL'"], "agreement": "'$AGREEMENT'"}'
    fi

    if [ -z "$_updateTos" ] ; then
      _info "Registering account"

      if ! _send_signed_request   "$API/acme/new-reg"  "$regjson" ; then
        _err "Register account Error: $response"
        return 1
      fi

      if [ "$code" = "" ] || [ "$code" = '201' ] ; then
        echo "$response" > $ACCOUNT_JSON_PATH
        _info "Registered"
      elif [ "$code" = '409' ] ; then
        _info "Already registered"
      else
        _err "Register account Error: $response"
        return 1
      fi

      _accUri="$(echo "$responseHeaders" | grep "^Location:" | _head_n 1 | cut -d ' ' -f 2| tr -d "\r\n")"
      _debug "_accUri" "$_accUri"

      _tos="$(echo "$responseHeaders" | grep "^Link:.*rel=\"terms-of-service\"" | _head_n 1 | _egrep_o "<.*>" | tr -d '<>')"
      _debug "_tos" "$_tos"
      if [ -z "$_tos" ] ; then
        _debug "Use default tos: $DEFAULT_AGREEMENT"
        _tos="$DEFAULT_AGREEMENT"
      fi
      if [ "$_tos" != "$AGREEMENT" ]; then
        _updateTos=1
        AGREEMENT="$_tos"
        _reg_res="reg"
        continue
      fi
      
    else
      _debug "Update tos: $_tos"
      if ! _send_signed_request   "$_accUri"  "$regjson" ; then
        _err "Update tos error."
        return 1
      fi
      if [ "$code" = '202' ] ; then
        _info "Update success."
        
        CA_KEY_HASH="$(__calcAccountKeyHash)"
        _debug "Calc CA_KEY_HASH" "$CA_KEY_HASH"
        _savecaconf CA_KEY_HASH "$CA_KEY_HASH"
      else
        _err "Update account error."
        return 1
      fi
    fi
    return 0
  done

}


# domain folder  file
_findHook() {
  _hookdomain="$1"
  _hookcat="$2"
  _hookname="$3"

  if [ -f "$LE_WORKING_DIR/$_hookdomain/$_hookname" ] ; then
    d_api="$LE_WORKING_DIR/$_hookdomain/$_hookname"
  elif [ -f "$LE_WORKING_DIR/$_hookdomain/$_hookname.sh" ] ; then
    d_api="$LE_WORKING_DIR/$_hookdomain/$_hookname.sh"
  elif [ -f "$LE_WORKING_DIR/$_hookname" ] ; then
    d_api="$LE_WORKING_DIR/$_hookname"
  elif [ -f "$LE_WORKING_DIR/$_hookname.sh" ] ; then
    d_api="$LE_WORKING_DIR/$_hookname.sh"
  elif [ -f "$LE_WORKING_DIR/$_hookcat/$_hookname" ] ; then
    d_api="$LE_WORKING_DIR/$_hookcat/$_hookname"
  elif [ -f "$LE_WORKING_DIR/$_hookcat/$_hookname.sh" ] ; then
    d_api="$LE_WORKING_DIR/$_hookcat/$_hookname.sh"
  fi

  printf "%s" "$d_api"
}

#domain
__get_domain_new_authz() {
  _gdnd="$1"
  _info "Getting new-authz for domain" "$_gdnd"
  
  _Max_new_authz_retry_times=5
  _authz_i=0
  while [ "$_authz_i" -lt "$_Max_new_authz_retry_times" ] ; do
    _info "Try new-authz for the $_authz_i time."
    if ! _send_signed_request "$API/acme/new-authz" "{\"resource\": \"new-authz\", \"identifier\": {\"type\": \"dns\", \"value\": \"$(_idn "$_gdnd")\"}}" ; then
      _err "Can not get domain new authz."
      return 1
    fi
    if ! _contains "$response" "An error occurred while processing your request" ; then
      _info "The new-authz request is ok."
      break
    fi
    _authz_i="$(_math "$_authz_i" + 1)"
    _info "The server is busy, Sleep $_authz_i to retry."
    _sleep "$_authz_i"
  done;

  if [ "$_authz_i" = "$_Max_new_authz_retry_times" ] ; then
    _debug "new-authz retry reach the max $_Max_new_authz_retry_times times."
  fi
  
  if [ ! -z "$code" ] && [ ! "$code" = '201' ] ; then
    _err "new-authz error: $response"
    return 1
  fi

}

#webroot, domain domainlist  keylength 
issue() {
  if [ -z "$2" ] ; then
    _usage "Usage: $PROJECT_ENTRY --issue  -d  a.com  -w /path/to/webroot/a.com/ "
    return 1
  fi
  Le_Webroot="$1"
  Le_Domain="$2"
  Le_Alt="$3"
  Le_Keylength="$4"
  Le_RealCertPath="$5"
  Le_RealKeyPath="$6"
  Le_RealCACertPath="$7"
  Le_ReloadCmd="$8"
  Le_RealFullChainPath="$9"
  Le_PreHook="${10}"
  Le_PostHook="${11}"
  Le_RenewHook="${12}"
  Le_LocalAddress="${13}"
  
  #remove these later.
  if [ "$Le_Webroot" = "dns-cf" ] ; then
    Le_Webroot="dns_cf"
  fi
  if [ "$Le_Webroot" = "dns-dp" ] ; then
    Le_Webroot="dns_dp"
  fi
  if [ "$Le_Webroot" = "dns-cx" ] ; then
    Le_Webroot="dns_cx"
  fi
  _debug "Using api: $API"
  
  if [ ! "$IS_RENEW" ] ; then
    _initpath $Le_Domain "$Le_Keylength"
    mkdir -p "$DOMAIN_PATH"
  fi

  if [ -f "$DOMAIN_CONF" ] ; then
    Le_NextRenewTime=$(_readdomainconf Le_NextRenewTime)
    _debug Le_NextRenewTime "$Le_NextRenewTime"
    if [ -z "$FORCE" ] && [ "$Le_NextRenewTime" ] && [ $(_time) -lt $Le_NextRenewTime ] ; then 
      _saved_domain=$(_readdomainconf Le_Domain)
      _debug _saved_domain "$_saved_domain"
      _saved_alt=$(_readdomainconf Le_Alt)
      _debug _saved_alt "$_saved_alt"
      if [ "$_saved_domain,$_saved_alt" = "$Le_Domain,$Le_Alt" ] ; then
        _info "Domains not changed."
        _info "Skip, Next renewal time is: $(__green "$(_readdomainconf Le_NextRenewTimeStr)")"
        _info "Add '$(__red '--force')' to force to renew."    
        return $RENEW_SKIP
      else
        _info "Domains have changed."
      fi
    fi
  fi

  _savedomainconf "Le_Domain"       "$Le_Domain"
  _savedomainconf "Le_Alt"          "$Le_Alt"
  _savedomainconf "Le_Webroot"      "$Le_Webroot"
  
  _savedomainconf "Le_PreHook"      "$Le_PreHook"
  _savedomainconf "Le_PostHook"     "$Le_PostHook"
  _savedomainconf "Le_RenewHook"     "$Le_RenewHook"
  
  if [ "$Le_LocalAddress" ] ; then
    _savedomainconf "Le_LocalAddress"     "$Le_LocalAddress"
  else
    _cleardomainconf "Le_LocalAddress"
  fi

  Le_API="$API"
  _savedomainconf "Le_API" "$Le_API"
  
  if [ "$Le_Alt" = "$NO_VALUE" ] ; then
    Le_Alt=""
  fi
  
  if [ "$Le_Keylength" = "$NO_VALUE" ] ; then
    Le_Keylength=""
  fi
  
  if ! _on_before_issue ; then
    _err "_on_before_issue."
    return 1
  fi

  _saved_account_key_hash="$(_readcaconf "CA_KEY_HASH")"
  _debug2 _saved_account_key_hash "$_saved_account_key_hash"
  
  if [ -z "$_saved_account_key_hash" ] || [ "$_saved_account_key_hash" != "$(__calcAccountKeyHash)" ] ; then
    if ! _regAccount ; then
      _on_issue_err
      return 1
    fi
  fi

  if [ -f "$CSR_PATH" ] && [ ! -f "$CERT_KEY_PATH" ] ; then
    _info "Signing from existing CSR."
  else
    _key=$(_readdomainconf Le_Keylength)
    _debug "Read key length:$_key"
    if [ ! -f "$CERT_KEY_PATH" ] || [ "$Le_Keylength" != "$_key" ] ; then
      if ! createDomainKey $Le_Domain $Le_Keylength ; then 
        _err "Create domain key error."
        _clearup
        _on_issue_err
        return 1
      fi
    fi

    if ! _createcsr "$Le_Domain" "$Le_Alt" "$CERT_KEY_PATH" "$CSR_PATH" "$DOMAIN_SSL_CONF"   ; then
      _err "Create CSR error."
      _clearup
      _on_issue_err
      return 1
    fi
  fi

  _savedomainconf "Le_Keylength"    "$Le_Keylength"
  
  vlist="$Le_Vlist"

  _info "Getting domain auth token for each domain"
  sep='#'
  if [ -z "$vlist" ] ; then
    alldomains=$(echo "$Le_Domain,$Le_Alt" |  tr ',' ' ' )
    _index=1
    _currentRoot=""
    for d in $alldomains   
    do
      _info "Getting webroot for domain" $d
      _w="$(echo $Le_Webroot | cut -d , -f $_index)"
      _info _w "$_w"
      if [ "$_w" ] ; then
        _currentRoot="$_w"
      fi
      _debug "_currentRoot" "$_currentRoot"
      _index=$(_math $_index + 1)
      
      vtype="$VTYPE_HTTP"
      if _startswith "$_currentRoot" "dns" ; then
        vtype="$VTYPE_DNS"
      fi
      
      if [ "$_currentRoot" = "$W_TLS" ] ; then
        vtype="$VTYPE_TLS"
      fi
      
      if ! __get_domain_new_authz "$d" ; then
        _clearup
        _on_issue_err
        return 1
      fi
      
      if [ -z "$thumbprint" ] ; then
        accountkey_json=$(printf "%s" "$jwk" |  tr -d ' ' )
        thumbprint=$(printf "%s" "$accountkey_json" | _digest "sha256" | _urlencode)
      fi
      
      entry="$(printf "%s\n" "$response" | _egrep_o  '[^\{]*"type":"'$vtype'"[^\}]*')"
      _debug entry "$entry"
      if [ -z "$entry" ] ; then
        _err "Error, can not get domain token $d"
        _clearup
        _on_issue_err
        return 1
      fi
      token="$(printf "%s\n" "$entry" | _egrep_o '"token":"[^"]*' | cut -d : -f 2 | tr -d '"')"
      _debug token $token
      
      uri="$(printf "%s\n" "$entry" | _egrep_o '"uri":"[^"]*'| cut -d : -f 2,3 | tr -d '"' )"
      _debug uri $uri

      keyauthorization="$token.$thumbprint"
      _debug keyauthorization "$keyauthorization"


      if printf "$response" | grep '"status":"valid"' >/dev/null 2>&1 ; then
        _info "$d is already verified, skip."
        keyauthorization=$STATE_VERIFIED
        _debug keyauthorization "$keyauthorization"
      fi


      dvlist="$d$sep$keyauthorization$sep$uri$sep$vtype$sep$_currentRoot"
      _debug dvlist "$dvlist"
      
      vlist="$vlist$dvlist,"

    done

    #add entry
    dnsadded=""
    ventries=$(echo "$vlist" |  tr ',' ' ' )
    for ventry in $ventries
    do
      d=$(echo $ventry | cut -d $sep -f 1)
      keyauthorization=$(echo $ventry | cut -d $sep -f 2)
      vtype=$(echo $ventry | cut -d $sep -f 4)
      _currentRoot=$(echo $ventry | cut -d $sep -f 5)

      if [ "$keyauthorization" = "$STATE_VERIFIED" ] ; then
        _info "$d is already verified, skip $vtype."
        continue
      fi

      if [ "$vtype" = "$VTYPE_DNS" ] ; then
        dnsadded='0'
        txtdomain="_acme-challenge.$d"
        _debug txtdomain "$txtdomain"
        txt="$(printf "%s" "$keyauthorization" | _digest "sha256" | _urlencode)"
        _debug txt "$txt"

        d_api="$(_findHook $d dnsapi $_currentRoot)"

        _debug d_api "$d_api"
        
        if [ "$d_api" ] ; then
          _info "Found domain api file: $d_api"
        else
          _err "Add the following TXT record:"
          _err "Domain: '$(__green $txtdomain)'"
          _err "TXT value: '$(__green $txt)'"
          _err "Please be aware that you prepend _acme-challenge. before your domain"
          _err "so the resulting subdomain will be: $txtdomain"
          continue
        fi
        
        (
          if ! . $d_api ; then
            _err "Load file $d_api error. Please check your api file and try again."
            return 1
          fi
          
          addcommand="${_currentRoot}_add"
          if ! _exists $addcommand ; then 
            _err "It seems that your api file is not correct, it must have a function named: $addcommand"
            return 1
          fi
          
          if ! $addcommand $txtdomain $txt ; then
            _err "Error add txt for domain:$txtdomain"
            return 1
          fi
        )
        
        if [ "$?" != "0" ] ; then
          _clearup
          _on_issue_err
          return 1
        fi
        dnsadded='1'
      fi
    done

    if [ "$dnsadded" = '0' ] ; then
      _savedomainconf "Le_Vlist"   "$vlist"
      _debug "Dns record not added yet, so, save to $DOMAIN_CONF and exit."
      _err "Please add the TXT records to the domains, and retry again."
      _clearup
      _on_issue_err
      return 1
    fi
    
  fi
  
  if [ "$dnsadded" = '1' ] ; then
    if [ -z "$Le_DNSSleep" ] ; then
      Le_DNSSleep=$DEFAULT_DNS_SLEEP
    else
      _savedomainconf "Le_DNSSleep"  "$Le_DNSSleep"
    fi

    _info "Sleep $(__green $Le_DNSSleep) seconds for the txt records to take effect"
    _sleep $Le_DNSSleep
  fi
  
  _debug "ok, let's start to verify"

  _ncIndex=1
  ventries=$(echo "$vlist" |  tr ',' ' ' )
  for ventry in $ventries
  do
    d=$(echo $ventry | cut -d $sep -f 1)
    keyauthorization=$(echo $ventry | cut -d $sep -f 2)
    uri=$(echo $ventry | cut -d $sep -f 3)
    vtype=$(echo $ventry | cut -d $sep -f 4)
    _currentRoot=$(echo $ventry | cut -d $sep -f 5)

    if [ "$keyauthorization" = "$STATE_VERIFIED" ] ; then
      _info "$d is already verified, skip $vtype."
      continue
    fi

    _info "Verifying:$d"
    _debug "d" "$d"
    _debug "keyauthorization" "$keyauthorization"
    _debug "uri" "$uri"
    removelevel=""
    token="$(printf "%s" "$keyauthorization" | cut -d '.' -f 1)"

    _debug "_currentRoot" "$_currentRoot"

      
    if [ "$vtype" = "$VTYPE_HTTP" ] ; then
      if [ "$_currentRoot" = "$NO_VALUE" ] ; then
        _info "Standalone mode server"
        _ncaddr="$(_getfield "$Le_LocalAddress" "$_ncIndex" )"
        _ncIndex="$(_math $_ncIndex + 1)"
        _startserver "$keyauthorization" "$_ncaddr" &
        if [ "$?" != "0" ] ; then
          _clearup
          _on_issue_err
          return 1
        fi
        serverproc="$!"
        sleep 1
        _debug serverproc $serverproc

      else
        if [ "$_currentRoot" = "apache" ] ; then
          wellknown_path="$ACME_DIR"
        else
          wellknown_path="$_currentRoot/.well-known/acme-challenge"
          if [ ! -d "$_currentRoot/.well-known" ] ; then 
            removelevel='1'
          elif [ ! -d "$_currentRoot/.well-known/acme-challenge" ] ; then 
            removelevel='2'
          else
            removelevel='3'
          fi
        fi

        _debug wellknown_path "$wellknown_path"

        _debug "writing token:$token to $wellknown_path/$token"

        mkdir -p "$wellknown_path"
        printf "%s" "$keyauthorization" > "$wellknown_path/$token"
        if [ ! "$usingApache" ] ; then
          if webroot_owner=$(_stat $_currentRoot) ; then
            _debug "Changing owner/group of .well-known to $webroot_owner"
            chown -R $webroot_owner "$_currentRoot/.well-known"
          else
            _debug "not chaning owner/group of webroot";
          fi
        fi
        
      fi
      
    elif [ "$vtype" = "$VTYPE_TLS" ] ; then
      #create A
      #_hash_A="$(printf "%s" $token | _digest "sha256" "hex" )"
      #_debug2 _hash_A "$_hash_A"
      #_x="$(echo $_hash_A | cut -c 1-32)"
      #_debug2 _x "$_x"
      #_y="$(echo $_hash_A | cut -c 33-64)"
      #_debug2 _y "$_y"
      #_SAN_A="$_x.$_y.token.acme.invalid"
      #_debug2 _SAN_A "$_SAN_A"
      
      #create B
      _hash_B="$(printf "%s" $keyauthorization | _digest "sha256" "hex" )"
      _debug2 _hash_B "$_hash_B"
      _x="$(echo $_hash_B | cut -c 1-32)"
      _debug2 _x "$_x"
      _y="$(echo $_hash_B | cut -c 33-64)"
      _debug2 _y "$_y"
      
      #_SAN_B="$_x.$_y.ka.acme.invalid"
      
      _SAN_B="$_x.$_y.acme.invalid"
      _debug2 _SAN_B "$_SAN_B"
      
      _ncaddr="$(_getfield "$Le_LocalAddress" "$_ncIndex" )"
      _ncIndex="$(_math $_ncIndex + 1)"
      if ! _starttlsserver "$_SAN_B" "$_SAN_A" "$Le_TLSPort" "$keyauthorization" "$_ncaddr"; then
        _err "Start tls server error."
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        _on_issue_err
        return 1
      fi
    fi
    
    if ! _send_signed_request $uri "{\"resource\": \"challenge\", \"keyAuthorization\": \"$keyauthorization\"}" ; then
      _err "$d:Can not get challenge: $response"
      _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
      _clearup
      _on_issue_err
      return 1
    fi
    
    if [ ! -z "$code" ] && [ ! "$code" = '202' ] ; then
      _err "$d:Challenge error: $response"
      _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
      _clearup
      _on_issue_err
      return 1
    fi
    
    waittimes=0
    if [ -z "$MAX_RETRY_TIMES" ] ; then
      MAX_RETRY_TIMES=30
    fi
    
    while true ; do
      waittimes=$(_math $waittimes + 1)
      if [ "$waittimes" -ge "$MAX_RETRY_TIMES" ] ; then
        _err "$d:Timeout"
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        _on_issue_err
        return 1
      fi
      
      _debug "sleep 2 secs to verify"
      sleep 2
      _debug "checking"
      response="$(_get $uri)"
      if [ "$?" != "0" ] ; then
        _err "$d:Verify error:$response"
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        _on_issue_err
        return 1
      fi
      _debug2 original "$response"
      
      response="$(echo "$response" | _normalizeJson )"
      _debug2 response "$response"
      
      status=$(echo "$response" | _egrep_o  '"status":"[^"]*' | cut -d : -f 2 | tr -d '"')
      if [ "$status" = "valid" ] ; then
        _info "Success"
        _stopserver $serverproc
        serverproc=""
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        break;
      fi
      
      if [ "$status" = "invalid" ] ; then
         error="$(echo "$response" | tr -d "\r\n" | _egrep_o '"error":\{[^\}]*')"
         _debug2 error "$error"
         errordetail="$(echo "$error" |  _egrep_o '"detail": *"[^"]*' | cut -d '"' -f 4)"
         _debug2 errordetail "$errordetail"
         if [ "$errordetail" ] ; then
           _err "$d:Verify error:$errordetail"
         else
           _err "$d:Verify error:$error"
         fi
         if [ "$DEBUG" ] ; then
           if [ "$vtype" = "$VTYPE_HTTP" ] ; then
             _debug "Debug: get token url."
             _get "http://$d/.well-known/acme-challenge/$token" "" 1
           fi
         fi
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        _on_issue_err
        return 1;
      fi
      
      if [ "$status" = "pending" ] ; then
        _info "Pending"
      else
        _err "$d:Verify error:$response" 
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        _on_issue_err
        return 1
      fi
      
    done
    
  done

  _clearup
  _info "Verify finished, start to sign."
  der="$(_getfile "${CSR_PATH}" "${BEGIN_CSR}" "${END_CSR}" | tr -d "\r\n" | _urlencode)"
  
  if ! _send_signed_request "$API/acme/new-cert" "{\"resource\": \"new-cert\", \"csr\": \"$der\"}" "needbase64" ; then
    _err "Sign failed."
    _on_issue_err
    return 1
  fi
  
  _rcert="$response"
  Le_LinkCert="$(grep -i '^Location.*$' $HTTP_HEADER | _head_n 1 | tr -d "\r\n" | cut -d " " -f 2)"
  _savedomainconf "Le_LinkCert"  "$Le_LinkCert"

  if [ "$Le_LinkCert" ] ; then
    echo "$BEGIN_CERT" > "$CERT_PATH"
    
    #if ! _get "$Le_LinkCert" | _base64 "multiline"  >> "$CERT_PATH" ; then
    #  _debug "Get cert failed. Let's try last response."
    #  printf -- "%s" "$_rcert" | _dbase64 "multiline" | _base64 "multiline" >> "$CERT_PATH" 
    #fi
    
    if ! printf -- "%s" "$_rcert" | _dbase64 "multiline" | _base64 "multiline" >> "$CERT_PATH" ; then
      _debug "Try cert link."
      _get "$Le_LinkCert" | _base64 "multiline"  >> "$CERT_PATH"
    fi

    echo "$END_CERT"  >> "$CERT_PATH"
    _info "$(__green "Cert success.")"
    cat "$CERT_PATH"
    
    _info "Your cert is in $( __green " $CERT_PATH ")"

    if [ -f "$CERT_KEY_PATH" ] ; then
      _info "Your cert key is in $( __green " $CERT_KEY_PATH ")"
    fi

    cp "$CERT_PATH" "$CERT_FULLCHAIN_PATH"

    if [ ! "$USER_PATH" ] || [ ! "$IN_CRON" ] ; then
      USER_PATH="$PATH"
      _saveaccountconf "USER_PATH" "$USER_PATH"
    fi
  fi
  

  if [ -z "$Le_LinkCert" ] ; then
    response="$(echo $response | _dbase64 "multiline" | _normalizeJson )"
    _err "Sign failed: $(echo "$response" | _egrep_o  '"detail":"[^"]*"')"
    _on_issue_err
    return 1
  fi
  
  _cleardomainconf  "Le_Vlist"
  
  Le_LinkIssuer=$(grep -i '^Link' $HTTP_HEADER | _head_n 1 | cut -d " " -f 2| cut -d ';' -f 1 | tr -d '<>' )
  if ! _contains "$Le_LinkIssuer" ":" ; then
    Le_LinkIssuer="$API$Le_LinkIssuer"
  fi
  
  _savedomainconf  "Le_LinkIssuer"  "$Le_LinkIssuer"
  
  if [ "$Le_LinkIssuer" ] ; then
    echo "$BEGIN_CERT" > "$CA_CERT_PATH"
    _get "$Le_LinkIssuer" | _base64 "multiline"  >> "$CA_CERT_PATH"
    echo "$END_CERT"  >> "$CA_CERT_PATH"
    _info "The intermediate CA cert is in $( __green " $CA_CERT_PATH ")"
    cat "$CA_CERT_PATH" >> "$CERT_FULLCHAIN_PATH"
    _info "And the full chain certs is there: $( __green " $CERT_FULLCHAIN_PATH ")"
  fi
  
  Le_CertCreateTime=$(_time)
  _savedomainconf  "Le_CertCreateTime"   "$Le_CertCreateTime"
  
  Le_CertCreateTimeStr=$(date -u )
  _savedomainconf  "Le_CertCreateTimeStr"  "$Le_CertCreateTimeStr"
  
  if [ -z "$Le_RenewalDays" ] || [ "$Le_RenewalDays" -lt "0" ] || [ "$Le_RenewalDays" -gt "$MAX_RENEW" ] ; then
    Le_RenewalDays=$MAX_RENEW
  else
    _savedomainconf  "Le_RenewalDays"   "$Le_RenewalDays"
  fi
  
  if [ "$CA_BUNDLE" ] ; then
    _saveaccountconf CA_BUNDLE "$CA_BUNDLE"
  else
    _clearaccountconf "CA_BUNDLE"
  fi

  if [ "$HTTPS_INSECURE" ] ; then
    _saveaccountconf HTTPS_INSECURE "$HTTPS_INSECURE"
  else
    _clearaccountconf  "HTTPS_INSECURE"
  fi

  if [ "$Le_Listen_V4" ] ; then
    _savedomainconf "Le_Listen_V4"     "$Le_Listen_V4"
    _cleardomainconf Le_Listen_V6
  elif [ "$Le_Listen_V6" ] ; then
    _savedomainconf "Le_Listen_V6"     "$Le_Listen_V6"
    _cleardomainconf Le_Listen_V4
  fi
  
  Le_NextRenewTime=$(_math $Le_CertCreateTime + $Le_RenewalDays \* 24 \* 60 \* 60)
  
  
  Le_NextRenewTimeStr=$( _time2str $Le_NextRenewTime )
  _savedomainconf  "Le_NextRenewTimeStr"  "$Le_NextRenewTimeStr"
  
  Le_NextRenewTime=$(_math $Le_NextRenewTime - 86400)
  _savedomainconf "Le_NextRenewTime"   "$Le_NextRenewTime"

  
  _on_issue_success

  if [ "$Le_RealCertPath$Le_RealKeyPath$Le_RealCACertPath$Le_ReloadCmd$Le_RealFullChainPath" ] ; then
    _installcert
  fi

}

#domain  [isEcc]
renew() {
  Le_Domain="$1"
  if [ -z "$Le_Domain" ] ; then
    _usage "Usage: $PROJECT_ENTRY --renew  -d domain.com [--ecc]"
    return 1
  fi

  _isEcc="$2"

  _initpath $Le_Domain "$_isEcc"

  _info "$(__green "Renew: '$Le_Domain'")"
  if [ ! -f "$DOMAIN_CONF" ] ; then
    _info "'$Le_Domain' is not a issued domain, skip."
    return 0;
  fi
  
  if [ "$Le_RenewalDays" ] ; then
    _savedomainconf Le_RenewalDays "$Le_RenewalDays"
  fi

  . "$DOMAIN_CONF"
  
  if [ "$Le_API" ] ; then
    API="$Le_API"
  fi
  
  if [ -z "$FORCE" ] && [ "$Le_NextRenewTime" ] && [ "$(_time)" -lt "$Le_NextRenewTime" ] ; then 
    _info "Skip, Next renewal time is: $(__green "$Le_NextRenewTimeStr")"
    _info "Add '$(__red '--force')' to force to renew."
    return $RENEW_SKIP
  fi
  
  IS_RENEW="1"
  issue "$Le_Webroot" "$Le_Domain" "$Le_Alt" "$Le_Keylength" "$Le_RealCertPath" "$Le_RealKeyPath" "$Le_RealCACertPath" "$Le_ReloadCmd" "$Le_RealFullChainPath" "$Le_PreHook" "$Le_PostHook" "$Le_RenewHook" "$Le_LocalAddress"
  res=$?
  if [ "$res" != "0" ] ; then
    return $res
  fi
  
  if [ "$Le_DeployHook" ] ; then
    deploy $Le_Domain "$Le_DeployHook" "$Le_Keylength"
    res=$?
  fi
  
  IS_RENEW=""

  return $res
}

#renewAll  [stopRenewOnError]
renewAll() {
  _initpath
  _stopRenewOnError="$1"
  _debug "_stopRenewOnError" "$_stopRenewOnError"
  _ret="0"

  for d in $(ls -F ${CERT_HOME}/ | grep [^.].*[.].*/$ ) ; do
    d=$(echo $d | cut -d '/' -f 1)
    (
      if _endswith $d "$ECC_SUFFIX" ; then
        _isEcc=$(echo $d | cut -d "$ECC_SEP" -f 2)
        d=$(echo $d | cut -d "$ECC_SEP" -f 1)
      fi
      renew "$d" "$_isEcc"
    )
    rc="$?"
    _debug "Return code: $rc"
    if [ "$rc" != "0" ] ; then
      if [ "$rc" = "$RENEW_SKIP" ] ; then
        _info "Skipped $d"
      elif [ "$_stopRenewOnError" ] ; then
        _err "Error renew $d,  stop now."
        return $rc
      else
        _ret="$rc"
        _err "Error renew $d, Go ahead to next one."
      fi
    fi
  done
  return $_ret
}


#csr webroot
signcsr(){
  _csrfile="$1"
  _csrW="$2"
  if [ -z "$_csrfile" ] || [ -z "$_csrW" ]; then
    _usage "Usage: $PROJECT_ENTRY --signcsr  --csr mycsr.csr  -w /path/to/webroot/a.com/ "
    return 1
  fi

  _initpath

  _csrsubj=$(_readSubjectFromCSR "$_csrfile")
  if [ "$?" != "0" ] ; then
    _err "Can not read subject from csr: $_csrfile"
    return 1
  fi
  _debug _csrsubj "$_csrsubj"

  _csrdomainlist=$(_readSubjectAltNamesFromCSR "$_csrfile")
  if [ "$?" != "0" ] ; then
    _err "Can not read domain list from csr: $_csrfile"
    return 1
  fi
  _debug "_csrdomainlist" "$_csrdomainlist"
  
    
  if [ -z "$_csrsubj" ] ; then
    _csrsubj="$(_getfield "$_csrdomainlist" 1)"
    _debug _csrsubj "$_csrsubj"
    _csrdomainlist="$(echo "$_csrdomainlist" | cut -d , -f 2-)"
    _debug "_csrdomainlist" "$_csrdomainlist"
  fi
  
  if [ -z "$_csrsubj" ] ; then
    _err "Can not read subject from csr: $_csrfile"
    return 1
  fi
  
  _csrkeylength=$(_readKeyLengthFromCSR "$_csrfile")
  if [ "$?" != "0" ] || [ -z "$_csrkeylength" ] ; then
    _err "Can not read key length from csr: $_csrfile"
    return 1
  fi
  
  _initpath "$_csrsubj" "$_csrkeylength"
  mkdir -p "$DOMAIN_PATH"
  
  _info "Copy csr to: $CSR_PATH"
  cp "$_csrfile" "$CSR_PATH"
  
  issue "$_csrW" "$_csrsubj" "$_csrdomainlist" "$_csrkeylength"
  
}

showcsr() {
 _csrfile="$1"
  _csrd="$2"
  if [ -z "$_csrfile" ] && [ -z "$_csrd" ]; then
    _usage "Usage: $PROJECT_ENTRY --showcsr  --csr mycsr.csr"
    return 1
  fi

  _initpath
  
  _csrsubj=$(_readSubjectFromCSR "$_csrfile")
  if [ "$?" != "0" ] || [ -z "$_csrsubj" ] ; then
    _err "Can not read subject from csr: $_csrfile"
    return 1
  fi
  
  _info "Subject=$_csrsubj"

  _csrdomainlist=$(_readSubjectAltNamesFromCSR "$_csrfile")
  if [ "$?" != "0" ] ; then
    _err "Can not read domain list from csr: $_csrfile"
    return 1
  fi
  _debug "_csrdomainlist" "$_csrdomainlist"

  _info "SubjectAltNames=$_csrdomainlist"


  _csrkeylength=$(_readKeyLengthFromCSR "$_csrfile")
  if [ "$?" != "0" ] || [ -z "$_csrkeylength" ] ; then
    _err "Can not read key length from csr: $_csrfile"
    return 1
  fi
  _info "KeyLength=$_csrkeylength"
}

list() {
  _raw="$1"
  _initpath
  
  _sep="|"
  if [ "$_raw" ] ; then
    printf  "Main_Domain${_sep}KeyLength${_sep}SAN_Domains${_sep}Created${_sep}Renew\n"
    for d in $(ls -F ${CERT_HOME}/ | grep [^.].*[.].*/$ ) ; do
      d=$(echo $d | cut -d '/' -f 1)
      (
        if _endswith $d "$ECC_SUFFIX" ; then
          _isEcc=$(echo $d | cut -d "$ECC_SEP" -f 2)
          d=$(echo $d | cut -d "$ECC_SEP" -f 1)
        fi
        _initpath $d "$_isEcc"
        if [ -f "$DOMAIN_CONF" ] ; then
          . "$DOMAIN_CONF"
          printf "$Le_Domain${_sep}\"$Le_Keylength\"${_sep}$Le_Alt${_sep}$Le_CertCreateTimeStr${_sep}$Le_NextRenewTimeStr\n"
        fi
      )
    done
  else
    if _exists column ; then
      list "raw" | column -t -s "$_sep"
    else
      list "raw" | tr "$_sep" '\t'
    fi
  fi


}

deploy() {
  Le_Domain="$1"
  Le_DeployHook="$2"
  _isEcc="$3"
  if [ -z "$Le_DeployHook" ] ; then
    _usage "Usage: $PROJECT_ENTRY --deploy -d domain.com --deploy-hook cpanel [--ecc] "
    return 1
  fi

  _initpath $Le_Domain "$_isEcc"
  if [ ! -d "$DOMAIN_PATH" ] ; then
    _err "Domain is not valid:'$Le_Domain'"
    return 1
  fi

  _deployApi="$(_findHook $Le_Domain deploy $Le_DeployHook)"
  if [ -z "$_deployApi" ] ; then
    _err "The deploy hook $Le_DeployHook is not found."
    return 1
  fi
  _debug _deployApi "$_deployApi"
  
  _savedomainconf Le_DeployHook "$Le_DeployHook"
  
  if ! (
    if ! . $_deployApi ; then
      _err "Load file $_deployApi error. Please check your api file and try again."
      return 1
    fi
    
    d_command="${Le_DeployHook}_deploy"
    if ! _exists $d_command ; then 
      _err "It seems that your api file is not correct, it must have a function named: $d_command"
      return 1
    fi
    
    if ! $d_command $Le_Domain "$CERT_KEY_PATH" "$CERT_PATH" "$CA_CERT_PATH" "$CERT_FULLCHAIN_PATH" ; then
      _err "Error deploy for domain:$Le_Domain"
      _on_issue_err
      return 1
    fi
  ) ; then
    _err "Deploy error."
    return 1
  else
    _info "$(__green Success)"
  fi
  
}

installcert() {
  Le_Domain="$1"
  if [ -z "$Le_Domain" ] ; then
    _usage "Usage: $PROJECT_ENTRY --installcert -d domain.com  [--ecc] [--certpath cert-file-path]  [--keypath key-file-path]  [--capath ca-cert-file-path]   [ --reloadCmd reloadCmd] [--fullchainpath fullchain-path]"
    return 1
  fi

  Le_RealCertPath="$2"
  Le_RealKeyPath="$3"
  Le_RealCACertPath="$4"
  Le_ReloadCmd="$5"
  Le_RealFullChainPath="$6"
  _isEcc="$7"

  _initpath $Le_Domain "$_isEcc"
  if [ ! -d "$DOMAIN_PATH" ] ; then
    _err "Domain is not valid:'$Le_Domain'"
    return 1
  fi

  _installcert
}


_installcert() {

  _savedomainconf "Le_RealCertPath"         "$Le_RealCertPath"
  _savedomainconf "Le_RealCACertPath"       "$Le_RealCACertPath"
  _savedomainconf "Le_RealKeyPath"          "$Le_RealKeyPath"
  _savedomainconf "Le_ReloadCmd"            "$Le_ReloadCmd"
  _savedomainconf "Le_RealFullChainPath"    "$Le_RealFullChainPath"
  
  if [ "$Le_RealCertPath" = "$NO_VALUE" ] ; then
    Le_RealCertPath=""
  fi
  if [ "$Le_RealKeyPath" = "$NO_VALUE" ] ; then
    Le_RealKeyPath=""
  fi
  if [ "$Le_RealCACertPath" = "$NO_VALUE" ] ; then
    Le_RealCACertPath=""
  fi
  if [ "$Le_ReloadCmd" = "$NO_VALUE" ] ; then
    Le_ReloadCmd=""
  fi
  if [ "$Le_RealFullChainPath" = "$NO_VALUE" ] ; then
    Le_RealFullChainPath=""
  fi
  
  _installed="0"
  if [ "$Le_RealCertPath" ] ; then
    _installed=1
    _info "Installing cert to:$Le_RealCertPath"
    if [ -f "$Le_RealCertPath" ] && [ ! "$IS_RENEW" ] ; then
      cp "$Le_RealCertPath" "$Le_RealCertPath".bak
    fi
    cat "$CERT_PATH" > "$Le_RealCertPath"
  fi
  
  if [ "$Le_RealCACertPath" ] ; then
    _installed=1
    _info "Installing CA to:$Le_RealCACertPath"
    if [ "$Le_RealCACertPath" = "$Le_RealCertPath" ] ; then
      echo "" >> "$Le_RealCACertPath"
      cat "$CA_CERT_PATH" >> "$Le_RealCACertPath"
    else
      if [ -f "$Le_RealCACertPath" ] && [ ! "$IS_RENEW" ] ; then
        cp "$Le_RealCACertPath" "$Le_RealCACertPath".bak
      fi
      cat "$CA_CERT_PATH" > "$Le_RealCACertPath"
    fi
  fi


  if [ "$Le_RealKeyPath" ] ; then
    _installed=1
    _info "Installing key to:$Le_RealKeyPath"
    if [ -f "$Le_RealKeyPath" ] && [ ! "$IS_RENEW" ] ; then
      cp "$Le_RealKeyPath" "$Le_RealKeyPath".bak
    fi
    cat "$CERT_KEY_PATH" > "$Le_RealKeyPath"
  fi
  
  if [ "$Le_RealFullChainPath" ] ; then
    _installed=1
    _info "Installing full chain to:$Le_RealFullChainPath"
    if [ -f "$Le_RealFullChainPath" ] && [ ! "$IS_RENEW" ] ; then
      cp "$Le_RealFullChainPath" "$Le_RealFullChainPath".bak
    fi
    cat "$CERT_FULLCHAIN_PATH" > "$Le_RealFullChainPath"
  fi  

  if [ "$Le_ReloadCmd" ] ; then
    _installed=1
    _info "Run Le_ReloadCmd: $Le_ReloadCmd"
    if (cd "$DOMAIN_PATH" && eval "$Le_ReloadCmd") ; then
      _info "$(__green "Reload success")"
    else
      _err "Reload error for :$Le_Domain"
    fi
  fi


}

installcronjob() {
  _initpath
  if ! _exists "crontab" ; then
    _err "crontab doesn't exist, so, we can not install cron jobs."
    _err "All your certs will not be renewed automatically."
    _err "You must add your own cron job to call '$PROJECT_ENTRY --cron' everyday."
    return 1
  fi

  _info "Installing cron job"
  if ! crontab -l | grep "$PROJECT_ENTRY --cron" ; then 
    if [ -f "$LE_WORKING_DIR/$PROJECT_ENTRY" ] ; then
      lesh="\"$LE_WORKING_DIR\"/$PROJECT_ENTRY"
    else
      _err "Can not install cronjob, $PROJECT_ENTRY not found."
      return 1
    fi
    if _exists uname && uname -a | grep solaris >/dev/null ; then
      crontab -l | { cat; echo "0 0 * * * $lesh --cron --home \"$LE_WORKING_DIR\" > /dev/null"; } | crontab --
    else
      crontab -l | { cat; echo "0 0 * * * $lesh --cron --home \"$LE_WORKING_DIR\" > /dev/null"; } | crontab -
    fi
  fi
  if [ "$?" != "0" ] ; then
    _err "Install cron job failed. You need to manually renew your certs."
    _err "Or you can add cronjob by yourself:"
    _err "$lesh --cron --home \"$LE_WORKING_DIR\" > /dev/null"
    return 1
  fi
}

uninstallcronjob() {
  if ! _exists "crontab" ; then
    return
  fi
  _info "Removing cron job"
  cr="$(crontab -l | grep "$PROJECT_ENTRY --cron")"
  if [ "$cr" ] ; then 
    if _exists uname && uname -a | grep solaris >/dev/null ; then
      crontab -l | sed "/$PROJECT_ENTRY --cron/d" | crontab --
    else
      crontab -l | sed "/$PROJECT_ENTRY --cron/d" | crontab -
    fi
    LE_WORKING_DIR="$(echo "$cr" | cut -d ' ' -f 9 | tr -d '"')"
    _info LE_WORKING_DIR "$LE_WORKING_DIR"
  fi 
  _initpath

}

revoke() {
  Le_Domain="$1"
  if [ -z "$Le_Domain" ] ; then
    _usage "Usage: $PROJECT_ENTRY --revoke -d domain.com"
    return 1
  fi
  
  _isEcc="$2"

  _initpath $Le_Domain "$_isEcc"
  if [ ! -f "$DOMAIN_CONF" ] ; then
    _err "$Le_Domain is not a issued domain, skip."
    return 1;
  fi
  
  if [ ! -f "$CERT_PATH" ] ; then
    _err "Cert for $Le_Domain $CERT_PATH is not found, skip."
    return 1
  fi
  
  cert="$(_getfile "${CERT_PATH}" "${BEGIN_CERT}" "${END_CERT}"| tr -d "\r\n" | _urlencode)"

  if [ -z "$cert" ] ; then
    _err "Cert for $Le_Domain is empty found, skip."
    return 1
  fi
  
  data="{\"resource\": \"revoke-cert\", \"certificate\": \"$cert\"}"
  uri="$API/acme/revoke-cert"

  if [ -f "$CERT_KEY_PATH" ] ; then
    _info "Try domain key first."
    if _send_signed_request $uri "$data" "" "$CERT_KEY_PATH"; then
      if [ -z "$response" ] ; then
        _info "Revoke success."
        rm -f $CERT_PATH
        return 0
      else 
        _err "Revoke error by domain key."
        _err "$response"
      fi
    fi
  else 
    _info "Domain key file doesn't exists."
  fi
  
  _info "Try account key."

  if _send_signed_request $uri "$data" "" "$ACCOUNT_KEY_PATH" ; then
    if [ -z "$response" ] ; then
      _info "Revoke success."
      rm -f $CERT_PATH
      return 0
    else 
      _err "Revoke error."
      _debug "$response"
    fi
  fi
  return 1
}


#domain vtype
_deactivate() {
  _d_domain="$1"
  _d_type="$2"
  _initpath
  
  _d_i=0
  _d_max_retry=9
  while [ "$_d_i" -lt "$_d_max_retry" ] ;
  do
    _info "Deactivate: $_d_domain"
    _d_i="$(_math $_d_i + 1)"
    
    
    if ! __get_domain_new_authz "$_d_domain" ; then
      _err "Can not get domain new authz token."
      return 1
    fi
    
    authzUri="$(echo "$responseHeaders" | grep "^Location:" | _head_n 1 | cut -d ' ' -f 2 | tr -d "\r\n")"
    _debug "authzUri" "$authzUri"

    if [ ! -z "$code" ] && [ ! "$code" = '201' ] ; then
      _err "new-authz error: $response"
      return 1
    fi
    
    entry="$(printf "%s\n" "$response" | _egrep_o  '[^\{]*"status":"valid","uri"[^\}]*')"
    _debug entry "$entry"
    
    if [ -z "$entry" ] ; then
      _info "No more valid entry found."
      break
    fi
    
    _vtype="$(printf "%s\n" "$entry" | _egrep_o '"type": *"[^"]*"' | cut -d : -f 2 | tr -d '"')"
    _debug _vtype $_vtype
    _info "Found $_vtype"

    
    uri="$(printf "%s\n" "$entry" | _egrep_o '"uri":"[^"]*'| cut -d : -f 2,3 | tr -d '"' )"
    _debug uri $uri
    
    if [ "$_d_type" ] && [ "$_d_type" != "$_vtype" ] ; then
      _info "Skip $_vtype"
      continue
    fi
    
    _info "Deactivate: $_vtype"
    
    if ! _send_signed_request "$authzUri" "{\"resource\": \"authz\", \"status\":\"deactivated\"}" ; then
      _err "Can not deactivate $_vtype."
      return 1
    fi
    
    _info "Deactivate: $_vtype success."
    
  done
  _debug "$_d_i"
  if [ "$_d_i" -lt "$_d_max_retry" ] ; then
    _info "Deactivated success!"
  else
    _err "Deactivate failed."
  fi

}

deactivate() {
  _d_domain_list="$1"
  _d_type="$2"
  _initpath
  _debug _d_domain_list "$_d_domain_list"
  if [ -z "$(echo $_d_domain_list | cut -d , -f 1 )" ] ; then
    _usage "Usage: $PROJECT_ENTRY --deactivate -d domain.com [-d domain.com]"
    return 1
  fi
  for _d_dm in $(echo "$_d_domain_list" |  tr ',' ' ' ) ; 
  do
    if [ -z "$_d_dm" ] || [ "$_d_dm" = "$NO_VALUE" ] ; then
      continue
    fi
    if ! _deactivate "$_d_dm" $_d_type ; then
      return 1
    fi
  done
}

# Detect profile file if not specified as environment variable
_detect_profile() {
  if [ -n "$PROFILE" -a -f "$PROFILE" ] ; then
    echo "$PROFILE"
    return
  fi

  DETECTED_PROFILE=''
  SHELLTYPE="$(basename "/$SHELL")"

  if [ "$SHELLTYPE" = "bash" ] ; then
    if [ -f "$HOME/.bashrc" ] ; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ] ; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    fi
  elif [ "$SHELLTYPE" = "zsh" ] ; then
    DETECTED_PROFILE="$HOME/.zshrc"
  fi

  if [ -z "$DETECTED_PROFILE" ] ; then
    if [ -f "$HOME/.profile" ] ; then
      DETECTED_PROFILE="$HOME/.profile"
    elif [ -f "$HOME/.bashrc" ] ; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ] ; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    elif [ -f "$HOME/.zshrc" ] ; then
      DETECTED_PROFILE="$HOME/.zshrc"
    fi
  fi

  if [ ! -z "$DETECTED_PROFILE" ] ; then
    echo "$DETECTED_PROFILE"
  fi
}

_initconf() {
  _initpath
  if [ ! -f "$ACCOUNT_CONF_PATH" ] ; then
    echo "#ACCOUNT_CONF_PATH=xxxx

#Account configurations:
#Here are the supported macros, uncomment them to make them take effect.

#ACCOUNT_EMAIL=aaa@example.com  # the account email used to register account.
#ACCOUNT_KEY_PATH=\"/path/to/account.key\"
#CERT_HOME=\"/path/to/cert/home\"



#LOG_FILE=\"$DEFAULT_LOG_FILE\"
#LOG_LEVEL=1

#AUTO_UPGRADE=\"1\"

#STAGE=1 # Use the staging api
#FORCE=1 # Force to issue cert
#DEBUG=1 # Debug mode


#USER_AGENT=\"$USER_AGENT\"

#USER_PATH=""

#dns api
#######################
#Cloudflare:
#api key
#CF_Key=\"sdfsdfsdfljlbjkljlkjsdfoiwje\"
#account email
#CF_Email=\"xxxx@sss.com\"

#######################
#Dnspod.cn:
#api key id
#DP_Id=\"1234\"
#api key
#DP_Key=\"sADDsdasdgdsf\"

#######################
#Cloudxns.com:
#CX_Key=\"1234\"
#
#CX_Secret=\"sADDsdasdgdsf\"

#######################
#Godaddy.com:
#GD_Key=\"sdfdsgdgdfdasfds\"
#
#GD_Secret=\"sADDsdasdfsdfdssdgdsf\"

#######################
#PowerDNS:
#PDNS_Url=\"http://ns.example.com:8081\"
#PDNS_ServerId=\"localhost\"
#PDNS_Token=\"0123456789ABCDEF\"
#PDNS_Ttl=60

    " > $ACCOUNT_CONF_PATH
  fi
}

# nocron
_precheck() {
  _nocron="$1"
  
  if ! _exists "curl"  && ! _exists "wget"; then
    _err "Please install curl or wget first, we need to access http resources."
    return 1
  fi
  
  if [ -z "$_nocron" ] ; then
    if ! _exists "crontab" ; then
      _err "It is recommended to install crontab first. try to install 'cron, crontab, crontabs or vixie-cron'."
      _err "We need to set cron job to renew the certs automatically."
      _err "Otherwise, your certs will not be able to be renewed automatically."
      if [ -z "$FORCE" ] ; then
        _err "Please add '--force' and try install again to go without crontab."
        _err "./$PROJECT_ENTRY --install --force"
        return 1
      fi
    fi
  fi
  
  if ! _exists "openssl" ; then
    _err "Please install openssl first."
    _err "We need openssl to generate keys."
    return 1
  fi
  
  if ! _exists "nc" ; then
    _err "It is recommended to install nc first, try to install 'nc' or 'netcat'."
    _err "We use nc for standalone server if you use standalone mode."
    _err "If you don't use standalone mode, just ignore this warning."
  fi
  
  return 0
}

_setShebang() {
  _file="$1"
  _shebang="$2"
  if [ -z "$_shebang" ] ; then
    _usage "Usage: file shebang"
    return 1
  fi
  cp "$_file" "$_file.tmp"
  echo "$_shebang" > "$_file"
  sed -n 2,99999p  "$_file.tmp" >> "$_file"
  rm -f "$_file.tmp"  
}

_installalias() {
  _initpath

  _envfile="$LE_WORKING_DIR/$PROJECT_ENTRY.env"
  if [ "$_upgrading" ] && [ "$_upgrading" = "1" ] ; then
    echo "$(cat $_envfile)" | sed "s|^LE_WORKING_DIR.*$||" > "$_envfile"
    echo "$(cat $_envfile)" | sed "s|^alias le.*$||" > "$_envfile"
    echo "$(cat $_envfile)" | sed "s|^alias le.sh.*$||" > "$_envfile"
  fi

  _setopt "$_envfile" "export LE_WORKING_DIR" "=" "\"$LE_WORKING_DIR\""
  _setopt "$_envfile" "alias $PROJECT_ENTRY" "=" "\"$LE_WORKING_DIR/$PROJECT_ENTRY\""

  _profile="$(_detect_profile)"
  if [ "$_profile" ] ; then
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
  if [ -f "$_csh_profile" ] ; then
    _info "Installing alias to '$_csh_profile'"
    _setopt "$_cshfile" "setenv LE_WORKING_DIR" " " "\"$LE_WORKING_DIR\""
    _setopt "$_cshfile" "alias $PROJECT_ENTRY" " " "\"$LE_WORKING_DIR/$PROJECT_ENTRY\""
    _setopt "$_csh_profile"  "source \"$_cshfile\""
  fi
  
  #for tcsh
  _tcsh_profile="$HOME/.tcshrc"
  if [ -f "$_tcsh_profile" ] ; then
    _info "Installing alias to '$_tcsh_profile'"
    _setopt "$_cshfile" "setenv LE_WORKING_DIR" " " "\"$LE_WORKING_DIR\""
    _setopt "$_cshfile" "alias $PROJECT_ENTRY" " " "\"$LE_WORKING_DIR/$PROJECT_ENTRY\""
    _setopt "$_tcsh_profile"  "source \"$_cshfile\""
  fi

}

# nocron
install() {

  if [ -z "$LE_WORKING_DIR" ] ; then
    LE_WORKING_DIR="$DEFAULT_INSTALL_HOME"
  fi
  
  _nocron="$1"
  if ! _initpath ; then
    _err "Install failed."
    return 1
  fi
  if [ "$_nocron" ] ; then
    _debug "Skip install cron job"
  fi
  
  if ! _precheck "$_nocron" ; then
    _err "Pre-check failed, can not install."
    return 1
  fi
  
  #convert from le
  if [ -d "$HOME/.le" ] ; then
    for envfile in "le.env" "le.sh.env"
    do
      if [ -f "$HOME/.le/$envfile" ] ; then
        if grep "le.sh" "$HOME/.le/$envfile" >/dev/null ; then
            _upgrading="1"
            _info "You are upgrading from le.sh"
            _info "Renaming \"$HOME/.le\" to $LE_WORKING_DIR"
            mv "$HOME/.le" "$LE_WORKING_DIR"
            mv "$LE_WORKING_DIR/$envfile" "$LE_WORKING_DIR/$PROJECT_ENTRY.env"
          break;
        fi
      fi
    done
  fi

  _info "Installing to $LE_WORKING_DIR"

  if ! mkdir -p "$LE_WORKING_DIR" ; then
    _err "Can not create working dir: $LE_WORKING_DIR"
    return 1
  fi
  
  chmod 700 "$LE_WORKING_DIR"

  cp $PROJECT_ENTRY "$LE_WORKING_DIR/" && chmod +x "$LE_WORKING_DIR/$PROJECT_ENTRY"

  if [ "$?" != "0" ] ; then
    _err "Install failed, can not copy $PROJECT_ENTRY"
    return 1
  fi

  _info "Installed to $LE_WORKING_DIR/$PROJECT_ENTRY"

  _installalias

  for subf in $_SUB_FOLDERS ; do
    if [ -d "$subf" ] ; then
      mkdir -p $LE_WORKING_DIR/$subf
      cp  $subf/* $LE_WORKING_DIR/$subf/
    fi
  done


  if [ ! -f "$ACCOUNT_CONF_PATH" ] ; then
    _initconf
  fi

  if [ "$_DEFAULT_ACCOUNT_CONF_PATH" != "$ACCOUNT_CONF_PATH" ] ; then
    _setopt "$_DEFAULT_ACCOUNT_CONF_PATH" "ACCOUNT_CONF_PATH" "=" "\"$ACCOUNT_CONF_PATH\""
  fi

  if [ "$_DEFAULT_CERT_HOME" != "$CERT_HOME" ] ; then
    _saveaccountconf "CERT_HOME" "$CERT_HOME"
  fi

  if [ "$_DEFAULT_ACCOUNT_KEY_PATH" != "$ACCOUNT_KEY_PATH" ] ; then
    _saveaccountconf "ACCOUNT_KEY_PATH" "$ACCOUNT_KEY_PATH"
  fi
  
  if [ -z "$_nocron" ] ; then
    installcronjob
  fi

  if [ -z "$NO_DETECT_SH" ] ; then
    #Modify shebang
    if _exists bash ; then
      _info "Good, bash is found, so change the shebang to use bash as prefered."
      _shebang='#!/usr/bin/env bash'
      _setShebang "$LE_WORKING_DIR/$PROJECT_ENTRY" "$_shebang"
      for subf in $_SUB_FOLDERS ; do
        if [ -d "$LE_WORKING_DIR/$subf" ] ; then
          for _apifile in "$LE_WORKING_DIR/$subf/"*.sh ; do
            _setShebang "$_apifile" "$_shebang"
          done
        fi
      done
    fi
  fi

  _info OK
}

# nocron
uninstall() {
  _nocron="$1"
  if [ -z "$_nocron" ] ; then
    uninstallcronjob
  fi
  _initpath

  _uninstallalias
  
  rm -f $LE_WORKING_DIR/$PROJECT_ENTRY
  _info "The keys and certs are in $LE_WORKING_DIR, you can remove them by yourself."

}

_uninstallalias() {
  _initpath

  _profile="$(_detect_profile)"
  if [ "$_profile" ] ; then
    _info "Uninstalling alias from: '$_profile'"
    text="$(cat $_profile)"
    echo "$text" | sed "s|^.*\"$LE_WORKING_DIR/$PROJECT_NAME.env\"$||" > "$_profile"
  fi

  _csh_profile="$HOME/.cshrc"
  if [ -f "$_csh_profile" ] ; then
    _info "Uninstalling alias from: '$_csh_profile'"
    text="$(cat $_csh_profile)"
    echo "$text" | sed "s|^.*\"$LE_WORKING_DIR/$PROJECT_NAME.csh\"$||" > "$_csh_profile"
  fi
  
  _tcsh_profile="$HOME/.tcshrc"
  if [ -f "$_tcsh_profile" ] ; then
    _info "Uninstalling alias from: '$_csh_profile'"
    text="$(cat $_tcsh_profile)"
    echo "$text" | sed "s|^.*\"$LE_WORKING_DIR/$PROJECT_NAME.csh\"$||" > "$_tcsh_profile"
  fi

}

cron() {
  IN_CRON=1
  _initpath
  if [ "$AUTO_UPGRADE" = "1" ] ; then
    export LE_WORKING_DIR
    (
     if ! upgrade ; then
       _err "Cron:Upgrade failed!"
       return 1
     fi
    )
    . $LE_WORKING_DIR/$PROJECT_ENTRY >/dev/null

    if [ -t 1 ] ; then
      __INTERACTIVE="1"
    fi
    
    _info "Auto upgraded to: $VER"
  fi
  renewAll
  _ret="$?"
  IN_CRON=""
  exit $_ret
}

version() {
  echo "$PROJECT"
  echo "v$VER"
}

showhelp() {
  _initpath
  version
  echo "Usage: $PROJECT_ENTRY  command ...[parameters]....
Commands:
  --help, -h               Show this help message.
  --version, -v            Show version info.
  --install                Install $PROJECT_NAME to your system.
  --uninstall              Uninstall $PROJECT_NAME, and uninstall the cron job.
  --upgrade                Upgrade $PROJECT_NAME to the latest code from $PROJECT .
  --issue                  Issue a cert.
  --signcsr                Issue a cert from an existing csr.
  --deploy                 Deploy the cert to your server.
  --installcert            Install the issued cert to apache/nginx or any other server.
  --renew, -r              Renew a cert.
  --renewAll               Renew all the certs.
  --revoke                 Revoke a cert.
  --list                   List all the certs.
  --showcsr                Show the content of a csr.
  --installcronjob         Install the cron job to renew certs, you don't need to call this. The 'install' command can automatically install the cron job.
  --uninstallcronjob       Uninstall the cron job. The 'uninstall' command can do this automatically.
  --cron                   Run cron job to renew all the certs.
  --toPkcs                 Export the certificate and key to a pfx file.
  --updateaccount          Update account info.
  --registeraccount        Register account key.
  --createAccountKey, -cak Create an account private key, professional use.
  --createDomainKey, -cdk  Create an domain private key, professional use.
  --createCSR, -ccsr       Create CSR , professional use.
  --deactivate             Deactivate the domain authz, professional use.
  
Parameters:
  --domain, -d   domain.tld         Specifies a domain, used to issue, renew or revoke etc.
  --force, -f                       Used to force to install or force to renew a cert immediately.
  --staging, --test                 Use staging server, just for test.
  --debug                           Output debug info.
    
  --webroot, -w  /path/to/webroot   Specifies the web root folder for web root mode.
  --standalone                      Use standalone mode.
  --tls                             Use standalone tls mode.
  --apache                          Use apache mode.
  --dns [dns_cf|dns_dp|dns_cx|/path/to/api/file]   Use dns mode or dns api.
  --dnssleep  [$DEFAULT_DNS_SLEEP]                  The time in seconds to wait for all the txt records to take effect in dns api mode. Default $DEFAULT_DNS_SLEEP seconds.
  
  --keylength, -k [2048]            Specifies the domain key length: 2048, 3072, 4096, 8192 or ec-256, ec-384.
  --accountkeylength, -ak [2048]    Specifies the account key length.
  --log    [/path/to/logfile]       Specifies the log file. The default is: \"$DEFAULT_LOG_FILE\" if you don't give a file path here.
  --log-level 1|2                   Specifies the log level, default is 1.
  
  These parameters are to install the cert to nginx/apache or anyother server after issue/renew a cert:
  
  --certpath /path/to/real/cert/file  After issue/renew, the cert will be copied to this path.
  --keypath /path/to/real/key/file  After issue/renew, the key will be copied to this path.
  --capath /path/to/real/ca/file    After issue/renew, the intermediate cert will be copied to this path.
  --fullchainpath /path/to/fullchain/file After issue/renew, the fullchain cert will be copied to this path.
  
  --reloadcmd \"service nginx reload\" After issue/renew, it's used to reload the server.

  --accountconf                     Specifies a customized account config file.
  --home                            Specifies the home dir for $PROJECT_NAME .
  --certhome                        Specifies the home dir to save all the certs, only valid for '--install' command.
  --useragent                       Specifies the user agent string. it will be saved for future use too.
  --accountemail                    Specifies the account email for registering, Only valid for the '--install' command.
  --accountkey                      Specifies the account key path, Only valid for the '--install' command.
  --days                            Specifies the days to renew the cert when using '--issue' command. The max value is $MAX_RENEW days.
  --httpport                        Specifies the standalone listening port. Only valid if the server is behind a reverse proxy or load balancer.
  --tlsport                         Specifies the standalone tls listening port. Only valid if the server is behind a reverse proxy or load balancer.
  --local-address                   Specifies the standalone/tls server listening address, in case you have multiple ip addresses.
  --listraw                         Only used for '--list' command, list the certs in raw format.
  --stopRenewOnError, -se           Only valid for '--renewall' command. Stop if one cert has error in renewal.
  --insecure                        Do not check the server certificate, in some devices, the api server's certificate may not be trusted.
  --ca-bundle                       Specifices the path to the CA certificate bundle to verify api server's certificate.
  --nocron                          Only valid for '--install' command, which means: do not install the default cron job. In this case, the certs will not be renewed automatically.
  --ecc                             Specifies to use the ECC cert. Valid for '--installcert', '--renew', '--revoke', '--toPkcs' and '--createCSR'
  --csr                             Specifies the input csr.
  --pre-hook                        Command to be run before obtaining any certificates.
  --post-hook                       Command to be run after attempting to obtain/renew certificates. No matter the obain/renew is success or failed.
  --renew-hook                      Command to be run once for each successfully renewed certificate.
  --deploy-hook                     The hook file to deploy cert
  --ocsp-must-staple, --ocsp        Generate ocsp must Staple extension.
  --auto-upgrade   [0|1]            Valid for '--upgrade' command, indicating whether to upgrade automatically in future.
  --listen-v4                       Force standalone/tls server to listen at ipv4.
  --listen-v6                       Force standalone/tls server to listen at ipv6.
  "
}

# nocron
_installOnline() {
  _info "Installing from online archive."
  _nocron="$1"
  if [ ! "$BRANCH" ] ; then
    BRANCH="master"
  fi

  target="$PROJECT/archive/$BRANCH.tar.gz"
  _info "Downloading $target"
  localname="$BRANCH.tar.gz"
  if ! _get "$target" > $localname ; then
    _err "Download error."
    return 1
  fi
  (
  _info "Extracting $localname"
  tar xzf $localname
  
  cd "$PROJECT_NAME-$BRANCH"
  chmod +x $PROJECT_ENTRY
  if ./$PROJECT_ENTRY install "$_nocron" ; then
    _info "Install success!"
  fi
  
  cd ..
  
  rm -rf "$PROJECT_NAME-$BRANCH"
  rm -f "$localname"
  )
}

upgrade() {
  if (
    _initpath
    export LE_WORKING_DIR
    cd "$LE_WORKING_DIR"
    _installOnline "nocron"
  ) ; then
    _info "Upgrade success!"
    exit 0
  else
    _err "Upgrade failed!"
    exit 1
  fi
}

_processAccountConf() {
  if [ "$_useragent" ] ; then
    _saveaccountconf "USER_AGENT" "$_useragent"
  elif [ "$USER_AGENT" ] && [ "$USER_AGENT" != "$DEFAULT_USER_AGENT" ] ; then
    _saveaccountconf "USER_AGENT" "$USER_AGENT"
  fi
  
  if [ "$_accountemail" ] ; then
    _saveaccountconf "ACCOUNT_EMAIL" "$_accountemail"
  elif [ "$ACCOUNT_EMAIL" ] && [ "$ACCOUNT_EMAIL" != "$DEFAULT_ACCOUNT_EMAIL" ] ; then
    _saveaccountconf "ACCOUNT_EMAIL" "$ACCOUNT_EMAIL"
  fi
  
  if [ "$_auto_upgrade" ] ; then
    _saveaccountconf "AUTO_UPGRADE" "$_auto_upgrade"
  elif [ "$AUTO_UPGRADE" ] ; then
    _saveaccountconf "AUTO_UPGRADE" "$AUTO_UPGRADE"
  fi
  
}

_process() {
  _CMD=""
  _domain=""
  _altdomains="$NO_VALUE"
  _webroot=""
  _keylength=""
  _accountkeylength=""
  _certpath=""
  _keypath=""
  _capath=""
  _fullchainpath=""
  _reloadcmd=""
  _password=""
  _accountconf=""
  _useragent=""
  _accountemail=""
  _accountkey=""
  _certhome=""
  _httpport=""
  _tlsport=""
  _dnssleep=""
  _listraw=""
  _stopRenewOnError=""
  _insecure=""
  _ca_bundle=""
  _nocron=""
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
  while [ ${#} -gt 0 ] ; do
    case "${1}" in
    
    --help|-h)
        showhelp
        return
        ;;
    --version|-v)
        version
        return
        ;;
    --install)
        _CMD="install"
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
    --signcsr)
        _CMD="signcsr"
        ;;
    --showcsr)
        _CMD="showcsr"
        ;;
    --installcert|-i)
        _CMD="installcert"
        ;;
    --renew|-r)
        _CMD="renew"
        ;;
    --renewAll|--renewall)
        _CMD="renewAll"
        ;;
    --revoke)
        _CMD="revoke"
        ;;
    --list)
        _CMD="list"
        ;;
    --installcronjob)
        _CMD="installcronjob"
        ;;
    --uninstallcronjob)
        _CMD="uninstallcronjob"
        ;;
    --cron)
        _CMD="cron"
        ;;
    --toPkcs)
        _CMD="toPkcs"
        ;; 
    --createAccountKey|--createaccountkey|-cak)
        _CMD="createAccountKey"
        ;;
    --createDomainKey|--createdomainkey|-cdk)
        _CMD="createDomainKey"
        ;;
    --createCSR|--createcsr|-ccr)
        _CMD="createCSR"
        ;;
    --deactivate)
        _CMD="deactivate"
        ;;
    --updateaccount)
        _CMD="updateaccount"
        ;;
    --registeraccount)
        _CMD="registeraccount"
        ;;
    --domain|-d)
        _dvalue="$2"
        
        if [ "$_dvalue" ] ; then
          if _startswith "$_dvalue" "-" ; then
            _err "'$_dvalue' is not a valid domain for parameter '$1'"
            return 1
          fi
          if _is_idn "$_dvalue" && ! _exists idn ; then
            _err "It seems that $_dvalue is an IDN( Internationalized Domain Names), please install 'idn' command first."
            return 1
          fi
          
          if [ -z "$_domain" ] ; then
            _domain="$_dvalue"
          else
            if [ "$_altdomains" = "$NO_VALUE" ] ; then
              _altdomains="$_dvalue"
            else
              _altdomains="$_altdomains,$_dvalue"
            fi
          fi
        fi
        
        shift
        ;;

    --force|-f)
        FORCE="1"
        ;;
    --staging|--test)
        STAGE="1"
        ;;
    --debug)
        if [ -z "$2" ] || _startswith "$2" "-" ; then
          DEBUG="1"
        else
          DEBUG="$2"
          shift
        fi 
        ;;
    --webroot|-w)
        wvalue="$2"
        if [ -z "$_webroot" ] ; then
          _webroot="$wvalue"
        else
          _webroot="$_webroot,$wvalue"
        fi
        shift
        ;;        
    --standalone)
        wvalue="$NO_VALUE"
        if [ -z "$_webroot" ] ; then
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
        if [ -z "$_webroot" ] ; then
          _webroot="$wvalue"
        else
          _webroot="$_webroot,$wvalue"
        fi
        ;;
    --tls)
        wvalue="$W_TLS"
        if [ -z "$_webroot" ] ; then
          _webroot="$wvalue"
        else
          _webroot="$_webroot,$wvalue"
        fi
        ;;
    --dns)
        wvalue="dns"
        if ! _startswith "$2" "-" ; then
          wvalue="$2"
          shift
        fi
        if [ -z "$_webroot" ] ; then
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
        
    --keylength|-k)
        _keylength="$2"
        if [ "$_accountkeylength" = "$NO_VALUE" ] ; then
          _accountkeylength="$2"
        fi
        shift
        ;;
    --accountkeylength|-ak)
        _accountkeylength="$2"
        shift
        ;;

    --certpath)
        _certpath="$2"
        shift
        ;;
    --keypath)
        _keypath="$2"
        shift
        ;;
    --capath)
        _capath="$2"
        shift
        ;;
    --fullchainpath)
        _fullchainpath="$2"
        shift
        ;;
    --reloadcmd|--reloadCmd)
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
    --certhome)
        _certhome="$2"
        CERT_HOME="$_certhome"
        shift
        ;;        
    --useragent)
        _useragent="$2"
        USER_AGENT="$_useragent"
        shift
        ;;
    --accountemail )
        _accountemail="$2"
        ACCOUNT_EMAIL="$_accountemail"
        shift
        ;;
    --accountkey )
        _accountkey="$2"
        ACCOUNT_KEY_PATH="$_accountkey"
        shift
        ;;
    --days )
        _days="$2"
        Le_RenewalDays="$_days"
        shift
        ;;
    --httpport )
        _httpport="$2"
        Le_HTTPPort="$_httpport"
        shift
        ;;
    --tlsport )
        _tlsport="$2"
        Le_TLSPort="$_tlsport"
        shift
        ;;
        
    --listraw )
        _listraw="raw"
        ;;        
    --stopRenewOnError|--stoprenewonerror|-se )
        _stopRenewOnError="1"
        ;;
    --insecure)
        _insecure="1"
        HTTPS_INSECURE="1"
        ;;
    --ca-bundle)
        _ca_bundle="$(readlink -f $2)"
        CA_BUNDLE="$_ca_bundle"
        shift
        ;;
    --nocron)
        _nocron="1"
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
        _deploy_hook="$2"
        shift
        ;;
    --ocsp-must-staple|--ocsp)
        Le_OCSP_Stable="1"
        ;;
    --log|--logfile)
        _log="1"
        _logfile="$2"
        if _startswith "$_logfile" '-' ; then
          _logfile=""
        else
          shift
        fi
        LOG_FILE="$_logfile"
        if [ -z "$LOG_LEVEL" ] ; then
          LOG_LEVEL="$DEFAULT_LOG_LEVEL"
        fi
        ;;
    --log-level)
        _log_level="$2"
        LOG_LEVEL="$_log_level"
        shift
        ;;
    --auto-upgrade)
        _auto_upgrade="$2"
        if [ -z "$_auto_upgrade" ] || _startswith "$_auto_upgrade" '-' ;  then
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
        
    *)
        _err "Unknown parameter : $1"
        return 1
        ;;
    esac

    shift 1
  done

  if [ "${_CMD}" != "install" ] ; then
    __initHome
    if [ "$_log" ]; then
      if [ -z "$_logfile" ] ; then
        _logfile="$DEFAULT_LOG_FILE"
      fi
    fi
    if [ "$_logfile" ] ; then
      _saveaccountconf "LOG_FILE" "$_logfile"
      LOG_FILE="$_logfile"
    fi

    if [ "$_log_level" ] ; then
      _saveaccountconf "LOG_LEVEL" "$_log_level"
      LOG_LEVEL="$_log_level"
    fi
    
    _processAccountConf
  fi
 
  if [ "$DEBUG" ] ; then
    version
  fi

  case "${_CMD}" in
    install) install "$_nocron" ;;
    uninstall) uninstall "$_nocron" ;;
    upgrade) upgrade ;;
    issue)
      issue  "$_webroot"  "$_domain" "$_altdomains" "$_keylength" "$_certpath" "$_keypath" "$_capath" "$_reloadcmd" "$_fullchainpath" "$_pre_hook" "$_post_hook" "$_renew_hook" "$_local_address"
      ;;
    deploy)
      deploy "$_domain" "$_deploy_hook" "$_ecc"
      ;;
    signcsr)
      signcsr "$_csr" "$_webroot"
      ;;
    showcsr)
      showcsr "$_csr" "$_domain"
      ;;
    installcert)
      installcert "$_domain" "$_certpath" "$_keypath" "$_capath" "$_reloadcmd" "$_fullchainpath" "$_ecc"
      ;;
    renew) 
      renew "$_domain" "$_ecc"
      ;;
    renewAll) 
      renewAll "$_stopRenewOnError"
      ;;
    revoke) 
      revoke "$_domain" "$_ecc"
      ;;
    deactivate) 
      deactivate "$_domain,$_altdomains"
      ;;
    registeraccount) 
      registeraccount
      ;;
    updateaccount) 
      updateaccount
      ;;
    list) 
      list "$_listraw"
      ;;
    installcronjob) installcronjob ;;
    uninstallcronjob) uninstallcronjob ;;
    cron) cron ;;
    toPkcs) 
      toPkcs "$_domain" "$_password" "$_ecc"
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

    *)
      _err "Invalid command: $_CMD"
      showhelp;
      return 1
    ;;
  esac
  _ret="$?"
  if [ "$_ret" != "0" ] ; then
    return $_ret
  fi
  
  if [ "${_CMD}" = "install" ] ; then
    if [ "$_log" ] ; then
      if [ -z "$LOG_FILE" ] ; then
        LOG_FILE="$DEFAULT_LOG_FILE"
      fi
      _saveaccountconf "LOG_FILE" "$LOG_FILE"
    fi
    
    if [ "$_log_level" ] ; then
      _saveaccountconf "LOG_LEVEL" "$_log_level"
    fi
    _processAccountConf
  fi

}


if [ "$INSTALLONLINE" ] ; then
  INSTALLONLINE=""
  _installOnline $BRANCH
  exit
fi





main() {
  [ -z "$1" ] && showhelp && return
  if _startswith "$1" '-' ; then _process "$@"; else "$@";fi
}


main "$@"



