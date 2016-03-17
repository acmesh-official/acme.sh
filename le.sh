#!/usr/bin/env bash
VER=1.1.9
PROJECT="https://github.com/Neilpang/le"

DEFAULT_CA="https://acme-v01.api.letsencrypt.org"
DEFAULT_AGREEMENT="https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf"

STAGE_CA="https://acme-staging.api.letsencrypt.org"

VTYPE_HTTP="http-01"
VTYPE_DNS="dns-01"

BEGIN_CSR="-----BEGIN CERTIFICATE REQUEST-----"
END_CSR="-----END CERTIFICATE REQUEST-----"

BEGIN_CERT="-----BEGIN CERTIFICATE-----"
END_CERT="-----END CERTIFICATE-----"

if [ -z "$AGREEMENT" ] ; then
  AGREEMENT="$DEFAULT_AGREEMENT"
fi

_debug() {

  if [ -z "$DEBUG" ] ; then
    return
  fi
  
  if [ -z "$2" ] ; then
    echo $1
  else
    echo "$1"="$2"
  fi
}

_info() {
  if [ -z "$2" ] ; then
    echo "$1"
  else
    echo "$1"="$2"
  fi
}

_err() {
  if [ -z "$2" ] ; then
    echo "$1" >&2
  else
    echo "$1"="$2" >&2
  fi
  return 1
}

_h2b() {
  hex=$(cat)
  i=1
  j=2
  while [ '1' ] ; do
    h=$(printf $hex | cut -c $i-$j)
    if [ -z "$h" ] ; then
      break;
    fi
    printf "\x$h"
    let "i+=2"
    let "j+=2"
  done
}

#Usage: file startline endline
_getfile() {
  filename="$1"
  startline="$2"
  endline="$3"
  if [ -z "$endline" ] ; then
    _err "Usage: file startline endline"
    return 1
  fi
  
  i="$(grep -n --  "$startline"  $filename | cut -d : -f 1)"
  if [ -z "$i" ] ; then
    _err "Can not find start line: $startline"
    return 1
  fi
  let "i+=1"
  _debug i $i
  
  j="$(grep -n --  "$endline"  $filename | cut -d : -f 1)"
  if [ -z "$j" ] ; then
    _err "Can not find end line: $endline"
    return 1
  fi
  let "j-=1"
  _debug j $j
  
  sed -n $i,${j}p  "$filename"

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

#Usage: hashalg
#Output Base64-encoded digest
_digest() {
  alg="$1"
  if [ -z "$alg" ] ; then
    _err "Usage: _digest hashalg"
    return 1
  fi
  
  if [ "$alg" == "sha256" ] ; then
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
  if [ -z "$alg" ] ; then
    _err "Usage: _sign keyfile hashalg"
    return 1
  fi
  
  if [ "$alg" == "sha256" ] ; then
    openssl   dgst   -sha256  -sign  "$keyfile" | _base64
  else
    _err "$alg is not supported yet"
    return 1
  fi  
  
}

_ss() {
  _port="$1"
  if command -v "netstat" >/dev/null 2>&1 ; then
    _debug "Using: netstat"
    netstat -ntpl | grep :$_port" "
    return 0
  fi
  if command -v "ss" >/dev/null 2>&1 ; then
    _debug "Using: ss"
    ss -ntpl | grep :$_port" "
    return 0
  fi
  return 1
}

#domain [2048]  
createAccountKey() {
  _info "Creating account key"
  if [ -z "$1" ] ; then
    echo Usage: createAccountKey account-domain  [2048]
    return
  fi
  
  account=$1
  length=$2
  
  if [[ "$length" == "ec-"* ]] ; then
    length=2048
  fi
  
  if [ -z "$2" ] ; then
    _info "Use default length 2048"
    length=2048
  fi
  _initpath
  
  if [ -f "$ACCOUNT_KEY_PATH" ] ; then
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
  if [ -z "$1" ] ; then
    echo Usage: createDomainKey domain  [2048]
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

  if [ -z "$length" ] ; then
    if [ "$isec" ] ; then
      length=256
    else
      length=2048
    fi
  fi
  _info "Use length $length"

  if [ "$isec" ] ; then
    if [ "$length" == "256" ] ; then
      eccname="prime256v1"
    fi
    if [ "$length" == "384" ] ; then
      eccname="secp384r1"
    fi
    if [ "$length" == "521" ] ; then
      eccname="secp521r1"
    fi
    _info "Using ec name: $eccname"
  fi
  
  _initpath $domain
  
  if [ ! -f "$CERT_KEY_PATH" ] || ( [ "$FORCE" ] && ! [ "$IS_RENEW" ] ); then 
    #generate account key
    if [ "$isec" ] ; then
      openssl ecparam  -name $eccname -genkey 2>/dev/null > "$CERT_KEY_PATH"
    else
      openssl genrsa $length 2>/dev/null > "$CERT_KEY_PATH"
    fi
  else
    if [ "$IS_RENEW" ] ; then
      _info "Domain key exists, skip"
      return 0
    else
      _err "Domain key exists, do you want to overwrite the key?"
      _err "Set FORCE=1, and try again."
      return 1
    fi
  fi

}

# domain  domainlist
createCSR() {
  _info "Creating csr"
  if [ -z "$1" ] ; then
    echo Usage: $0 domain  [domainlist]
    return
  fi
  domain=$1
  _initpath $domain
  
  domainlist=$2
  
  if [ -f "$CSR_PATH" ]  && [ "$IS_RENEW" ] && ! [ "$FORCE" ]; then
    _info "CSR exists, skip"
    return
  fi
  
  if [ -z "$domainlist" ] ; then
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
  if [ -z "$keyfile" ] ; then
    _err "Usage: _calcjwk keyfile"
    return 1
  fi
  EC_SIGN=""
  if grep "BEGIN RSA PRIVATE KEY" "$keyfile" > /dev/null 2>&1 ; then
    _debug "RSA key"
    pub_exp=$(openssl rsa -in $keyfile  -noout -text | grep "^publicExponent:"| cut -d '(' -f 2 | cut -d 'x' -f 2 | cut -d ')' -f 1)
    if [ "${#pub_exp}" == "5" ] ; then
      pub_exp=0$pub_exp
    fi
    _debug pub_exp "$pub_exp"
    
    e=$(echo $pub_exp | _h2b | _base64)
    _debug e "$e"
    
    modulus=$(openssl rsa -in $keyfile -modulus -noout | cut -d '=' -f 2 )
    n=$(echo $modulus| _h2b | _base64 | _urlencode )
    jwk='{"e": "'$e'", "kty": "RSA", "n": "'$n'"}'
    _debug jwk "$jwk"
    
    HEADER='{"alg": "RS256", "jwk": '$jwk'}'
    HEADERPLACE='{"nonce": "NONCE", "alg": "RS256", "jwk": '$jwk'}'
  elif grep "BEGIN EC PRIVATE KEY" "$keyfile" > /dev/null 2>&1 ; then
    _debug "EC key"
    EC_SIGN="1"
    crv="$(openssl ec  -in $keyfile  -noout -text 2>/dev/null | grep "^NIST CURVE:" | cut -d ":" -f 2 | tr -d " \r\n")"
    _debug crv $crv
    
    pubi="$(openssl ec  -in $keyfile  -noout -text 2>/dev/null | grep -n pub: | cut -d : -f 1)"
    _debug pubi $pubi
    let "pubi=pubi+1"
    
    pubj="$(openssl ec  -in $keyfile  -noout -text 2>/dev/null | grep -n "ASN1 OID:"  | cut -d : -f 1)"
    _debug pubj $pubj
    let "pubj=pubj-1"
    
    pubtext="$(openssl ec  -in $keyfile  -noout -text 2>/dev/null | sed  -n "$pubi,${pubj}p" | tr -d " \n\r")"
    _debug pubtext "$pubtext"
    
    xlen="$(printf "$pubtext" | tr -d ':' | wc -c)"
    let "xlen=xlen/4"
    _debug xlen $xlen
    
    let "xend=xlen+1"
    x="$(printf $pubtext | cut -d : -f 2-$xend)"
    _debug x $x
    
    x64="$(printf $x | tr -d : | _h2b | _base64 | _urlencode)"
    _debug x64 $x64
    
    let "xend+=1"
    y="$(printf $pubtext | cut -d : -f $xend-10000)"
    _debug y $y
    
    y64="$(printf $y | tr -d : | _h2b | _base64 | _urlencode)"
    _debug y64 $y64
   
    jwk='{"kty": "EC", "crv": "'$crv'", "x": "'$x64'", "y": "'$y64'"}'
    _debug jwk "$jwk"
    
    HEADER='{"alg": "ES256", "jwk": '$jwk'}'
    HEADERPLACE='{"nonce": "NONCE", "alg": "ES256", "jwk": '$jwk'}'

  else
    _err "Only RSA or EC key is supported."
    return 1
  fi

  _debug HEADER "$HEADER"
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
  
  CURL_HEADER="$LE_WORKING_DIR/curl.header"
  dp="$LE_WORKING_DIR/curl.dump"
  CURL="curl --silent --dump-header $CURL_HEADER "
  if [ "$DEBUG" ] ; then
    CURL="$CURL --trace-ascii $dp "
  fi
  payload64=$(echo -n $payload | _base64 | _urlencode)
  _debug payload64 $payload64
  
  nonceurl="$API/directory"
  nonce="$($CURL -I $nonceurl | grep -o "^Replay-Nonce:.*$" | tr -d "\r\n" | cut -d ' ' -f 2)"

  _debug nonce "$nonce"
  
  protected="$(printf "$HEADERPLACE" | sed "s/NONCE/$nonce/" )"
  _debug protected "$protected"
  
  protected64="$(printf "$protected" | _base64 | _urlencode)"
  _debug protected64 "$protected64"

  sig=$(echo -n "$protected64.$payload64" |  _sign  "$keyfile" "sha256" | _urlencode)
  _debug sig "$sig"
  
  body="{\"header\": $HEADER, \"protected\": \"$protected64\", \"payload\": \"$payload64\", \"signature\": \"$sig\"}"
  _debug body "$body"
  
  if [ "$needbase64" ] ; then
    response="$($CURL -X POST --data "$body" $url | _base64)"
  else
    response="$($CURL -X POST --data "$body" $url)"
  fi

  responseHeaders="$(cat $CURL_HEADER)"
  
  _debug responseHeaders "$responseHeaders"
  _debug response  "$response"
  code="$(grep ^HTTP $CURL_HEADER | tail -1 | cut -d " " -f 2 | tr -d "\r\n" )"
  _debug code $code

}

_get() {
  url="$1"
  _debug url $url
  response="$(curl --silent $url)"
  ret=$?
  _debug response  "$response"
  code="$(echo $response | grep -o '"status":[0-9]\+' | cut -d : -f 2)"
  _debug code $code
  return $ret
}

#setopt "file"  "opt"  "="  "value" [";"]
_setopt() {
  __conf="$1"
  __opt="$2"
  __sep="$3"
  __val="$4"
  __end="$5"
  if [ -z "$__opt" ] ; then 
    echo usage: _setopt  '"file"  "opt"  "="  "value" [";"]'
    return
  fi
  if [ ! -f "$__conf" ] ; then
    touch "$__conf"
  fi

  if grep -H -n "^$__opt$__sep" "$__conf" > /dev/null ; then
    _debug OK
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
    _debug APP
    echo "$__opt$__sep$__val$__end" >> "$__conf"
  fi
  _debug "$(grep -H -n "^$__opt$__sep" $__conf)"
}

#_savedomainconf   key  value
#save to domain.conf
_savedomainconf() {
  key="$1"
  value="$2"
  if [ "$DOMAIN_CONF" ] ; then
    _setopt $DOMAIN_CONF "$key" "=" "$value"
  else
    _err "DOMAIN_CONF is empty, can not save $key=$value"
  fi
}

#_saveaccountconf  key  value
_saveaccountconf() {
  key="$1"
  value="$2"
  if [ "$ACCOUNT_CONF_PATH" ] ; then
    _setopt $ACCOUNT_CONF_PATH "$key" "=" "$value"
  else
    _err "ACCOUNT_CONF_PATH is empty, can not save $key=$value"
  fi
}

_startserver() {
  content="$1"

  nchelp="$(nc -h 2>&1)"
  
  if echo "$nchelp" | grep "\-q " >/dev/null ; then
    _NC="nc -q 1 -l"
  else
    if echo "$nchelp" | grep "GNU netcat" >/dev/null && echo "$nchelp" | grep "\-c, \-\-close" >/dev/null ; then
      _NC="nc -c -l"
    else
      _NC="nc -l"
    fi
  fi

  _debug "_NC" "$_NC"
#  while true ; do
    if [ "$DEBUG" ] ; then
      if ! echo -e -n "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC -p $Le_HTTPPort -vv ; then
        echo -e -n "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC $Le_HTTPPort -vv ;
      fi
    else
      if ! echo -e -n "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC -p $Le_HTTPPort > /dev/null 2>&1; then
        echo -e -n "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC $Le_HTTPPort > /dev/null 2>&1
      fi      
    fi
    if [ "$?" != "0" ] ; then
      _err "nc listen error."
      return 1
    fi
#  done
}

_stopserver() {
  pid="$1"

}

_initpath() {

  if [ -z "$LE_WORKING_DIR" ]; then
    LE_WORKING_DIR=$HOME/.le
  fi
  
  if [ -z "$ACCOUNT_CONF_PATH" ] ; then
    ACCOUNT_CONF_PATH="$LE_WORKING_DIR/account.conf"
  fi
  
  if [ -f "$ACCOUNT_CONF_PATH" ] ; then
    source "$ACCOUNT_CONF_PATH"
  fi

  if [ -z "$API" ] ; then
    if [ -z "$STAGE" ] ; then
      API="$DEFAULT_CA"
    else
      API="$STAGE_CA"
      _info "Using stage api:$API"
    fi  
  fi
  
  if [ -z "$ACME_DIR" ] ; then
    ACME_DIR="/home/.acme"
  fi
  
  if [ -z "$APACHE_CONF_BACKUP_DIR" ] ; then
    APACHE_CONF_BACKUP_DIR="$LE_WORKING_DIR/"
  fi
  
  domain="$1"
  if ! mkdir -p "$LE_WORKING_DIR" ; then
    _err "Can not craete working dir: $LE_WORKING_DIR"
    return 1
  fi
  
  if [ -z "$ACCOUNT_KEY_PATH" ] ; then
    ACCOUNT_KEY_PATH="$LE_WORKING_DIR/account.key"
  fi

  if [ -z "$domain" ] ; then
    return 0
  fi
  
  domainhome="$LE_WORKING_DIR/$domain"
  mkdir -p "$domainhome"

  if [ -z "$DOMAIN_PATH" ] ; then
    DOMAIN_PATH="$domainhome"
  fi
  if [ -z "$DOMAIN_CONF" ] ; then
    DOMAIN_CONF="$domainhome/$domain.conf"
  fi
  
  if [ -z "$DOMAIN_SSL_CONF" ] ; then
    DOMAIN_SSL_CONF="$domainhome/$domain.ssl.conf"
  fi
  
  if [ -z "$CSR_PATH" ] ; then
    CSR_PATH="$domainhome/$domain.csr"
  fi
  if [ -z "$CERT_KEY_PATH" ] ; then 
    CERT_KEY_PATH="$domainhome/$domain.key"
  fi
  if [ -z "$CERT_PATH" ] ; then
    CERT_PATH="$domainhome/$domain.cer"
  fi
  if [ -z "$CA_CERT_PATH" ] ; then
    CA_CERT_PATH="$domainhome/ca.cer"
  fi
  if [ -z "$CERT_FULLCHAIN_PATH" ] ; then
    CERT_FULLCHAIN_PATH="$domainhome/fullchain.cer"
  fi

}


_apachePath() {
  httpdroot="$(apachectl -V | grep HTTPD_ROOT= | cut -d = -f 2 | tr -d '"' )"
  httpdconfname="$(apachectl -V | grep SERVER_CONFIG_FILE= | cut -d = -f 2 | tr -d '"' )"
  httpdconf="$httpdroot/$httpdconfname"
  if [ ! -f $httpdconf ] ; then
    _err "Apache Config file not found" $httpdconf
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
  echo "
Alias /.well-known/acme-challenge  $ACME_DIR

<Directory $ACME_DIR >
Require all granted
</Directory>
  " >> $httpdconf
  
  if ! apachectl  -t ; then
    _err "Sorry, apache config error, please contact me."
    _restoreApache
    return 1;
  fi
  
  if [ ! -d "$ACME_DIR" ] ; then
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
  if [ -z "$__webroot" ] ; then
    _debug "no webroot specified, skip"
    return 0
  fi
  
  if [ "$2" == '1' ] ; then
    _debug "remove $__webroot/.well-known"
    rm -rf "$__webroot/.well-known"
  elif [ "$2" == '2' ] ; then
    _debug "remove $__webroot/.well-known/acme-challenge"
    rm -rf "$__webroot/.well-known/acme-challenge"
  elif [ "$2" == '3' ] ; then
    _debug "remove $__webroot/.well-known/acme-challenge/$3"
    rm -rf "$__webroot/.well-known/acme-challenge/$3"
  else
    _info "Skip for removelevel:$2"
  fi
  
  return 0

}

issue() {
  if [ -z "$2" ] ; then
    _err "Usage: le  issue  webroot|no|apache|dns   a.com  [www.a.com,b.com,c.com]|no   [key-length]|no"
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

  
  _initpath $Le_Domain
  
  if [ -f "$DOMAIN_CONF" ] ; then
    Le_NextRenewTime=$(grep "^Le_NextRenewTime=" "$DOMAIN_CONF" | cut -d '=' -f 2)
    if [ -z "$FORCE" ] && [ "$Le_NextRenewTime" ] && [ "$(date -u "+%s" )" -lt "$Le_NextRenewTime" ] ; then 
      _info "Skip, Next renewal time is: $(grep "^Le_NextRenewTimeStr" "$DOMAIN_CONF" | cut -d '=' -f 2)"
      return 2
    fi
  fi
  
  if [ "$Le_Alt" == "no" ] ; then
    Le_Alt=""
  fi
  if [ "$Le_Keylength" == "no" ] ; then
    Le_Keylength=""
  fi
  if [ "$Le_RealCertPath" == "no" ] ; then
    Le_RealCertPath=""
  fi
  if [ "$Le_RealKeyPath" == "no" ] ; then
    Le_RealKeyPath=""
  fi
  if [ "$Le_RealCACertPath" == "no" ] ; then
    Le_RealCACertPath=""
  fi
  if [ "$Le_ReloadCmd" == "no" ] ; then
    Le_ReloadCmd=""
  fi
  
  _setopt "$DOMAIN_CONF"  "Le_Domain"             "="  "$Le_Domain"
  _setopt "$DOMAIN_CONF"  "Le_Alt"                "="  "$Le_Alt"
  _setopt "$DOMAIN_CONF"  "Le_Webroot"            "="  "$Le_Webroot"
  _setopt "$DOMAIN_CONF"  "Le_Keylength"          "="  "$Le_Keylength"
  _setopt "$DOMAIN_CONF"  "Le_RealCertPath"       "="  "\"$Le_RealCertPath\""
  _setopt "$DOMAIN_CONF"  "Le_RealCACertPath"     "="  "\"$Le_RealCACertPath\""
  _setopt "$DOMAIN_CONF"  "Le_RealKeyPath"        "="  "\"$Le_RealKeyPath\""
  _setopt "$DOMAIN_CONF"  "Le_ReloadCmd"          "="  "\"$Le_ReloadCmd\""
  
  if [ "$Le_Webroot" == "no" ] ; then
    _info "Standalone mode."
    if ! command -v "nc" > /dev/null ; then
      _err "Please install netcat(nc) tools first."
      return 1
    fi
    
    if [ -z "$Le_HTTPPort" ] ; then
      Le_HTTPPort=80
    fi
    _setopt "$DOMAIN_CONF"  "Le_HTTPPort"             "="  "$Le_HTTPPort"
    
    netprc="$(_ss "$Le_HTTPPort" | grep "$Le_HTTPPort")"
    if [ "$netprc" ] ; then
      _err "$netprc"
      _err "tcp port $Le_HTTPPort is already used by $(echo "$netprc" | cut -d :  -f 4)"
      _err "Please stop it first"
      return 1
    fi
  fi
  
  if [ "$Le_Webroot" == "apache" ] ; then
    if ! _setApache ; then
      _err "set up apache error. Report error to me."
      return 1
    fi
    wellknown_path="$ACME_DIR"
  else
    usingApache=""
  fi
  
  createAccountKey $Le_Domain $Le_Keylength

  if ! _calcjwk "$ACCOUNT_KEY_PATH" ; then
    return 1
  fi
  
  accountkey_json=$(echo -n "$jwk" |  tr -d ' ' )
  thumbprint=$(echo -n "$accountkey_json" | _digest "sha256" | _urlencode)
  
  accountkeyhash="$(cat "$ACCOUNT_KEY_PATH" | _digest "sha256" )"

  if [ "$accountkeyhash" != "$ACCOUNT_KEY_HASH" ] ; then
    _info "Registering account"
    regjson='{"resource": "new-reg", "agreement": "'$AGREEMENT'"}'
    if [ "$ACCOUNT_EMAIL" ] ; then
      regjson='{"resource": "new-reg", "contact": ["mailto: '$ACCOUNT_EMAIL'"], "agreement": "'$AGREEMENT'"}'
    fi  
    _send_signed_request   "$API/acme/new-reg"  "$regjson"
    
    if [ "$code" == "" ] || [ "$code" == '201' ] ; then
      _info "Registered"
      echo $response > $LE_WORKING_DIR/account.json
    elif [ "$code" == '409' ] ; then
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

  if ! createDomainKey $Le_Domain $Le_Keylength ; then 
    _err "Create domain key error."
    return 1
  fi
  
  if ! createCSR  $Le_Domain  $Le_Alt ; then
    _err "Create CSR error."
    return 1
  fi
  
  vtype="$VTYPE_HTTP"
  if [[ "$Le_Webroot" == "dns"* ]] ; then
    vtype="$VTYPE_DNS"
  fi
  
  vlist="$Le_Vlist"
  # verify each domain
  _info "Verify each domain"
  sep='#'
  if [ -z "$vlist" ] ; then
    alldomains=$(echo "$Le_Domain,$Le_Alt" |  tr ',' ' ' )
    for d in $alldomains   
    do  
      _info "Getting token for domain" $d
      _send_signed_request "$API/acme/new-authz" "{\"resource\": \"new-authz\", \"identifier\": {\"type\": \"dns\", \"value\": \"$d\"}}"
      if [ ! -z "$code" ] && [ ! "$code" == '201' ] ; then
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

      dvlist="$d$sep$keyauthorization$sep$uri"
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

      if [ "$vtype" == "$VTYPE_DNS" ] ; then
        dnsadded='0'
        txtdomain="_acme-challenge.$d"
        _debug txtdomain "$txtdomain"
        txt="$(echo -e -n $keyauthorization | _digest "sha256" | _urlencode)"
        _debug txt "$txt"
        #dns
        #1. check use api
        d_api=""
        if [ -f "$LE_WORKING_DIR/$d/$Le_Webroot" ] ; then
          d_api="$LE_WORKING_DIR/$d/$Le_Webroot"
        elif [ -f "$LE_WORKING_DIR/$d/$Le_Webroot.sh" ] ; then
          d_api="$LE_WORKING_DIR/$d/$Le_Webroot.sh"
        elif [ -f "$LE_WORKING_DIR/$Le_Webroot" ] ; then
          d_api="$LE_WORKING_DIR/$Le_Webroot"
        elif [ -f "$LE_WORKING_DIR/$Le_Webroot.sh" ] ; then
          d_api="$LE_WORKING_DIR/$Le_Webroot.sh"
        elif [ -f "$LE_WORKING_DIR/dnsapi/$Le_Webroot" ] ; then
          d_api="$LE_WORKING_DIR/dnsapi/$Le_Webroot"
        elif [ -f "$LE_WORKING_DIR/dnsapi/$Le_Webroot.sh" ] ; then
          d_api="$LE_WORKING_DIR/dnsapi/$Le_Webroot.sh"
        fi
        _debug d_api "$d_api"
        
        if [ "$d_api" ]; then
          _info "Found domain api file: $d_api"
        else
          _err "Add the following TXT record:"
          _err "Domain: $txtdomain"
          _err "TXT value: $txt"
          _err "Please be aware that you prepend _acme-challenge. before your domain"
          _err "so the resulting subdomain will be: $txtdomain"
          continue
        fi

        if ! source $d_api ; then
          _err "Load file $d_api error. Please check your api file and try again."
          return 1
        fi
        
        addcommand="$Le_Webroot-add"
        if ! command -v $addcommand ; then 
          _err "It seems that your api file is not correct, it must have a function named: $addcommand"
          return 1
        fi
        
        if ! $addcommand $txtdomain $txt ; then
          _err "Error add txt for domain:$txtdomain"
          return 1
        fi
        dnsadded='1'
      fi
    done

    if [ "$dnsadded" == '0' ] ; then
      _setopt "$DOMAIN_CONF"  "Le_Vlist" "=" "\"$vlist\""
      _debug "Dns record not added yet, so, save to $DOMAIN_CONF and exit."
      _err "Please add the TXT records to the domains, and retry again."
      return 1
    fi
    
  fi
  
  if [ "$dnsadded" == '1' ] ; then
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
    _info "Verifying:$d"
    _debug "d" "$d"
    _debug "keyauthorization" "$keyauthorization"
    _debug "uri" "$uri"
    removelevel=""
    token=""
    if [ "$vtype" == "$VTYPE_HTTP" ] ; then
      if [ "$Le_Webroot" == "no" ] ; then
        _info "Standalone mode server"
        _startserver "$keyauthorization" &
        serverproc="$!"
        sleep 2
        _debug serverproc $serverproc
      else
        if [ -z "$wellknown_path" ] ; then
          wellknown_path="$Le_Webroot/.well-known/acme-challenge"
        fi
        _debug wellknown_path "$wellknown_path"
        
        if [ ! -d "$Le_Webroot/.well-known" ] ; then 
          removelevel='1'
        elif [ ! -d "$Le_Webroot/.well-known/acme-challenge" ] ; then 
          removelevel='2'
        else
          removelevel='3'
        fi
        
        token="$(echo -e -n "$keyauthorization" | cut -d '.' -f 1)"
        _debug "writing token:$token to $wellknown_path/$token"

        mkdir -p "$wellknown_path"
        echo -n "$keyauthorization" > "$wellknown_path/$token"

        webroot_owner=$(_stat $Le_Webroot)
        _debug "Changing owner/group of .well-known to $webroot_owner"
        chown -R $webroot_owner "$Le_Webroot/.well-known"
        
      fi
    fi
    
    _send_signed_request $uri "{\"resource\": \"challenge\", \"keyAuthorization\": \"$keyauthorization\"}"
    
    if [ ! -z "$code" ] && [ ! "$code" == '202' ] ; then
      _err "$d:Challenge error: $resource"
      _clearupwebbroot "$Le_Webroot" "$removelevel" "$token"
      _clearup
      return 1
    fi
    
    while [ "1" ] ; do
      _debug "sleep 5 secs to verify"
      sleep 5
      _debug "checking"
      
      if ! _get $uri ; then
        _err "$d:Verify error:$resource"
        _clearupwebbroot "$Le_Webroot" "$removelevel" "$token"
        _clearup
        return 1
      fi
      
      status=$(echo $response | egrep -o  '"status":"[^"]+"' | cut -d : -f 2 | tr -d '"')
      if [ "$status" == "valid" ] ; then
        _info "Success"
        _stopserver $serverproc
        serverproc=""
        _clearupwebbroot "$Le_Webroot" "$removelevel" "$token"
        break;
      fi
      
      if [ "$status" == "invalid" ] ; then
         error=$(echo $response | egrep -o '"error":{[^}]*}' | grep -o '"detail":"[^"]*"' | cut -d '"' -f 4)
        _err "$d:Verify error:$error"
        _clearupwebbroot "$Le_Webroot" "$removelevel" "$token"
        _clearup
        return 1;
      fi
      
      if [ "$status" == "pending" ] ; then
        _info "Pending"
      else
        _err "$d:Verify error:$response" 
        _clearupwebbroot "$Le_Webroot" "$removelevel" "$token"
        _clearup
        return 1
      fi
      
    done
    
  done

  _clearup
  _info "Verify finished, start to sign."
  der="$(_getfile "$CSR_PATH" "$BEGIN_CSR" "$END_CSR" | tr -d "\r\n" | _urlencode)"
  _send_signed_request "$API/acme/new-cert" "{\"resource\": \"new-cert\", \"csr\": \"$der\"}" "needbase64"
  
  
  Le_LinkCert="$(grep -i -o '^Location.*$' $CURL_HEADER | tr -d "\r\n" | cut -d " " -f 2)"
  _setopt "$DOMAIN_CONF"  "Le_LinkCert"           "="  "$Le_LinkCert"

  if [ "$Le_LinkCert" ] ; then
    echo "$BEGIN_CERT" > "$CERT_PATH"
    curl --silent "$Le_LinkCert" | _base64 "multiline"  >> "$CERT_PATH"
    echo "$END_CERT"  >> "$CERT_PATH"
    _info "Cert success."
    cat "$CERT_PATH"
    
    _info "Your cert is in $CERT_PATH"
    cp "$CERT_PATH" "$CERT_FULLCHAIN_PATH"
  fi
  

  if [ -z "$Le_LinkCert" ] ; then
    response="$(echo $response | _dbase64 "multiline" )"
    _err "Sign failed: $(echo "$response" | grep -o  '"detail":"[^"]*"')"
    return 1
  fi
  
  _setopt "$DOMAIN_CONF"  'Le_Vlist' '=' "\"\""
  
  Le_LinkIssuer=$(grep -i '^Link' $CURL_HEADER | cut -d " " -f 2| cut -d ';' -f 1 | tr -d '<>' )
  _setopt "$DOMAIN_CONF"  "Le_LinkIssuer"         "="  "$Le_LinkIssuer"
  
  if [ "$Le_LinkIssuer" ] ; then
    echo "$BEGIN_CERT" > "$CA_CERT_PATH"
    curl --silent "$Le_LinkIssuer" | _base64 "multiline"  >> "$CA_CERT_PATH"
    echo "$END_CERT"  >> "$CA_CERT_PATH"
    _info "The intermediate CA cert is in $CA_CERT_PATH"
    cat "$CA_CERT_PATH" >> "$CERT_FULLCHAIN_PATH"
    _info "And the full chain certs is there: $CERT_FULLCHAIN_PATH"
  fi
  
  Le_CertCreateTime=$(date -u "+%s")
  _setopt "$DOMAIN_CONF"  "Le_CertCreateTime"     "="  "$Le_CertCreateTime"
  
  Le_CertCreateTimeStr=$(date -u )
  _setopt "$DOMAIN_CONF"  "Le_CertCreateTimeStr"  "="  "\"$Le_CertCreateTimeStr\""
  
  if [ ! "$Le_RenewalDays" ] ; then
    Le_RenewalDays=80
  fi
  
  _setopt "$DOMAIN_CONF"  "Le_RenewalDays"      "="  "$Le_RenewalDays"
  
  let "Le_NextRenewTime=Le_CertCreateTime+Le_RenewalDays*24*60*60"
  _setopt "$DOMAIN_CONF"  "Le_NextRenewTime"      "="  "$Le_NextRenewTime"
  
  Le_NextRenewTimeStr=$( _time2str $Le_NextRenewTime )
  _setopt "$DOMAIN_CONF"  "Le_NextRenewTimeStr"      "="  "\"$Le_NextRenewTimeStr\""


  installcert $Le_Domain  "$Le_RealCertPath" "$Le_RealKeyPath" "$Le_RealCACertPath" "$Le_ReloadCmd"

}

renew() {
  Le_Domain="$1"
  if [ -z "$Le_Domain" ] ; then
    _err "Usage: $0  domain.com"
    return 1
  fi

  _initpath $Le_Domain

  if [ ! -f "$DOMAIN_CONF" ] ; then
    _info "$Le_Domain is not a issued domain, skip."
    return 0;
  fi
  
  source "$DOMAIN_CONF"
  if [ -z "$FORCE" ] && [ "$Le_NextRenewTime" ] && [ "$(date -u "+%s" )" -lt "$Le_NextRenewTime" ] ; then 
    _info "Skip, Next renewal time is: $Le_NextRenewTimeStr"
    return 2
  fi
  
  IS_RENEW="1"
  issue "$Le_Webroot" "$Le_Domain" "$Le_Alt" "$Le_Keylength" "$Le_RealCertPath" "$Le_RealKeyPath" "$Le_RealCACertPath" "$Le_ReloadCmd"
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
    Le_Alt=""
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
    
    DOMAIN_PATH=""
    DOMAIN_CONF=""
    DOMAIN_SSL_CONF=""
    CSR_PATH=""
    CERT_KEY_PATH=""
    CERT_PATH=""
    CA_CERT_PATH=""
    CERT_FULLCHAIN_PATH=""
    ACCOUNT_KEY_PATH=""
    
    wellknown_path=""
    
    renew "$d"  
  done
  
}

installcert() {
  Le_Domain="$1"
  if [ -z "$Le_Domain" ] ; then
    _err "Usage: $0  domain.com  [cert-file-path]|no  [key-file-path]|no  [ca-cert-file-path]|no   [reloadCmd]|no"
    return 1
  fi

  Le_RealCertPath="$2"
  Le_RealKeyPath="$3"
  Le_RealCACertPath="$4"
  Le_ReloadCmd="$5"

  _initpath $Le_Domain

  _setopt "$DOMAIN_CONF"  "Le_RealCertPath"       "="  "\"$Le_RealCertPath\""
  _setopt "$DOMAIN_CONF"  "Le_RealCACertPath"     "="  "\"$Le_RealCACertPath\""
  _setopt "$DOMAIN_CONF"  "Le_RealKeyPath"        "="  "\"$Le_RealKeyPath\""
  _setopt "$DOMAIN_CONF"  "Le_ReloadCmd"          "="  "\"$Le_ReloadCmd\""
  
  if [ "$Le_RealCertPath" ] ; then
    if [ -f "$Le_RealCertPath" ] ; then
      cp -p "$Le_RealCertPath" "$Le_RealCertPath".bak
    fi
    cat "$CERT_PATH" > "$Le_RealCertPath"
  fi
  
  if [ "$Le_RealCACertPath" ] ; then
    if [ -f "$Le_RealCACertPath" ] ; then
      cp -p "$Le_RealCACertPath" "$Le_RealCACertPath".bak
    fi
    if [ "$Le_RealCACertPath" == "$Le_RealCertPath" ] ; then
      echo "" >> "$Le_RealCACertPath"
      cat "$CA_CERT_PATH" >> "$Le_RealCACertPath"
    else
      cat "$CA_CERT_PATH" > "$Le_RealCACertPath"
    fi
  fi


  if [ "$Le_RealKeyPath" ] ; then
    if [ -f "$Le_RealKeyPath" ] ; then
      cp -p "$Le_RealKeyPath" "$Le_RealKeyPath".bak
    fi
    cat "$CERT_KEY_PATH" > "$Le_RealKeyPath"
  fi

  if [ "$Le_ReloadCmd" ] ; then
    _info "Run Le_ReloadCmd: $Le_ReloadCmd"
    (cd "$DOMAIN_PATH" && eval "$Le_ReloadCmd")
  fi

}

installcronjob() {
  _initpath
  _info "Installing cron job"
  if ! crontab -l | grep 'le.sh cron' ; then 
    if [ -f "$LE_WORKING_DIR/le.sh" ] ; then
      lesh="\"$LE_WORKING_DIR\"/le.sh"
    else
      _err "Can not install cronjob, le.sh not found."
      return 1
    fi
    crontab -l | { cat; echo "0 0 * * * LE_WORKING_DIR=\"$LE_WORKING_DIR\" $lesh cron > /dev/null"; } | crontab -
  fi
  if [ "$?" != "0" ] ; then
    _err "Install cron job failed. You need to manually renew your certs."
    _err "Or you can add cronjob by yourself:"
    _err "LE_WORKING_DIR=\"$LE_WORKING_DIR\" $lesh cron > /dev/null"
    return 1
  fi
}

uninstallcronjob() {
  _info "Removing cron job"
  cr="$(crontab -l | grep 'le.sh cron')"
  if [ "$cr" ] ; then 
    crontab -l | sed "/le.sh cron/d" | crontab -
    LE_WORKING_DIR="$(echo "$cr" | cut -d ' ' -f 6 | cut -d '=' -f 2 | tr -d '"')"
    _info LE_WORKING_DIR "$LE_WORKING_DIR"
  fi 
  _initpath
  
}


# Detect profile file if not specified as environment variable
_detect_profile() {
  if [ -n "$PROFILE" -a -f "$PROFILE" ]; then
    echo "$PROFILE"
    return
  fi

  local DETECTED_PROFILE
  DETECTED_PROFILE=''
  local SHELLTYPE
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

  if [ ! -z "$DETECTED_PROFILE" ]; then
    echo "$DETECTED_PROFILE"
  fi
}

_initconf() {
  _initpath
  if [ ! -f "$ACCOUNT_CONF_PATH" ] ; then
    echo "#Account configurations:
#Here are the supported macros, uncomment them to make them take effect.
#ACCOUNT_EMAIL=aaa@aaa.com  # the account email used to register account.
#ACCOUNT_KEY_PATH=\"/path/to/account.key\"

#STAGE=1 # Use the staging api
#FORCE=1 # Force to issue cert
#DEBUG=1 # Debug mode

#ACCOUNT_KEY_HASH=account key hash

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

install() {
  if ! _initpath ; then
    _err "Install failed."
    return 1
  fi
  
  #check if there is sudo installed, AND if the current user is a sudoer.
  if command -v sudo > /dev/null ; then
    if [ "$(sudo -n uptime 2>&1|grep "load"|wc -l)" != "0" ] ; then
      SUDO=sudo
    fi
  fi
  
  if command -v yum > /dev/null ; then
   YUM="1"
   INSTALL="$SUDO yum install -y "
  elif command -v apt-get > /dev/null ; then
   INSTALL="$SUDO apt-get install -y "
  fi

  if ! command -v "curl" > /dev/null ; then
    _err "Please install curl first."
    _err "$INSTALL curl"
    return 1
  fi
  
  if ! command -v "crontab" > /dev/null ; then
    _err "Please install crontab first."
    if [ "$YUM" ] ; then
      _err "$INSTALL crontabs"
    else
      _err "$INSTALL crontab"
    fi
    return 1
  fi
  
  if ! command -v "openssl" > /dev/null ; then
    _err "Please install openssl first."
    _err "$INSTALL openssl"
    return 1
  fi

  _info "Installing to $LE_WORKING_DIR"

  cp le.sh "$LE_WORKING_DIR/" && chmod +x "$LE_WORKING_DIR/le.sh"

  if [ "$?" != "0" ] ; then
    _err "Install failed, can not copy le.sh"
    return 1
  fi

  _info "Installed to $LE_WORKING_DIR/le.sh"

  _profile="$(_detect_profile)"
  if [ "$_profile" ] ; then
    _debug "Found profile: $_profile"
    
    echo "LE_WORKING_DIR=$LE_WORKING_DIR
alias le=\"$LE_WORKING_DIR/le.sh\"
alias le.sh=\"$LE_WORKING_DIR/le.sh\"
    " > "$LE_WORKING_DIR/le.env"
    echo "" >> "$_profile"
    _setopt "$_profile" "source \"$LE_WORKING_DIR/le.env\""
    _info "OK, Close and reopen your terminal to start using le"
  else
    _info "No profile is found, you will need to go into $LE_WORKING_DIR to use le.sh"
  fi

  mkdir -p $LE_WORKING_DIR/dnsapi
  cp  dnsapi/* $LE_WORKING_DIR/dnsapi/
  
  #to keep compatible mv the .acc file to .key file 
  if [ -f "$LE_WORKING_DIR/account.acc" ] ; then
    mv "$LE_WORKING_DIR/account.acc" "$LE_WORKING_DIR/account.key"
  fi
  
  installcronjob
  
  if [ ! -f "$ACCOUNT_CONF_PATH" ] ; then
    _initconf
  fi
  _info OK
}

uninstall() {
  uninstallcronjob
  _initpath

  _profile="$(_detect_profile)"
  if [ "$_profile" ] ; then
    text="$(cat $_profile)"
    echo "$text" | sed "s|^source.*le.env.*$||" > "$_profile"
  fi

  rm -f $LE_WORKING_DIR/le.sh
  _info "The keys and certs are in $LE_WORKING_DIR, you can remove them by yourself."

}

cron() {
  renewAll
}

version() {
  _info "$PROJECT"
  _info "v$VER"
}

showhelp() {
  version
  echo "Usage: le.sh  [command] ...[args]....
Avalible commands:

install:
  Install le.sh to your system.
issue:
  Issue a cert.
installcert:
  Install the issued cert to apache/nginx or any other server.
renew:
  Renew a cert.
renewAll:
  Renew all the certs.
uninstall:
  Uninstall le.sh, and uninstall the cron job.
version:
  Show version info.
installcronjob:
  Install the cron job to renew certs, you don't need to call this. The 'install' command can automatically install the cron job.
uninstallcronjob:
  Uninstall the cron job. The 'uninstall' command can do this automatically.
createAccountKey:
  Create an account private key, professional use.
createDomainKey:
  Create an domain private key, professional use.
createCSR:
  Create CSR , professional use.
  "
}


if [ -z "$1" ] ; then
  showhelp
else
  "$@"
fi
