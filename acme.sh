#!/usr/bin/env bash
VER=2.1.1

PROJECT_NAME="acme.sh"

PROJECT_ENTRY="acme.sh"

PROJECT="https://github.com/Neilpang/$PROJECT_NAME"

DEFAULT_CA="https://acme-v01.api.letsencrypt.org"
DEFAULT_AGREEMENT="https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf"

DEFAULT_USER_AGENT="$PROJECT_ENTRY client: $PROJECT"

STAGE_CA="https://acme-staging.api.letsencrypt.org"

VTYPE_HTTP="http-01"
VTYPE_DNS="dns-01"

BEGIN_CSR="-----BEGIN CERTIFICATE REQUEST-----"
END_CSR="-----END CERTIFICATE REQUEST-----"

BEGIN_CERT="-----BEGIN CERTIFICATE-----"
END_CERT="-----END CERTIFICATE-----"

if [[ -z "$AGREEMENT" ]] ; then
  AGREEMENT="$DEFAULT_AGREEMENT"
fi


_info() {
  if [[ -z "$2" ]] ; then
    echo "[$(date)] $1"
  else
    echo "[$(date)] $1"="'$2'"
  fi
}

_err() {
  _info "$@" >&2
  return 1
}

_debug() {
  if [[ -z "$DEBUG" ]] ; then
    return
  fi
  _err "$@"
  return 0
}

_debug2() {
  if [[ "$DEBUG" -ge "2" ]] ; then
    _debug "$@"
  fi
  return
}

_exists() {
  cmd="$1"
  if [[ -z "$cmd" ]] ; then
    _err "Usage: _exists cmd"
    return 1
  fi
  command -v $cmd >/dev/null 2>&1
  ret="$?"
  _debug2 "$cmd exists=$ret"
  return $ret
}

_h2b() {
  hex=$(cat)
  i=1
  j=2
  while [ '1' ] ; do
    h=$(printf $hex | cut -c $i-$j)
    if [[ -z "$h" ]] ; then
      break;
    fi
    printf "\x$h"
    let "i+=2"
    let "j+=2"
  done
}

#options file
_sed_i() {
  options="$1"
  filename="$2"
  if [[ -z "$filename" ]] ; then
    _err "Usage:_sed_i options filename"
    return 1
  fi
  
  if sed -h 2>&1 | grep "\-i[SUFFIX]" ; then
    _debug "Using sed  -i"
    sed -i ""
  else
    _debug "No -i support in sed"
    text="$(cat $filename)"
    echo "$text" | sed "$options" > "$filename"
  fi
}

#Usage: file startline endline
_getfile() {
  filename="$1"
  startline="$2"
  endline="$3"
  if [[ -z "$endline" ]] ; then
    _err "Usage: file startline endline"
    return 1
  fi
  
  i="$(grep -n --  "$startline"  $filename | cut -d : -f 1)"
  if [[ -z "$i" ]] ; then
    _err "Can not find start line: $startline"
    return 1
  fi
  let "i+=1"
  _debug i $i
  
  j="$(grep -n --  "$endline"  $filename | cut -d : -f 1)"
  if [[ -z "$j" ]] ; then
    _err "Can not find end line: $endline"
    return 1
  fi
  let "j-=1"
  _debug j $j
  
  sed -n $i,${j}p  "$filename"

}

#Usage: multiline
_base64() {
  if [[ "$1" ]] ; then
    openssl base64 -e
  else
    openssl base64 -e | tr -d '\r\n'
  fi
}

#Usage: multiline
_dbase64() {
  if [[ "$1" ]] ; then
    openssl base64 -d -A
  else
    openssl base64 -d
  fi
}

#Usage: hashalg
#Output Base64-encoded digest
_digest() {
  alg="$1"
  if [[ -z "$alg" ]] ; then
    _err "Usage: _digest hashalg"
    return 1
  fi
  
  if [[ "$alg" == "sha256" ]] ; then
    openssl dgst -sha256 -binary | _base64
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
  if [[ -z "$alg" ]] ; then
    _err "Usage: _sign keyfile hashalg"
    return 1
  fi
  
  if [[ "$alg" == "sha256" ]] ; then
    openssl   dgst   -sha256  -sign  "$keyfile" | _base64
  else
    _err "$alg is not supported yet"
    return 1
  fi  
  
}

_ss() {
  _port="$1"
  
  if _exists "ss" ; then
    _debug "Using: ss"
    ss -ntpl | grep :$_port" "
    return 0
  fi

  if _exists "netstat" ; then
    _debug "Using: netstat"
    if netstat -h 2>&1 | grep "\-p proto" >/dev/null ; then
      #for windows version netstat tool
      netstat -anb -p tcp | grep "LISTENING" | grep :$_port" "
    else
      if netstat -help 2>&1 | grep "\-p protocol" >/dev/null ; then
        netstat -an -p tcp | grep LISTEN | grep :$_port" "
      else
        netstat -ntpl | grep :$_port" "
      fi
    fi
    return 0
  fi

  return 1
}

toPkcs() {
  domain="$1"
  pfxPassword="$2"
  if [[ -z "$domain" ]] ; then
    echo "Usage: $PROJECT_ENTRY --toPkcs -d domain [--password pfx-password]"
    return 1
  fi

  _initpath "$domain"
  
  if [[ "$pfxPassword" ]] ; then
    openssl pkcs12 -export -out "$CERT_PFX_PATH" -inkey "$CERT_KEY_PATH" -in "$CERT_PATH" -certfile "$CA_CERT_PATH" -password "pass:$pfxPassword"
  else
    openssl pkcs12 -export -out "$CERT_PFX_PATH" -inkey "$CERT_KEY_PATH" -in "$CERT_PATH" -certfile "$CA_CERT_PATH"
  fi
  
  if [[ "$?" == "0" ]] ; then
    _info "Success, Pfx is exported to: $CERT_PFX_PATH"
  fi

}

#domain [2048]  
createAccountKey() {
  _info "Creating account key"
  if [[ -z "$1" ]] ; then
    echo Usage: $PROJECT_ENTRY --createAccountKey -d domain.com  [--accountkeylength 2048]
    return
  fi
  
  account=$1
  length=$2
  _debug account "$account"
  _debug length "$length"
  if [[ "$length" == "ec-"* ]] ; then
    length=2048
  fi
  
  if [[ -z "$2" ]] || [[ "$2" == "no" ]] ; then
    _info "Use default length 2048"
    length=2048
  fi
  _initpath
  
  if [[ -f "$ACCOUNT_KEY_PATH" ]] ; then
    _info "Account key exists, skip"
    return
  else
    #generate account key
    openssl genrsa $length 2>/dev/null > "$ACCOUNT_KEY_PATH"
  fi

}

#domain length
createDomainKey() {
  _info "Creating domain key"
  if [[ -z "$1" ]] ; then
    echo Usage: $PROJECT_ENTRY --createDomainKey -d domain.com  [ --keylength 2048 ]
    return
  fi
  
  domain=$1
  length=$2
  isec=""
  if [[ "$length" == "ec-"* ]] ; then
    isec="1"
    length=$(printf $length | cut -d '-' -f 2-100)
    eccname="$length"
  fi

  if [[ -z "$length" ]] ; then
    if [[ "$isec" ]] ; then
      length=256
    else
      length=2048
    fi
  fi
  _info "Use length $length"

  if [[ "$isec" ]] ; then
    if [[ "$length" == "256" ]] ; then
      eccname="prime256v1"
    fi
    if [[ "$length" == "384" ]] ; then
      eccname="secp384r1"
    fi
    if [[ "$length" == "521" ]] ; then
      eccname="secp521r1"
    fi
    _info "Using ec name: $eccname"
  fi
  
  _initpath $domain
  
  if [[ ! -f "$CERT_KEY_PATH" ]] || ( [[ "$FORCE" ]] && ! [[ "$IS_RENEW" ]] ); then 
    #generate account key
    if [[ "$isec" ]] ; then
      openssl ecparam  -name $eccname -genkey 2>/dev/null > "$CERT_KEY_PATH"
    else
      openssl genrsa $length 2>/dev/null > "$CERT_KEY_PATH"
    fi
  else
    if [[ "$IS_RENEW" ]] ; then
      _info "Domain key exists, skip"
      return 0
    else
      _err "Domain key exists, do you want to overwrite the key?"
      _err "Add '--force', and try again."
      return 1
    fi
  fi

}

# domain  domainlist
createCSR() {
  _info "Creating csr"
  if [[ -z "$1" ]] ; then
    echo Usage: $PROJECT_ENTRY --createCSR -d domain1.com [-d domain2.com  -d domain3.com ... ]
    return
  fi
  domain=$1
  _initpath $domain
  
  domainlist=$2
  
  if [[ -f "$CSR_PATH" ]]  && [[ "$IS_RENEW" ]] && [[ -z "$FORCE" ]]; then
    _info "CSR exists, skip"
    return
  fi
  
  if [[ -z "$domainlist" ]] || [[ "$domainlist" == "no" ]]; then
    #single domain
    _info "Single domain" $domain
    printf "[ req_distinguished_name ]\n[ req ]\ndistinguished_name = req_distinguished_name\n" > "$DOMAIN_SSL_CONF"
    openssl req -new -sha256 -key "$CERT_KEY_PATH" -subj "/CN=$domain" -config "$DOMAIN_SSL_CONF" -out "$CSR_PATH"
  else
    alt="DNS:$(echo $domainlist | sed "s/,/,DNS:/g")"
    #multi 
    _info "Multi domain" "$alt"
    printf "[ req_distinguished_name ]\n[ req ]\ndistinguished_name = req_distinguished_name\n[SAN]\nsubjectAltName=$alt" > "$DOMAIN_SSL_CONF"
    openssl req -new -sha256 -key "$CERT_KEY_PATH" -subj "/CN=$domain" -reqexts SAN -config "$DOMAIN_SSL_CONF" -out "$CSR_PATH"
  fi

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
}

#keyfile
_calcjwk() {
  keyfile="$1"
  if [[ -z "$keyfile" ]] ; then
    _err "Usage: _calcjwk keyfile"
    return 1
  fi
  EC_SIGN=""
  if grep "BEGIN RSA PRIVATE KEY" "$keyfile" > /dev/null 2>&1 ; then
    _debug "RSA key"
    pub_exp=$(openssl rsa -in $keyfile  -noout -text | grep "^publicExponent:"| cut -d '(' -f 2 | cut -d 'x' -f 2 | cut -d ')' -f 1)
    if [[ "${#pub_exp}" == "5" ]] ; then
      pub_exp=0$pub_exp
    fi
    _debug2 pub_exp "$pub_exp"
    
    e=$(echo $pub_exp | _h2b | _base64)
    _debug2 e "$e"
    
    modulus=$(openssl rsa -in $keyfile -modulus -noout | cut -d '=' -f 2 )
    n=$(echo $modulus| _h2b | _base64 | _urlencode )
    jwk='{"e": "'$e'", "kty": "RSA", "n": "'$n'"}'
    _debug2 jwk "$jwk"
    
    HEADER='{"alg": "RS256", "jwk": '$jwk'}'
    HEADERPLACE='{"nonce": "NONCE", "alg": "RS256", "jwk": '$jwk'}'
  elif grep "BEGIN EC PRIVATE KEY" "$keyfile" > /dev/null 2>&1 ; then
    _debug "EC key"
    EC_SIGN="1"
    crv="$(openssl ec  -in $keyfile  -noout -text 2>/dev/null | grep "^NIST CURVE:" | cut -d ":" -f 2 | tr -d " \r\n")"
    _debug2 crv $crv
    
    pubi="$(openssl ec  -in $keyfile  -noout -text 2>/dev/null | grep -n pub: | cut -d : -f 1)"
    _debug2 pubi $pubi
    let "pubi=pubi+1"
    
    pubj="$(openssl ec  -in $keyfile  -noout -text 2>/dev/null | grep -n "ASN1 OID:"  | cut -d : -f 1)"
    _debug2 pubj $pubj
    let "pubj=pubj-1"
    
    pubtext="$(openssl ec  -in $keyfile  -noout -text 2>/dev/null | sed  -n "$pubi,${pubj}p" | tr -d " \n\r")"
    _debug2 pubtext "$pubtext"
    
    xlen="$(printf "$pubtext" | tr -d ':' | wc -c)"
    let "xlen=xlen/4"
    _debug2 xlen $xlen
    
    let "xend=xlen+1"
    x="$(printf $pubtext | cut -d : -f 2-$xend)"
    _debug2 x $x
    
    x64="$(printf $x | tr -d : | _h2b | _base64 | _urlencode)"
    _debug2 x64 $x64
    
    let "xend+=1"
    y="$(printf $pubtext | cut -d : -f $xend-10000)"
    _debug2 y $y
    
    y64="$(printf $y | tr -d : | _h2b | _base64 | _urlencode)"
    _debug2 y64 $y64
   
    jwk='{"kty": "EC", "crv": "'$crv'", "x": "'$x64'", "y": "'$y64'"}'
    _debug2 jwk "$jwk"
    
    HEADER='{"alg": "ES256", "jwk": '$jwk'}'
    HEADERPLACE='{"nonce": "NONCE", "alg": "ES256", "jwk": '$jwk'}'

  else
    _err "Only RSA or EC key is supported."
    return 1
  fi

  _debug2 HEADER "$HEADER"
}
# body  url [needbase64]
_post() {
  body="$1"
  url="$2"
  needbase64="$3"

  if _exists "curl" ; then
    CURL="$CURL --dump-header $HTTP_HEADER "
    if [[ "$needbase64" ]] ; then
      response="$($CURL -A "User-Agent: $USER_AGENT" -X POST --data "$body" $url | _base64)"
    else
      response="$($CURL -A "User-Agent: $USER_AGENT" -X POST --data "$body" $url)"
    fi
  else
    if [[ "$needbase64" ]] ; then
      response="$($WGET -S -O - --user-agent="$USER_AGENT" --post-data="$body" $url 2>"$HTTP_HEADER" | _base64)"
    else
      response="$($WGET -S -O - --user-agent="$USER_AGENT" --post-data="$body" $url 2>"$HTTP_HEADER")"
    fi
    _sed_i "s/^ *//g" "$HTTP_HEADER"
  fi
  echo -n "$response"
  
}

# url getheader
_get() {
  url="$1"
  onlyheader="$2"
  _debug url $url
  if _exists "curl" ; then
    if [[ "$onlyheader" ]] ; then
      $CURL -I -A "User-Agent: $USER_AGENT" $url
    else
      $CURL -A "User-Agent: $USER_AGENT" $url
    fi
  else
    _debug "WGET" "$WGET"
    if [[ "$onlyheader" ]] ; then
      eval $WGET --user-agent=\"$USER_AGENT\" -S -O /dev/null $url 2>&1 | sed 's/^[ ]*//g'
    else
      eval $WGET --user-agent=\"$USER_AGENT\" -O - $url
    fi
  fi
  ret=$?
  return $ret
}

# url  payload needbase64  keyfile
_send_signed_request() {
  url=$1
  payload=$2
  needbase64=$3
  keyfile=$4
  if [[ -z "$keyfile" ]] ; then
    keyfile="$ACCOUNT_KEY_PATH"
  fi
  _debug url $url
  _debug payload "$payload"
  
  if ! _calcjwk "$keyfile" ; then
    return 1
  fi

  payload64=$(echo -n $payload | _base64 | _urlencode)
  _debug2 payload64 $payload64
  
  nonceurl="$API/directory"
  nonce="$(_get $nonceurl "onlyheader" | grep -o "Replay-Nonce:.*$" | head -1 | tr -d "\r\n" | cut -d ' ' -f 2)"

  _debug nonce "$nonce"
  
  protected="$(printf "$HEADERPLACE" | sed "s/NONCE/$nonce/" )"
  _debug2 protected "$protected"
  
  protected64="$(printf "$protected" | _base64 | _urlencode)"
  _debug2 protected64 "$protected64"

  sig=$(echo -n "$protected64.$payload64" |  _sign  "$keyfile" "sha256" | _urlencode)
  _debug2 sig "$sig"
  
  body="{\"header\": $HEADER, \"protected\": \"$protected64\", \"payload\": \"$payload64\", \"signature\": \"$sig\"}"
  _debug2 body "$body"
  

  response="$(_post "$body" $url "$needbase64" )"

  responseHeaders="$(cat $HTTP_HEADER)"
  
  _debug2 responseHeaders "$responseHeaders"
  _debug2 response  "$response"
  code="$(grep "^HTTP" $HTTP_HEADER | tail -1 | cut -d " " -f 2 | tr -d "\r\n" )"
  _debug code $code

}


#setopt "file"  "opt"  "="  "value" [";"]
_setopt() {
  __conf="$1"
  __opt="$2"
  __sep="$3"
  __val="$4"
  __end="$5"
  if [[ -z "$__opt" ]] ; then 
    echo usage: _setopt  '"file"  "opt"  "="  "value" [";"]'
    return
  fi
  if [[ ! -f "$__conf" ]] ; then
    touch "$__conf"
  fi

  if grep -H -n "^$__opt$__sep" "$__conf" > /dev/null ; then
    _debug2 OK
    if [[ "$__val" == *"&"* ]] ; then
      __val="$(echo $__val | sed 's/&/\\&/g')"
    fi
    text="$(cat $__conf)"
    echo "$text" | sed "s|^$__opt$__sep.*$|$__opt$__sep$__val$__end|" > "$__conf"

  elif grep -H -n "^#$__opt$__sep" "$__conf" > /dev/null ; then
    if [[ "$__val" == *"&"* ]] ; then
      __val="$(echo $__val | sed 's/&/\\&/g')"
    fi
    text="$(cat $__conf)"
    echo "$text" | sed "s|^#$__opt$__sep.*$|$__opt$__sep$__val$__end|" > "$__conf"

  else
    _debug2 APP
    echo "$__opt$__sep$__val$__end" >> "$__conf"
  fi
  _debug "$(grep -H -n "^$__opt$__sep" $__conf)"
}

#_savedomainconf   key  value
#save to domain.conf
_savedomainconf() {
  key="$1"
  value="$2"
  if [[ "$DOMAIN_CONF" ]] ; then
    _setopt $DOMAIN_CONF "$key" "=" "$value"
  else
    _err "DOMAIN_CONF is empty, can not save $key=$value"
  fi
}

#_saveaccountconf  key  value
_saveaccountconf() {
  key="$1"
  value="$2"
  if [[ "$ACCOUNT_CONF_PATH" ]] ; then
    _setopt $ACCOUNT_CONF_PATH "$key" "=" "\"$value\""
  else
    _err "ACCOUNT_CONF_PATH is empty, can not save $key=$value"
  fi
}

_startserver() {
  content="$1"
  _debug "startserver: $$"
  nchelp="$(nc -h 2>&1)"
  
  if echo "$nchelp" | grep "\-q[ ,]" >/dev/null ; then
    _NC="nc -q 1 -l"
  else
    if echo "$nchelp" | grep "GNU netcat" >/dev/null && echo "$nchelp" | grep "\-c, \-\-close" >/dev/null ; then
      _NC="nc -c -l"
    elif echo "$nchelp" | grep "\-N" |grep "Shutdown the network socket after EOF on stdin"  >/dev/null ; then
      _NC="nc -N -l"
    else
      _NC="nc -l"
    fi
  fi

  _debug "_NC" "$_NC"
#  while true ; do
    if [[ "$DEBUG" ]] ; then
      if ! echo -e -n "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC -p $Le_HTTPPort -vv ; then
        echo -e -n "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC $Le_HTTPPort -vv ;
      fi
    else
      if ! echo -e -n "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC -p $Le_HTTPPort > /dev/null 2>&1; then
        echo -e -n "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC $Le_HTTPPort > /dev/null 2>&1
      fi      
    fi
    if [[ "$?" != "0" ]] ; then
      _err "nc listen error."
      exit 1
    fi
#  done
}

_stopserver(){
  pid="$1"
  _debug "pid" "$pid"
  if [[ -z "$pid" ]] ; then
    return
  fi
  
  if [[ "$(ps | grep "$pid")" ]] ; then
    _debug "Found proc process, kill it."
    kill -s 9 $pid > /dev/null
  fi
  
  for ncid in $(echo $(ps | grep nc) | cut -d " " -f 1) ; do
    _debug "kill $ncid"
    kill -s 9 $ncid > /dev/null
  done
  
  _get "http://localhost:$Le_HTTPPort" >/dev/null 2>&1

}

_initpath() {

  if [[ -z "$LE_WORKING_DIR" ]] ; then
    LE_WORKING_DIR=$HOME/.$PROJECT_NAME
  fi
  
  _DEFAULT_ACCOUNT_CONF_PATH="$LE_WORKING_DIR/account.conf"

  if [[ -z "$ACCOUNT_CONF_PATH" ]] ; then
    if [[ -f "$_DEFAULT_ACCOUNT_CONF_PATH" ]] ; then
      source "$_DEFAULT_ACCOUNT_CONF_PATH"
    fi
  fi
  
  if [[ -z "$ACCOUNT_CONF_PATH" ]] ; then
    ACCOUNT_CONF_PATH="$_DEFAULT_ACCOUNT_CONF_PATH"
  fi
  
  if [[ -f "$ACCOUNT_CONF_PATH" ]] ; then
    source "$ACCOUNT_CONF_PATH"
  fi

  if [[ "$IN_CRON" ]] ; then
    if [[ ! "$_USER_PATH_EXPORTED" ]] ; then
      _USER_PATH_EXPORTED=1
      export PATH="$USER_PATH:$PATH"
    fi
  fi

  if [[ -z "$API" ]] ; then
    if [[ -z "$STAGE" ]] ; then
      API="$DEFAULT_CA"
    else
      API="$STAGE_CA"
      _info "Using stage api:$API"
    fi  
  fi
  
  if [[ -z "$ACME_DIR" ]] ; then
    ACME_DIR="/home/.acme"
  fi
  
  if [[ -z "$APACHE_CONF_BACKUP_DIR" ]] ; then
    APACHE_CONF_BACKUP_DIR="$LE_WORKING_DIR"
  fi
  
  if [[ -z "$USER_AGENT" ]] ; then
    USER_AGENT="$DEFAULT_USER_AGENT"
  fi
  
  HTTP_HEADER="$LE_WORKING_DIR/http.header"
  
  WGET="wget -q"
  if [[ "$DEBUG" -ge "2" ]] ; then
    WGET="$WGET -d "
  fi

  dp="$LE_WORKING_DIR/curl.dump"
  CURL="curl -L --silent"
  if [[ "$DEBUG" -ge "2" ]] ; then
    CURL="$CURL -L --trace-ascii $dp "
  fi
  
  domain="$1"
  
  if [[ -z "$ACCOUNT_KEY_PATH" ]] ; then
    ACCOUNT_KEY_PATH="$LE_WORKING_DIR/account.key"
  fi

  if [[ -z "$domain" ]] ; then
    return 0
  fi
  
  domainhome="$LE_WORKING_DIR/$domain"
  mkdir -p "$domainhome"

  if [[ -z "$DOMAIN_PATH" ]] ; then
    DOMAIN_PATH="$domainhome"
  fi
  if [[ -z "$DOMAIN_CONF" ]] ; then
    DOMAIN_CONF="$domainhome/$domain.conf"
  fi
  
  if [[ -z "$DOMAIN_SSL_CONF" ]] ; then
    DOMAIN_SSL_CONF="$domainhome/$domain.ssl.conf"
  fi
  
  if [[ -z "$CSR_PATH" ]] ; then
    CSR_PATH="$domainhome/$domain.csr"
  fi
  if [[ -z "$CERT_KEY_PATH" ]] ; then 
    CERT_KEY_PATH="$domainhome/$domain.key"
  fi
  if [[ -z "$CERT_PATH" ]] ; then
    CERT_PATH="$domainhome/$domain.cer"
  fi
  if [[ -z "$CA_CERT_PATH" ]] ; then
    CA_CERT_PATH="$domainhome/ca.cer"
  fi
  if [[ -z "$CERT_FULLCHAIN_PATH" ]] ; then
    CERT_FULLCHAIN_PATH="$domainhome/fullchain.cer"
  fi
  if [[ -z "$CERT_PFX_PATH" ]] ; then
    CERT_PFX_PATH="$domainhome/$domain.pfx"
  fi
}


_apachePath() {
  httpdconfname="$(apachectl -V | grep SERVER_CONFIG_FILE= | cut -d = -f 2 | tr -d '"' )"
  if [[ "$httpdconfname" == '/'* ]] ; then
    httpdconf="$httpdconfname"
    httpdconfname="$(basename $httpdconfname)"
  else
    httpdroot="$(apachectl -V | grep HTTPD_ROOT= | cut -d = -f 2 | tr -d '"' )"
    httpdconf="$httpdroot/$httpdconfname"
  fi

  if [[ ! -f $httpdconf ]] ; then
    _err "Apache Config file not found" $httpdconf
    return 1
  fi
  return 0
}

_restoreApache() {
  if [[ -z "$usingApache" ]] ; then
    return 0
  fi
  _initpath
  if ! _apachePath ; then
    return 1
  fi
  
  if [[ ! -f "$APACHE_CONF_BACKUP_DIR/$httpdconfname" ]] ; then
    _debug "No config file to restore."
    return 0
  fi
  
  cp -p "$APACHE_CONF_BACKUP_DIR/$httpdconfname" "$httpdconf"
  if ! apachectl  -t ; then
    _err "Sorry, restore apache config error, please contact me."
    return 1;
  fi
  rm -f "$APACHE_CONF_BACKUP_DIR/$httpdconfname"
  return 0  
}

_setApache() {
  _initpath
  if ! _apachePath ; then
    return 1
  fi

  #backup the conf
  _debug "Backup apache config file" $httpdconf
  cp -p $httpdconf $APACHE_CONF_BACKUP_DIR/
  _info "JFYI, Config file $httpdconf is backuped to $APACHE_CONF_BACKUP_DIR/$httpdconfname"
  _info "In case there is an error that can not be restored automatically, you may try restore it yourself."
  _info "The backup file will be deleted on sucess, just forget it."
  
  #add alias
  
  apacheVer="$(apachectl -V | grep "Server version:" | cut -d : -f 2 | cut -d " " -f 2 | cut -d '/' -f 2 )"
  _debug "apacheVer" "$apacheVer"
  apacheMajer="$(echo "$apacheVer" | cut -d . -f 1)"
  apacheMinor="$(echo "$apacheVer" | cut -d . -f 2)"

  if [[ "$apacheVer" ]] && [[ "$apacheMajer" -ge "2" ]] && [[ "$apacheMinor" -ge "4" ]] ; then
    echo "
Alias /.well-known/acme-challenge  $ACME_DIR

<Directory $ACME_DIR >
Require all granted
</Directory>
  " >> $httpdconf  
  else
    echo "
Alias /.well-known/acme-challenge  $ACME_DIR

<Directory $ACME_DIR >
Order allow,deny
Allow from all
</Directory>
  " >> $httpdconf
  fi

  
  if ! apachectl  -t ; then
    _err "Sorry, apache config error, please contact me."
    _restoreApache
    return 1;
  fi
  
  if [[ ! -d "$ACME_DIR" ]] ; then
    mkdir -p "$ACME_DIR"
    chmod 755 "$ACME_DIR"
  fi
  
  if ! apachectl  graceful ; then
    _err "Sorry, apachectl  graceful error, please contact me."
    _restoreApache
    return 1;
  fi
  usingApache="1"
  return 0
}

_clearup () {
  _stopserver $serverproc
  serverproc=""
  _restoreApache
}

# webroot  removelevel tokenfile
_clearupwebbroot() {
  __webroot="$1"
  if [[ -z "$__webroot" ]] ; then
    _debug "no webroot specified, skip"
    return 0
  fi
  
  if [[ "$2" == '1' ]] ; then
    _debug "remove $__webroot/.well-known"
    rm -rf "$__webroot/.well-known"
  elif [[ "$2" == '2' ]] ; then
    _debug "remove $__webroot/.well-known/acme-challenge"
    rm -rf "$__webroot/.well-known/acme-challenge"
  elif [[ "$2" == '3' ]] ; then
    _debug "remove $__webroot/.well-known/acme-challenge/$3"
    rm -rf "$__webroot/.well-known/acme-challenge/$3"
  else
    _info "Skip for removelevel:$2"
  fi
  
  return 0

}

issue() {
  if [[ -z "$2" ]] ; then
    echo "Usage: $PROJECT_ENTRY --issue  -d  a.com  -w /path/to/webroot/a.com/ "
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
  
  _initpath $Le_Domain
  
  if [[ -f "$DOMAIN_CONF" ]] ; then
    Le_NextRenewTime=$(grep "^Le_NextRenewTime=" "$DOMAIN_CONF" | cut -d '=' -f 2)
    if [[ -z "$FORCE" ]] && [[ "$Le_NextRenewTime" ]] && [[ "$(date -u "+%s" )" -lt "$Le_NextRenewTime" ]] ; then 
      _info "Skip, Next renewal time is: $(grep "^Le_NextRenewTimeStr" "$DOMAIN_CONF" | cut -d '=' -f 2)"
      return 2
    fi
  fi

  _setopt "$DOMAIN_CONF"  "Le_Domain"             "="  "$Le_Domain"
  _setopt "$DOMAIN_CONF"  "Le_Alt"                "="  "$Le_Alt"
  _setopt "$DOMAIN_CONF"  "Le_Webroot"            "="  "$Le_Webroot"
  _setopt "$DOMAIN_CONF"  "Le_Keylength"          "="  "$Le_Keylength"
  _setopt "$DOMAIN_CONF"  "Le_RealCertPath"       "="  "\"$Le_RealCertPath\""
  _setopt "$DOMAIN_CONF"  "Le_RealCACertPath"     "="  "\"$Le_RealCACertPath\""
  _setopt "$DOMAIN_CONF"  "Le_RealKeyPath"        "="  "\"$Le_RealKeyPath\""
  _setopt "$DOMAIN_CONF"  "Le_ReloadCmd"          "="  "\"$Le_ReloadCmd\""
  _setopt "$DOMAIN_CONF"  "Le_RealFullChainPath"  "="  "\"$Le_RealFullChainPath\""
  
  if [[ "$Le_Alt" == "no" ]] ; then
    Le_Alt=""
  fi
  if [[ "$Le_Keylength" == "no" ]] ; then
    Le_Keylength=""
  fi
  if [[ "$Le_RealCertPath" == "no" ]] ; then
    Le_RealCertPath=""
  fi
  if [[ "$Le_RealKeyPath" == "no" ]] ; then
    Le_RealKeyPath=""
  fi
  if [[ "$Le_RealCACertPath" == "no" ]] ; then
    Le_RealCACertPath=""
  fi
  if [[ "$Le_ReloadCmd" == "no" ]] ; then
    Le_ReloadCmd=""
  fi
  if [[ "$Le_RealFullChainPath" == "no" ]] ; then
    Le_RealFullChainPath=""
  fi

  
  if [[ "$Le_Webroot" == *"no"* ]] ; then
    _info "Standalone mode."
    if ! command -v "nc" > /dev/null ; then
      _err "Please install netcat(nc) tools first."
      return 1
    fi
    
    if [[ -z "$Le_HTTPPort" ]] ; then
      Le_HTTPPort=80
    fi
    _setopt "$DOMAIN_CONF"  "Le_HTTPPort"             "="  "$Le_HTTPPort"
    
    netprc="$(_ss "$Le_HTTPPort" | grep "$Le_HTTPPort")"
    if [[ "$netprc" ]] ; then
      _err "$netprc"
      _err "tcp port $Le_HTTPPort is already used by $(echo "$netprc" | cut -d :  -f 4)"
      _err "Please stop it first"
      return 1
    fi
  fi
  
  if [[ "$Le_Webroot" == *"apache"* ]] ; then
    if ! _setApache ; then
      _err "set up apache error. Report error to me."
      return 1
    fi
    wellknown_path="$ACME_DIR"
  else
    usingApache=""
  fi
  
  if [[ ! -f "$ACCOUNT_KEY_PATH" ]] ; then
    if ! createAccountKey $Le_Domain $Le_Keylength ; then
      _err "Create account key error."
      return 1
    fi
  fi
  
  if ! _calcjwk "$ACCOUNT_KEY_PATH" ; then
    return 1
  fi
  
  accountkey_json=$(echo -n "$jwk" |  tr -d ' ' )
  thumbprint=$(echo -n "$accountkey_json" | _digest "sha256" | _urlencode)
  
  accountkeyhash="$(cat "$ACCOUNT_KEY_PATH" | _digest "sha256" )"
  accountkeyhash="$(echo $accountkeyhash$API | _digest "sha256" )"
  if [[ "$accountkeyhash" != "$ACCOUNT_KEY_HASH" ]] ; then
    _info "Registering account"
    regjson='{"resource": "new-reg", "agreement": "'$AGREEMENT'"}'
    if [[ "$ACCOUNT_EMAIL" ]] ; then
      regjson='{"resource": "new-reg", "contact": ["mailto: '$ACCOUNT_EMAIL'"], "agreement": "'$AGREEMENT'"}'
    fi  
    _send_signed_request   "$API/acme/new-reg"  "$regjson"
    
    if [[ "$code" == "" ]] || [[ "$code" == '201' ]] ; then
      _info "Registered"
      echo $response > $LE_WORKING_DIR/account.json
    elif [[ "$code" == '409' ]] ; then
      _info "Already registered"
    else
      _err "Register account Error: $response"
      _clearup
      return 1
    fi
    ACCOUNT_KEY_HASH="$accountkeyhash"
    _saveaccountconf "ACCOUNT_KEY_HASH" "$ACCOUNT_KEY_HASH"
  else
    _info "Skip register account key"
  fi

  if [[ ! -f "$CERT_KEY_PATH" ]] ; then
    if ! createDomainKey $Le_Domain $Le_Keylength ; then 
      _err "Create domain key error."
      return 1
    fi
  fi
  
  if ! createCSR  $Le_Domain  $Le_Alt ; then
    _err "Create CSR error."
    return 1
  fi

  vlist="$Le_Vlist"
  # verify each domain
  _info "Verify each domain"
  sep='#'
  if [[ -z "$vlist" ]] ; then
    alldomains=$(echo "$Le_Domain,$Le_Alt" |  tr ',' ' ' )
    _index=1
    _currentRoot=""
    for d in $alldomains   
    do
      _info "Getting webroot for domain" $d
      _w="$(echo $Le_Webroot | cut -d , -f $_index)"
      _debug _w "$_w"
      if [[ "$_w" ]] ; then
        _currentRoot="$_w"
      fi
      _debug "_currentRoot" "$_currentRoot"
      let "_index+=1"
      
      vtype="$VTYPE_HTTP"
      if [[ "$_currentRoot" == "dns"* ]] ; then
        vtype="$VTYPE_DNS"
      fi
      _info "Getting token for domain" $d
      _send_signed_request "$API/acme/new-authz" "{\"resource\": \"new-authz\", \"identifier\": {\"type\": \"dns\", \"value\": \"$d\"}}"
      if [[ ! -z "$code" ]] && [[ ! "$code" == '201' ]] ; then
        _err "new-authz error: $response"
        _clearup
        return 1
      fi

      entry="$(printf $response | egrep -o  '\{[^{]*"type":"'$vtype'"[^}]*')"
      _debug entry "$entry"

      token="$(printf "$entry" | egrep -o '"token":"[^"]*' | cut -d : -f 2 | tr -d '"')"
      _debug token $token
      
      uri="$(printf "$entry" | egrep -o '"uri":"[^"]*'| cut -d : -f 2,3 | tr -d '"' )"
      _debug uri $uri
      
      keyauthorization="$token.$thumbprint"
      _debug keyauthorization "$keyauthorization"

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
      if [[ "$vtype" == "$VTYPE_DNS" ]] ; then
        dnsadded='0'
        txtdomain="_acme-challenge.$d"
        _debug txtdomain "$txtdomain"
        txt="$(echo -e -n $keyauthorization | _digest "sha256" | _urlencode)"
        _debug txt "$txt"
        #dns
        #1. check use api
        d_api=""
        if [[ -f "$LE_WORKING_DIR/$d/$_currentRoot" ]] ; then
          d_api="$LE_WORKING_DIR/$d/$_currentRoot"
        elif [[ -f "$LE_WORKING_DIR/$d/$_currentRoot.sh" ]] ; then
          d_api="$LE_WORKING_DIR/$d/$_currentRoot.sh"
        elif [[ -f "$LE_WORKING_DIR/$_currentRoot" ]] ; then
          d_api="$LE_WORKING_DIR/$_currentRoot"
        elif [[ -f "$LE_WORKING_DIR/$_currentRoot.sh" ]] ; then
          d_api="$LE_WORKING_DIR/$_currentRoot.sh"
        elif [[ -f "$LE_WORKING_DIR/dnsapi/$_currentRoot" ]] ; then
          d_api="$LE_WORKING_DIR/dnsapi/$_currentRoot"
        elif [[ -f "$LE_WORKING_DIR/dnsapi/$_currentRoot.sh" ]] ; then
          d_api="$LE_WORKING_DIR/dnsapi/$_currentRoot.sh"
        fi
        _debug d_api "$d_api"
        
        if [[ "$d_api" ]] ; then
          _info "Found domain api file: $d_api"
        else
          _err "Add the following TXT record:"
          _err "Domain: $txtdomain"
          _err "TXT value: $txt"
          _err "Please be aware that you prepend _acme-challenge. before your domain"
          _err "so the resulting subdomain will be: $txtdomain"
          continue
        fi
        
        (
          if ! source $d_api ; then
            _err "Load file $d_api error. Please check your api file and try again."
            return 1
          fi
          
          addcommand="$_currentRoot-add"
          if ! _exists $addcommand ; then 
            _err "It seems that your api file is not correct, it must have a function named: $addcommand"
            return 1
          fi
          
          if ! $addcommand $txtdomain $txt ; then
            _err "Error add txt for domain:$txtdomain"
            return 1
          fi
        )
        
        if [[ "$?" != "0" ]] ; then
          return 1
        fi
        dnsadded='1'
      fi
    done

    if [[ "$dnsadded" == '0' ]] ; then
      _setopt "$DOMAIN_CONF"  "Le_Vlist" "=" "\"$vlist\""
      _debug "Dns record not added yet, so, save to $DOMAIN_CONF and exit."
      _err "Please add the TXT records to the domains, and retry again."
      return 1
    fi
    
  fi
  
  if [[ "$dnsadded" == '1' ]] ; then
    _info "Sleep 60 seconds for the txt records to take effect"
    sleep 60
  fi
  
  _debug "ok, let's start to verify"

  ventries=$(echo "$vlist" |  tr ',' ' ' )
  for ventry in $ventries
  do
    d=$(echo $ventry | cut -d $sep -f 1)
    keyauthorization=$(echo $ventry | cut -d $sep -f 2)
    uri=$(echo $ventry | cut -d $sep -f 3)
    vtype=$(echo $ventry | cut -d $sep -f 4)
    _currentRoot=$(echo $ventry | cut -d $sep -f 5)
    _info "Verifying:$d"
    _debug "d" "$d"
    _debug "keyauthorization" "$keyauthorization"
    _debug "uri" "$uri"
    removelevel=""
    token=""

    _debug "_currentRoot" "$_currentRoot"

      
    if [[ "$vtype" == "$VTYPE_HTTP" ]] ; then
      if [[ "$_currentRoot" == "no" ]] ; then
        _info "Standalone mode server"
        _startserver "$keyauthorization" &
        if [[ "$?" != "0" ]] ; then
          return 1
        fi
        serverproc="$!"
        sleep 2
        _debug serverproc $serverproc

      else
        if [[ -z "$wellknown_path" ]] ; then
          wellknown_path="$_currentRoot/.well-known/acme-challenge"
        fi
        _debug wellknown_path "$wellknown_path"
        
        if [[ ! -d "$_currentRoot/.well-known" ]] ; then 
          removelevel='1'
        elif [[ ! -d "$_currentRoot/.well-known/acme-challenge" ]] ; then 
          removelevel='2'
        else
          removelevel='3'
        fi
        
        token="$(echo -e -n "$keyauthorization" | cut -d '.' -f 1)"
        _debug "writing token:$token to $wellknown_path/$token"

        mkdir -p "$wellknown_path"
        echo -n "$keyauthorization" > "$wellknown_path/$token"
        if [[ ! "$usingApache" ]] ; then
          webroot_owner=$(_stat $_currentRoot)
          _debug "Changing owner/group of .well-known to $webroot_owner"
          chown -R $webroot_owner "$_currentRoot/.well-known"
        fi
        
      fi
    fi
    
    _send_signed_request $uri "{\"resource\": \"challenge\", \"keyAuthorization\": \"$keyauthorization\"}"
    
    if [[ ! -z "$code" ]] && [[ ! "$code" == '202' ]] ; then
      _err "$d:Challenge error: $response"
      _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
      _clearup
      return 1
    fi
    
    waittimes=0
    if [[ -z "$MAX_RETRY_TIMES" ]] ; then
      MAX_RETRY_TIMES=30
    fi
    
    while [[ "1" ]] ; do
      let "waittimes+=1"
      if [[ "$waittimes" -ge "$MAX_RETRY_TIMES" ]] ; then
        _err "$d:Timeout"
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        return 1
      fi
      
      _debug "sleep 5 secs to verify"
      sleep 5
      _debug "checking"
      response="$(_get $uri)"
      if [[ "$?" != "0" ]] ; then
        _err "$d:Verify error:$response"
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        return 1
      fi
      
      status=$(echo $response | egrep -o  '"status":"[^"]*' | cut -d : -f 2 | tr -d '"')
      if [[ "$status" == "valid" ]] ; then
        _info "Success"
        _stopserver $serverproc
        serverproc=""
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        break;
      fi
      
      if [[ "$status" == "invalid" ]] ; then
         error=$(echo $response | egrep -o '"error":{[^}]*}' | grep -o '"detail":"[^"]*"' | cut -d '"' -f 4)
        _err "$d:Verify error:$error"
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        return 1;
      fi
      
      if [[ "$status" == "pending" ]] ; then
        _info "Pending"
      else
        _err "$d:Verify error:$response" 
        _clearupwebbroot "$_currentRoot" "$removelevel" "$token"
        _clearup
        return 1
      fi
      
    done
    
  done

  _clearup
  _info "Verify finished, start to sign."
  der="$(_getfile "${CSR_PATH}" "${BEGIN_CSR}" "${END_CSR}" | tr -d "\r\n" | _urlencode)"
  _send_signed_request "$API/acme/new-cert" "{\"resource\": \"new-cert\", \"csr\": \"$der\"}" "needbase64"
  
  
  Le_LinkCert="$(grep -i -o '^Location.*$' $HTTP_HEADER | head -1 | tr -d "\r\n" | cut -d " " -f 2)"
  _setopt "$DOMAIN_CONF"  "Le_LinkCert"           "="  "$Le_LinkCert"

  if [[ "$Le_LinkCert" ]] ; then
    echo "$BEGIN_CERT" > "$CERT_PATH"
    _get "$Le_LinkCert" | _base64 "multiline"  >> "$CERT_PATH"
    echo "$END_CERT"  >> "$CERT_PATH"
    _info "Cert success."
    cat "$CERT_PATH"
    
    _info "Your cert is in $CERT_PATH"
    cp "$CERT_PATH" "$CERT_FULLCHAIN_PATH"

    if [[ ! "$USER_PATH" ]] || [[ ! "$IN_CRON" ]] ; then
      USER_PATH="$PATH"
      _saveaccountconf "USER_PATH" "$USER_PATH"
    fi
  fi
  

  if [[ -z "$Le_LinkCert" ]] ; then
    response="$(echo $response | _dbase64 "multiline" )"
    _err "Sign failed: $(echo "$response" | grep -o  '"detail":"[^"]*"')"
    return 1
  fi
  
  _setopt "$DOMAIN_CONF"  'Le_Vlist' '=' "\"\""
  
  Le_LinkIssuer=$(grep -i '^Link' $HTTP_HEADER | head -1 | cut -d " " -f 2| cut -d ';' -f 1 | tr -d '<>' )
  _setopt "$DOMAIN_CONF"  "Le_LinkIssuer"         "="  "$Le_LinkIssuer"
  
  if [[ "$Le_LinkIssuer" ]] ; then
    echo "$BEGIN_CERT" > "$CA_CERT_PATH"
    _get "$Le_LinkIssuer" | _base64 "multiline"  >> "$CA_CERT_PATH"
    echo "$END_CERT"  >> "$CA_CERT_PATH"
    _info "The intermediate CA cert is in $CA_CERT_PATH"
    cat "$CA_CERT_PATH" >> "$CERT_FULLCHAIN_PATH"
    _info "And the full chain certs is there: $CERT_FULLCHAIN_PATH"
  fi
  
  Le_CertCreateTime=$(date -u "+%s")
  _setopt "$DOMAIN_CONF"  "Le_CertCreateTime"     "="  "$Le_CertCreateTime"
  
  Le_CertCreateTimeStr=$(date -u )
  _setopt "$DOMAIN_CONF"  "Le_CertCreateTimeStr"  "="  "\"$Le_CertCreateTimeStr\""
  
  if [[ ! "$Le_RenewalDays" ]] ; then
    Le_RenewalDays=80
  fi
  
  _setopt "$DOMAIN_CONF"  "Le_RenewalDays"      "="  "$Le_RenewalDays"
  
  let "Le_NextRenewTime=Le_CertCreateTime+Le_RenewalDays*24*60*60"
  _setopt "$DOMAIN_CONF"  "Le_NextRenewTime"      "="  "$Le_NextRenewTime"
  
  Le_NextRenewTimeStr=$( _time2str $Le_NextRenewTime )
  _setopt "$DOMAIN_CONF"  "Le_NextRenewTimeStr"      "="  "\"$Le_NextRenewTimeStr\""


  installcert $Le_Domain  "$Le_RealCertPath" "$Le_RealKeyPath" "$Le_RealCACertPath" "$Le_ReloadCmd" "$Le_RealFullChainPath"

}

renew() {
  Le_Domain="$1"
  if [[ -z "$Le_Domain" ]] ; then
    _err "Usage: $PROJECT_ENTRY --renew  -d domain.com"
    return 1
  fi

  _initpath $Le_Domain

  if [[ ! -f "$DOMAIN_CONF" ]] ; then
    _info "$Le_Domain is not a issued domain, skip."
    return 0;
  fi
  
  source "$DOMAIN_CONF"
  if [[ -z "$FORCE" ]] && [[ "$Le_NextRenewTime" ]] && [[ "$(date -u "+%s" )" -lt "$Le_NextRenewTime" ]] ; then 
    _info "Skip, Next renewal time is: $Le_NextRenewTimeStr"
    return 2
  fi
  
  IS_RENEW="1"
  issue "$Le_Webroot" "$Le_Domain" "$Le_Alt" "$Le_Keylength" "$Le_RealCertPath" "$Le_RealKeyPath" "$Le_RealCACertPath" "$Le_ReloadCmd" "$Le_RealFullChainPath"
  local res=$?
  IS_RENEW=""

  return $res
}

renewAll() {
  _initpath
  _info "renewAll"
  
  for d in $(ls -F ${LE_WORKING_DIR}/ | grep [^.].*[.].*/$ ) ; do
    d=$(echo $d | cut -d '/' -f 1)
    _info "renew $d"
    
    Le_LinkCert=""
    Le_Domain=""
    Le_Alt="no"
    Le_Webroot=""
    Le_Keylength=""
    Le_LinkIssuer=""

    Le_CertCreateTime=""
    Le_CertCreateTimeStr=""
    Le_RenewalDays=""
    Le_NextRenewTime=""
    Le_NextRenewTimeStr=""

    Le_RealCertPath=""
    Le_RealKeyPath=""
    
    Le_RealCACertPath=""

    Le_ReloadCmd=""
    Le_RealFullChainPath=""
    
    DOMAIN_PATH=""
    DOMAIN_CONF=""
    DOMAIN_SSL_CONF=""
    CSR_PATH=""
    CERT_KEY_PATH=""
    CERT_PATH=""
    CA_CERT_PATH=""
    CERT_PFX_PATH=""
    CERT_FULLCHAIN_PATH=""
    ACCOUNT_KEY_PATH=""
    
    wellknown_path=""
    
    renew "$d"  
  done
  
}

installcert() {
  Le_Domain="$1"
  if [[ -z "$Le_Domain" ]] ; then
    echo "Usage: $PROJECT_ENTRY --installcert -d domain.com  [--certpath cert-file-path]  [--keypath key-file-path]  [--capath ca-cert-file-path]   [ --reloadCmd reloadCmd] [--fullchainpath fullchain-path]"
    return 1
  fi

  Le_RealCertPath="$2"
  Le_RealKeyPath="$3"
  Le_RealCACertPath="$4"
  Le_ReloadCmd="$5"
  Le_RealFullChainPath="$6"

  _initpath $Le_Domain

  _setopt "$DOMAIN_CONF"  "Le_RealCertPath"       "="  "\"$Le_RealCertPath\""
  _setopt "$DOMAIN_CONF"  "Le_RealCACertPath"     "="  "\"$Le_RealCACertPath\""
  _setopt "$DOMAIN_CONF"  "Le_RealKeyPath"        "="  "\"$Le_RealKeyPath\""
  _setopt "$DOMAIN_CONF"  "Le_ReloadCmd"          "="  "\"$Le_ReloadCmd\""
  _setopt "$DOMAIN_CONF"  "Le_RealFullChainPath"  "="  "\"$Le_RealFullChainPath\""
  
  if [[ "$Le_RealCertPath" ]] ; then
    if [[ -f "$Le_RealCertPath" ]] ; then
      cp -p "$Le_RealCertPath" "$Le_RealCertPath".bak
    fi
    cat "$CERT_PATH" > "$Le_RealCertPath"
  fi
  
  if [[ "$Le_RealCACertPath" ]] ; then
    if [[ "$Le_RealCACertPath" == "$Le_RealCertPath" ]] ; then
      echo "" >> "$Le_RealCACertPath"
      cat "$CA_CERT_PATH" >> "$Le_RealCACertPath"
    else
      if [[ -f "$Le_RealCACertPath" ]] ; then
        cp -p "$Le_RealCACertPath" "$Le_RealCACertPath".bak
      fi
      cat "$CA_CERT_PATH" > "$Le_RealCACertPath"
    fi
  fi


  if [[ "$Le_RealKeyPath" ]] ; then
    if [[ -f "$Le_RealKeyPath" ]] ; then
      cp -p "$Le_RealKeyPath" "$Le_RealKeyPath".bak
    fi
    cat "$CERT_KEY_PATH" > "$Le_RealKeyPath"
  fi
  
  if [[ "$Le_RealFullChainPath" ]] ; then
    if [[ -f "$Le_RealFullChainPath" ]] ; then
      cp -p "$Le_RealFullChainPath" "$Le_RealFullChainPath".bak
    fi
    cat "$CERT_FULLCHAIN_PATH" > "$Le_RealFullChainPath"
  fi  

  if [[ "$Le_ReloadCmd" ]] ; then
    _info "Run Le_ReloadCmd: $Le_ReloadCmd"
    (cd "$DOMAIN_PATH" && eval "$Le_ReloadCmd")
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
    if [[ -f "$LE_WORKING_DIR/$PROJECT_ENTRY" ]] ; then
      lesh="\"$LE_WORKING_DIR\"/$PROJECT_ENTRY"
    else
      _err "Can not install cronjob, $PROJECT_ENTRY not found."
      return 1
    fi
    crontab -l | { cat; echo "0 0 * * * $lesh --cron --home \"$LE_WORKING_DIR\" > /dev/null"; } | crontab -
  fi
  if [[ "$?" != "0" ]] ; then
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
  if [[ "$cr" ]] ; then 
    crontab -l | sed "/$PROJECT_ENTRY --cron/d" | crontab -
    LE_WORKING_DIR="$(echo "$cr" | cut -d ' ' -f 9 | tr -d '"')"
    _info LE_WORKING_DIR "$LE_WORKING_DIR"
  fi 
  _initpath

}

revoke() {
  Le_Domain="$1"
  if [[ -z "$Le_Domain" ]] ; then
    echo "Usage: $PROJECT_ENTRY --revoke -d domain.com"
    return 1
  fi
  
  _initpath $Le_Domain
  if [[ ! -f "$DOMAIN_CONF" ]] ; then
    _err "$Le_Domain is not a issued domain, skip."
    return 1;
  fi
  
  if [[ ! -f "$CERT_PATH" ]] ; then
    _err "Cert for $Le_Domain $CERT_PATH is not found, skip."
    return 1
  fi
  
  cert="$(_getfile "${CERT_PATH}" "${BEGIN_CERT}" "${END_CERT}"| tr -d "\r\n" | _urlencode)"

  if [[ -z "$cert" ]] ; then
    _err "Cert for $Le_Domain is empty found, skip."
    return 1
  fi
  
  data="{\"resource\": \"revoke-cert\", \"certificate\": \"$cert\"}"
  uri="$API/acme/revoke-cert"

  _info "Try domain key first."
  if _send_signed_request $uri "$data" "" "$CERT_KEY_PATH"; then
    if [[ -z "$response" ]] ; then
      _info "Revoke success."
      rm -f $CERT_PATH
      return 0
    else 
      _err "Revoke error by domain key."
      _err "$resource"
    fi
  fi
  
  _info "Then try account key."

  if _send_signed_request $uri "$data" "" "$ACCOUNT_KEY_PATH" ; then
    if [[ -z "$response" ]] ; then
      _info "Revoke success."
      rm -f $CERT_PATH
      return 0
    else 
      _err "Revoke error."
      _debug "$resource"
    fi
  fi
  return 1
}

# Detect profile file if not specified as environment variable
_detect_profile() {
  if [ -n "$PROFILE" -a -f "$PROFILE" ] ; then
    echo "$PROFILE"
    return
  fi

  local DETECTED_PROFILE
  DETECTED_PROFILE=''
  local SHELLTYPE
  SHELLTYPE="$(basename "/$SHELL")"

  if [[ "$SHELLTYPE" = "bash" ]] ; then
    if [[ -f "$HOME/.bashrc" ]] ; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]] ; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    fi
  elif [[ "$SHELLTYPE" = "zsh" ]] ; then
    DETECTED_PROFILE="$HOME/.zshrc"
  fi

  if [[ -z "$DETECTED_PROFILE" ]] ; then
    if [[ -f "$HOME/.profile" ]] ; then
      DETECTED_PROFILE="$HOME/.profile"
    elif [[ -f "$HOME/.bashrc" ]] ; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [[ -f "$HOME/.bash_profile" ]] ; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    elif [[ -f "$HOME/.zshrc" ]] ; then
      DETECTED_PROFILE="$HOME/.zshrc"
    fi
  fi

  if [[ ! -z "$DETECTED_PROFILE" ]] ; then
    echo "$DETECTED_PROFILE"
  fi
}

_initconf() {
  _initpath
  if [[ ! -f "$ACCOUNT_CONF_PATH" ]] ; then
    echo "#ACCOUNT_CONF_PATH=xxxx

#Account configurations:
#Here are the supported macros, uncomment them to make them take effect.

#ACCOUNT_EMAIL=aaa@aaa.com  # the account email used to register account.
#ACCOUNT_KEY_PATH=\"/path/to/account.key\"

#STAGE=1 # Use the staging api
#FORCE=1 # Force to issue cert
#DEBUG=1 # Debug mode

#ACCOUNT_KEY_HASH=account key hash

USER_AGENT=\"$USER_AGENT\"

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

    " > $ACCOUNT_CONF_PATH
  fi
}

_precheck() {
  if ! _exists "curl"  && ! _exists "wget"; then
    _err "Please install curl or wget first, we need to access http resources."
    return 1
  fi
  
  if ! _exists "crontab" ; then
    _err "It is recommended to install crontab first. try to install 'cron, crontab, crontabs or vixie-cron'."
    _err "We need to set cron job to renew the certs automatically."
    _err "Otherwise, your certs will not be able to be renewed automatically."
    if [[ -z "$FORCE" ]] ; then
      _err "Please add '--force' and try install again to go without crontab."
      _err "./$PROJECT_ENTRY --install --force"
      return 1
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

install() {

  if ! _initpath ; then
    _err "Install failed."
    return 1
  fi

  if ! _precheck ; then
    _err "Pre-check failed, can not install."
    return 1
  fi
  
  #convert from le
  if [[ -d "$HOME/.le" ]] ; then
    for envfile in "le.env" "le.sh.env"
    do
      if [[ -f "$HOME/.le/$envfile" ]] ; then
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
    _err "Can not craete working dir: $LE_WORKING_DIR"
    return 1
  fi
  
  cp $PROJECT_ENTRY "$LE_WORKING_DIR/" && chmod +x "$LE_WORKING_DIR/$PROJECT_ENTRY"

  if [[ "$?" != "0" ]] ; then
    _err "Install failed, can not copy $PROJECT_ENTRY"
    return 1
  fi

  _info "Installed to $LE_WORKING_DIR/$PROJECT_ENTRY"

  _profile="$(_detect_profile)"
  if [[ "$_profile" ]] ; then
    _debug "Found profile: $_profile"
    
    _envfile="$LE_WORKING_DIR/$PROJECT_ENTRY.env"
    if [[ "$_upgrading" == "1" ]] ; then
      echo "$(cat $_envfile)" | sed "s|^LE_WORKING_DIR.*$||" > "$_envfile"
      echo "$(cat $_envfile)" | sed "s|^alias le.*$||" > "$_envfile"
      echo "$(cat $_envfile)" | sed "s|^alias le.sh.*$||" > "$_envfile"
    fi
    
    _setopt "$_envfile" "LE_WORKING_DIR" "=" "\"$LE_WORKING_DIR\""
    _setopt "$_envfile" "alias $PROJECT_ENTRY" "=" "\"$LE_WORKING_DIR/$PROJECT_ENTRY\""
    
    echo "" >> "$_profile"
    _setopt "$_profile" "source \"$LE_WORKING_DIR/$PROJECT_NAME.env\""
    _info "OK, Close and reopen your terminal to start using $PROJECT_NAME"
  else
    _info "No profile is found, you will need to go into $LE_WORKING_DIR to use $PROJECT_NAME"
  fi

  mkdir -p $LE_WORKING_DIR/dnsapi
  cp  dnsapi/* $LE_WORKING_DIR/dnsapi/
  
  #to keep compatible mv the .acc file to .key file 
  if [[ -f "$LE_WORKING_DIR/account.acc" ]] ; then
    mv "$LE_WORKING_DIR/account.acc" "$LE_WORKING_DIR/account.key"
  fi

  if [[ ! -f "$ACCOUNT_CONF_PATH" ]] ; then
    _initconf
  fi

  if [[ "$_DEFAULT_ACCOUNT_CONF_PATH" != "$ACCOUNT_CONF_PATH" ]] ; then
    _setopt "$_DEFAULT_ACCOUNT_CONF_PATH" "ACCOUNT_CONF_PATH" "=" "\"$ACCOUNT_CONF_PATH\""
  fi

  installcronjob
  
  _info OK
}

uninstall() {
  uninstallcronjob
  _initpath

  _profile="$(_detect_profile)"
  if [[ "$_profile" ]] ; then
    text="$(cat $_profile)"
    echo "$text" | sed "s|^source.*$PROJECT_NAME.env.*$||" > "$_profile"
  fi

  rm -f $LE_WORKING_DIR/$PROJECT_ENTRY
  _info "The keys and certs are in $LE_WORKING_DIR, you can remove them by yourself."

}

cron() {
  IN_CRON=1
  renewAll
  IN_CRON=""
}

version() {
  echo "$PROJECT"
  echo "v$VER"
}

showhelp() {
  version
  echo "Usage: $PROJECT_ENTRY  command ...[parameters]....
Commands:
  --help, -h               Show this help message.
  --version, -v            Show version info.
  --install                Install $PROJECT_NAME to your system.
  --uninstall              Uninstall $PROJECT_NAME, and uninstall the cron job.
  --issue                  Issue a cert.
  --installcert            Install the issued cert to apache/nginx or any other server.
  --renew, -r              Renew a cert.
  --renewAll               Renew all the certs
  --revoke                 Revoke a cert.
  --installcronjob         Install the cron job to renew certs, you don't need to call this. The 'install' command can automatically install the cron job.
  --uninstallcronjob       Uninstall the cron job. The 'uninstall' command can do this automatically.
  --cron                   Run cron job to renew all the certs.
  --toPkcs                 Export the certificate and key to a pfx file.
  --createAccountKey, -cak Create an account private key, professional use.
  --createDomainKey, -cdk  Create an domain private key, professional use.
  --createCSR, -ccsr       Create CSR , professional use.
  
Parameters:
  --domain, -d   domain.tld         Specifies a domain, used to issue, renew or revoke etc.
  --force, -f                       Used to force to install or force to renew a cert immediately.
  --staging, --test                 Use staging server, just for test.
  --debug                           Output debug info.
    
  --webroot, -w  /path/to/webroot   Specifies the web root folder for web root mode.
  --standalone                      Use standalone mode.
  --apache                          Use apache mode.
  --dns [dns-cf|dns-dp|dns-cx|/path/to/api/file]   Use dns mode or dns api.
  
  --keylength, -k [2048]            Specifies the domain key length: 2048, 3072, 4096, 8192 or ec-256, ec-384.
  --accountkeylength, -ak [2048]    Specifies the account key length.
  
  These parameters are to install the cert to nginx/apache or anyother server after issue/renew a cert:
  
  --certpath /path/to/real/cert/file  After issue/renew, the cert will be copied to this path.
  --keypath /path/to/real/key/file  After issue/renew, the key will be copied to this path.
  --capath /path/to/real/ca/file    After issue/renew, the intermediate cert will be copied to this path.
  --fullchainpath /path/to/fullchain/file After issue/renew, the fullchain cert will be copied to this path.
  
  --reloadcmd \"service nginx reload\" After issue/renew, it's used to reload the server.

  --accountconf                     Specifies a customized account config file.
  --home                            Specifies the home dir for $PROJECT_NAME .
  --useragent                       Specifies the user agent string. it will be saved for future use too.
  --accountemail                    Specifies the account email for registering, Only valid for the '--install' command.
  --accountkey                      Specifyes the account key path, Only valid for the '--install' command.
  
  "
}

_installOnline() {
  _info "Installing from online archive."
  if [[ ! "$BRANCH" ]] ; then
    BRANCH="master"
  fi
  _initpath
  target="$PROJECT/archive/$BRANCH.tar.gz"
  _info "Downloading $target"
  localname="$BRANCH.tar.gz"
  if ! _get "$target" > $localname ; then
    _debug "Download error."
    return 1
  fi
  _info "Extracting $localname"
  tar xzf $localname
  cd "$PROJECT_NAME-$BRANCH"
  chmod +x $PROJECT_ENTRY
  if ./$PROJECT_ENTRY install ; then
    _info "Install success!"
  fi
  
  cd ..
  rm -rf "$PROJECT_NAME-$BRANCH"
  rm -f "$localname"
}


_process() {
  _CMD=""
  _domain=""
  _altdomains="no"
  _webroot=""
  _keylength="no"
  _accountkeylength="no"
  _certpath="no"
  _keypath="no"
  _capath="no"
  _fullchainpath="no"
  _reloadcmd="no"
  _password=""
  _accountconf=""
  _useragent=""
  _accountemail=""
  _accountkey=""
  while (( ${#} )); do
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
    --issue)
        _CMD="issue"
        ;;
    --installcert|-i)
        _CMD="installcert"
        ;;
    --renew|-r)
        _CMD="renew"
        ;;
    --renewAll|-renewall)
        _CMD="renewAll"
        ;;
    --revoke)
        _CMD="revoke"
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

     
    --domain|-d)
        _dvalue="$2"
        
        if [[ -z "$_dvalue" ]] || [[ "$_dvalue" == "-"* ]] ; then
          _err "'$_dvalue' is not a valid domain for parameter '$1'"
          return 1
        fi
        
        if [[ -z "$_domain" ]] ; then
          _domain="$_dvalue"
        else
          if [[ "$_altdomains" == "no" ]] ; then
            _altdomains="$_dvalue"
          else
            _altdomains="$_altdomains,$_dvalue"
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
        if [[ "$2" == "-"* ]] || [[ -z "$2" ]]; then
          DEBUG="1"
        else
          DEBUG="$2"
          shift
        fi 
        ;;
    --webroot|-w)
        wvalue="$2"
        if [[ -z "$_webroot" ]] ; then
          _webroot="$wvalue"
        else
          _webroot="$_webroot,$wvalue"
        fi
        shift
        ;;        
    --standalone)
        wvalue="no"
        if [[ -z "$_webroot" ]] ; then
          _webroot="$wvalue"
        else
          _webroot="$_webroot,$wvalue"
        fi
        ;;
    --apache)
        wvalue="apache"
        if [[ -z "$_webroot" ]] ; then
          _webroot="$wvalue"
        else
          _webroot="$_webroot,$wvalue"
        fi
        ;;
    --dns)
        wvalue="dns"
        if [[ "$2" != "-"* ]] ; then
          wvalue="$2"
          shift
        fi
        if [[ -z "$_webroot" ]] ; then
          _webroot="$wvalue"
        else
          _webroot="$_webroot,$wvalue"
        fi
        ;;
    --keylength|-k)
        _keylength="$2"
        accountkeylength="$2"
        shift
        ;;
    --accountkeylength|-ak)
        accountkeylength="$2"
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
    *)
        _err "Unknown parameter : $1"
        return 1
        ;;
    esac

    shift 1
  done


  case "${_CMD}" in
    install) install ;;
    uninstall) uninstall ;;
    issue)
      issue  "$_webroot"  "$_domain" "$_altdomains" "$_keylength" "$_certpath" "$_keypath" "$_capath" "$_reloadcmd" "$_fullchainpath"
      ;;
    installcert)
      installcert "$_domain" "$_certpath" "$_keypath" "$_capath" "$_reloadcmd" "$_fullchainpath"
      ;;
    renew) 
      renew "$_domain" 
      ;;
    renewAll) 
      renewAll 
      ;;
    revoke) 
      revoke "$_domain" 
      ;;
    installcronjob) installcronjob ;;
    uninstallcronjob) uninstallcronjob ;;
    cron) cron ;;
    toPkcs) 
      toPkcs "$_domain" "$_password"
      ;;
    createAccountKey) 
      createAccountKey "$_domain" "$_accountkeylength"
      ;;
    createDomainKey) 
      createDomainKey "$_domain" "$_keylength"
      ;;
    createCSR) 
      createCSR "$_domain" "$_altdomains"
      ;;

    *)
      _err "Invalid command: $_CMD"
      showhelp;
      return 1
    ;;
  esac
  
  if [[ "$_useragent" ]] ; then
    _saveaccountconf "USER_AGENT" "$_useragent"
  fi
  if [[ "$_accountemail" ]] ; then
    _saveaccountconf "ACCOUNT_EMAIL" "$_accountemail"
  fi
  if [[ "$_accountkey" ]] ; then
    _saveaccountconf "ACCOUNT_KEY_PATH" "$_accountkey"
  fi  

}


if [[ "$INSTALLONLINE" ]] ; then
  INSTALLONLINE=""
  _installOnline $BRANCH
  exit
fi

if [[ -z "$1" ]] ; then
  showhelp
else
  if [[ "$1" == "-"* ]] ; then
    _process "$@"
  else
    "$@"
  fi
fi


