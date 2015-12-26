#!/bin/bash


WORKING_DIR=~/.le

ACCOUNT_KEY_PATH=$WORKING_DIR/account.acc

CERT_KEY_PATH=$WORKING_DIR/domain.key

CSR_PATH=$WORKING_DIR/domain.csr

CERT_PATH=$WORKING_DIR/domain.cer

DOMAIN_CONF=$WORKING_DIR/domain.conf

CURL_HEADER=""

HEADER=""
HEADERPLACE=""

ACCOUNT_EMAIL=""
DEFAULT_CA="https://acme-v01.api.letsencrypt.org"

API=$DEFAULT_CA

DEBUG=

_debug() {
  if ! [ "$DEBUG" ] ; then
    return
  fi
  
  if [ -z "$2" ] ; then
    echo $1
  else
    echo $1:$2
  fi
}

_info() {
  if [ -z "$2" ] ; then
    echo $1
  else
    echo $1:$2
  fi
}

#domain [2048]  
createAccountKey() {
  if [ -z "$1" ] ; then
    echo Usage: $0 account-domain  [2048]
    return
  fi
  
  account=$1
  length=$2
  if [ -z "$2" ] ; then
    echo Use default length 2048
    length=2048
  fi
  
  mkdir -p $WORKING_DIR
  ACCOUNT_KEY_PATH=$WORKING_DIR/account.acc
  
  if [ -f "$ACCOUNT_KEY_PATH" ] ; then
    echo account key exists, skip
    return
  else
    #generate account key
    openssl genrsa $length > $ACCOUNT_KEY_PATH
  fi

}

#domain length
createDomainKey() {
  if [ -z "$1" ] ; then
    echo Usage: $0 domain  [2048]
    return
  fi
  
  domain=$1
  length=$2
  if [ -z "$2" ] ; then
    echo Use default length 2048
    length=2048
  fi

  mkdir -p $WORKING_DIR/$domain
  CERT_KEY_PATH=$WORKING_DIR/$domain/$domain.key
  
  if [ -f "$CERT_KEY_PATH" ] ; then 
    echo domain key exists, skip
  else
    #generate account key
    openssl genrsa $length > $CERT_KEY_PATH
  fi

}

# domain  domainlist
createCSR() {
  if [ -z "$1" ] ; then
    echo Usage: $0 domain  [domainlist]
    return
  fi
  domain=$1
  _initpath $domain
  
  domainlist=$2
  
  if [ -f $CSR_PATH ] ; then
    echo CSR exists, skip
    return
  fi
  
  if [ -z "$domainlist" ] ; then
    #single domain
    echo single domain
    openssl req -new -sha256 -key $CERT_KEY_PATH -subj "/CN=$domain" > $CSR_PATH
  else
    alt=DNS:$(echo $domainlist | sed "s/,/,DNS:/g")
    #multi 
    echo multi domain $alt
    openssl req -new -sha256 -key $CERT_KEY_PATH -subj "/CN=$domain" -reqexts SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[SAN]\nsubjectAltName=$alt")) -out $CSR_PATH
  fi

}

_b64() {
  while read __line; do
    __n=$__n$__line
  done;
  __n=$(echo $__n | sed "s|/|_|g")
  __n=$(echo $__n | sed "s| ||g")
  __n=$(echo $__n | sed "s|+|-|g")
  __n=$(echo $__n | sed "s|=||g")
  echo $__n
}

_send_signed_request() {
  url=$1
  payload=$2
  
  needbas64="$3"
  
  _debug url $url
  _debug payload "$payload"
  
  CURL_HEADER="$WORKING_DIR/curl.header"
  dp="$WORKING_DIR/curl.dump"
  CURL="curl --silent --dump-header $CURL_HEADER "
  if [ "DEBUG" ] ; then
    CURL="$CURL --trace-ascii $dp "
  fi
  payload64=$(echo -n $payload | base64 | _b64)
  _debug payload64 $payload64
  
  nonceurl="$API/directory"
  nonce=$($CURL -I $nonceurl | grep "^Replay-Nonce:" | sed s/\\r//|sed s/\\n//| cut -d ' ' -f 2)

  _debug nonce $nonce
  
  protected=$(echo -n "$HEADERPLACE" | sed "s/NONCE/$nonce/" )
  _debug protected "$protected"
  
  protected64=$( echo -n $protected | base64 | _b64)
  _debug protected64 "$protected64"
  
  sig=$(echo -n "$protected64.$payload64" |  openssl   dgst   -sha256  -sign  $ACCOUNT_KEY_PATH | base64| _b64)
  _debug sig "$sig"
  
  body="{\"header\": $HEADER, \"protected\": \"$protected64\", \"payload\": \"$payload64\", \"signature\": \"$sig\"}"
  _debug body "$body"
  
  
  if [ "$needbas64" ] ; then
    response=$($CURL -X POST --data "$body" $url | base64)
  else
    response=$($CURL -X POST --data "$body" $url)
  fi
  responseHeaders="$(cat $CURL_HEADER)"
  
  _debug responseHeaders "$responseHeaders"
  _debug response  "$response"
  code=$(grep ^HTTP $CURL_HEADER | tail -1 | cut -d " " -f 2)
  _debug code $code

}

_get() {
  url="$1"
  _debug url $url
  response=$(curl --silent $url)
  ret=$?
  _debug response  "$response"
  code=$(echo $response | grep -o '"status":[0-9]\+' | cut -d : -f 2)
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
    echo usage: $0  '"file"  "opt"  "="  "value" [";"]'
    return
  fi
  if [ ! -f $__conf ] ; then
    touch $__conf
  fi
  if grep -H -n "^$__opt$__sep" $__conf ; then
    _debug OK
    sed -i "s|^$__opt$__sep.*$|$__opt$__sep$__val$__end|" $__conf 
  else
    _debug APP
    echo "$__opt$__sep$__val$__end" >> $__conf
  fi
  _debug "$(grep -H -n "^$__opt$__sep" $__conf)"
}

_initpath() {
  WORKING_DIR=~/.le
  domain=$1
  mkdir -p $WORKING_DIR
  ACCOUNT_KEY_PATH=$WORKING_DIR/account.acc
  
  if [ -z "$domain" ] ; then
    return 0
  fi
  
  mkdir -p $WORKING_DIR/$domain
  

  CSR_PATH=$WORKING_DIR/$domain/$domain.csr

  CERT_KEY_PATH=$WORKING_DIR/$domain/$domain.key

  CERT_PATH=$WORKING_DIR/$domain/$domain.cer

}

#issue webroot a.com [www.a.com,b.com,c.com]  [key-length] [cert-file-path] [key-file-path] [reloadCmd]
issue() {
  if [ -z "$1" ] ; then
    echo "Usage: $0 webroot a.com [www.a.com,b.com,c.com]  [key-length] [cert-file-path] [key-file-path] [reloadCmd]"
    return 1
  fi
  Le_Webroot=$1
  Le_Domain=$2
  Le_Alt=$3
  Le_Keylength=$4
  
  if [ -z "$Le_Domain" ] ; then 
    Le_Domain="$1"
  fi
  
  _initpath $Le_Domain
  
  DOMAIN_CONF=$WORKING_DIR/$Le_Domain/$Le_Domain.conf
  if [ -f "$DOMAIN_CONF" ] ; then
    source "$DOMAIN_CONF"
    if [ "$(date -u "+%s" )" -lt "$Le_NextRenewTime" ] ; then 
      _info "Skip, Next renwal time is: $Le_NextRenewTimeStr"
      return 2
    fi
  fi
  
  if [ -z "$Le_Webroot" ] ; then
    echo Usage: $0 webroot a.com [b.com,c.com]  [key-length]
    return 1
  fi

  createAccountKey $Le_Domain $Le_Keylength
  
  createDomainKey $Le_Domain $Le_Keylength
  
  createCSR  $Le_Domain  $Le_Alt

  pub_exp=$(openssl rsa -in $ACCOUNT_KEY_PATH  -noout -text | grep "^publicExponent:"| cut -d '(' -f 2 | cut -d 'x' -f 2 | cut -d ')' -f 1)
  if [ "${#pub_exp}" == "5" ] ; then
    pub_exp=0$pub_exp
  fi
  _debug pub_exp "$pub_exp"
  
  e=$(echo $pub_exp | xxd -r -p | base64)
  _debug e "$e"
  
  modulus=$(openssl rsa -in $ACCOUNT_KEY_PATH -modulus -noout | cut -d '=' -f 2 )
  n=$(echo $modulus| xxd -r -p | base64 | _b64 )

  jwk='{"e": "'$e'", "kty": "RSA", "n": "'$n'"}'
  
  HEADER='{"alg": "RS256", "jwk": '$jwk'}'
  HEADERPLACE='{"nonce": "NONCE", "alg": "RS256", "jwk": '$jwk'}'
  _debug HEADER "$HEADER"
  
  accountkey_json=$(echo -n "$jwk" | sed "s/ //g")
  thumbprint=$(echo -n "$accountkey_json" | sha256sum | xxd -r -p | base64 | _b64)
  
  
  _info "Registering account"
  regjson='{"resource": "new-reg", "agreement": "https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf"}'
  if [ "$ACCOUNT_EMAIL" ] ; then
    regjson='{"resource": "new-reg", "contact": ["mailto: '$ACCOUNT_EMAIL'"], "agreement": "https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf"}'
  fi  
  _send_signed_request   "$API/acme/new-reg"  "$regjson"
  
  if [ "$code" == "" ] || [ "$code" == '201' ] ; then
    _info "Registered"
    echo $response > $WORKING_DIR/account.json
  elif [ "$code" == '409' ] ; then
    _info "Already registered"
  else
    _info "Register account Error."
    return 1
  fi
  
  # verify each domain
  _info "Verify each domain"
  
  alldomains=$(echo "$Le_Domain,$Le_Alt" | sed "s/,/ /g")
  for d in $alldomains   
  do  
    _info "Verifing domain $d"
    
    _send_signed_request "$API/acme/new-authz" "{\"resource\": \"new-authz\", \"identifier\": {\"type\": \"dns\", \"value\": \"$d\"}}"
 
    if [ ! -z "$code" ] && [ ! "$code" == '201' ] ; then
      _info "new-authz error: $d"
      return 1
    fi
    
    http01=$(echo $response | egrep -o  '{[^{]*"type":"http-01"[^}]*')
    _debug http01 "$http01"
    
    token=$(echo "$http01" | sed 's/,/\n'/g| grep '"token":'| cut -d : -f 2|sed 's/"//g')
    _debug token $token
    
    uri=$(echo "$http01" | sed 's/,/\n'/g| grep '"uri":'| cut -d : -f 2,3|sed 's/"//g')
    _debug uri $uri
    
    keyauthorization="$token.$thumbprint"
    _debug keyauthorization "$keyauthorization"
    
    wellknown_path="$Le_Webroot/.well-known/acme-challenge"
    _debug wellknown_path "$wellknown_path"
    
    mkdir -p "$wellknown_path"
    wellknown_path="$wellknown_path/$token"
    echo -n "$keyauthorization" > $wellknown_path
    
    wellknown_url="http://$d/.well-known/acme-challenge/$token"
    _debug wellknown_url "$wellknown_url"
    
    _debug challenge "$challenge"
    _send_signed_request $uri "{\"resource\": \"challenge\", \"keyAuthorization\": \"$keyauthorization\"}"
    
    if [ ! -z "$code" ] && [ ! "$code" == '202' ] ; then
      _info "challenge error: $d"
      return 1
    fi
    
    while [ "1" ] ; do
      _debug "sleep 5 secs to verify"
      sleep 5
      _debug "checking"
      
      if ! _get $uri ; then
        _info "Verify error:$d"
        return 1
      fi
      
      status=$(echo $response | egrep -o  '"status":"[^"]+"' | cut -d : -f 2 | sed 's/"//g')
      if [ "$status" == "valid" ] ; then
        _info "Verify success:$d"
        break;
      fi
      
      if [ "$status" == "invalid" ] ; then
         error=$(echo $response | egrep -o '"error":{[^}]*}' | grep -o '"detail":"[^"]*"' | cut -d '"' -f 4)
        _info "Verify error:$d"
        _debug $error
        return 1;
      fi
      
      if [ "$status" == "pending" ] ; then
        _info "Verify pending:$d"
      else
        _info "Verify error:$d" 
        return 1
      fi
      
    done    
  done 
  
  _info "Verify finished, start to sign."
  der=$(openssl req  -in $CSR_PATH -outform DER | base64 | _b64)
  _send_signed_request "$API/acme/new-cert" "{\"resource\": \"new-cert\", \"csr\": \"$der\"}" "needbas64"
  
  echo -----BEGIN CERTIFICATE----- > $CERT_PATH
  echo $response | sed "s/ /\n/g" >> $CERT_PATH
  echo -----END CERTIFICATE-----  >> $CERT_PATH
  _info "Cert success."
  cat $CERT_PATH
  
  _info "Your cert is in $CERT_PATH"
  
  _setopt $DOMAIN_CONF  "Le_Domain"             "="  "$Le_Domain"
  _setopt $DOMAIN_CONF  "Le_Alt"                "="  "$Le_Alt"
  _setopt $DOMAIN_CONF  "Le_Webroot"            "="  "$Le_Webroot"
  _setopt $DOMAIN_CONF  "Le_Keylength"          "="  "$Le_Keylength"
  
  
  
  Le_LinkIssuer=$(grep -i '^Link' $CURL_HEADER | cut -d " " -f 2| cut -d ';' -f 1 | sed 's/<//g' | sed 's/>//g')
  _setopt $DOMAIN_CONF  "Le_LinkIssuer"         "="  "$Le_LinkIssuer"
  
  Le_LinkCert=$(grep -i '^Location' $CURL_HEADER | cut -d " " -f 2)
  _setopt $DOMAIN_CONF  "Le_LinkCert"           "="  "$Le_LinkCert"
  
  Le_CertCreateTime=$(date -u "+%s")
  _setopt $DOMAIN_CONF  "Le_CertCreateTime"     "="  "$Le_CertCreateTime"
  
  Le_CertCreateTimeStr=$(date -u "+%Y-%m-%d %H:%M:%S UTC")
  _setopt $DOMAIN_CONF  "Le_CertCreateTimeStr"  "="  "\"$Le_CertCreateTimeStr\""
  
  if [ ! "$Le_RenewalDays" ] ; then
    Le_RenewalDays=50
  fi
  
  _setopt $DOMAIN_CONF  "Le_RenewalDays"      "="  "$Le_RenewalDays"
  
  Le_NextRenewTime=$(date -u -d "+$Le_RenewalDays day" "+%s")
  _setopt $DOMAIN_CONF  "Le_NextRenewTime"      "="  "$Le_NextRenewTime"
  
  Le_NextRenewTimeStr=$(date -u -d "+$Le_RenewalDays day" "+%Y-%m-%d %H:%M:%S UTC")
  _setopt $DOMAIN_CONF  "Le_NextRenewTimeStr"      "="  "\"$Le_NextRenewTimeStr\""
    
  _setopt $DOMAIN_CONF  "Le_RealCertPath"      "="  "\"$Le_RealCertPath\""
  if [ "$Le_RealCertPath" ] ; then
    if [ -f "$Le_RealCertPath" ] ; then
      rm -f $Le_RealCertPath
    fi
    ln -s $CERT_PATH $Le_RealCertPath
    
  fi
  
  _setopt $DOMAIN_CONF  "Le_RealKeyPath"       "="  "\"$Le_RealKeyPath\""
    if [ "$Le_RealKeyPath" ] ; then
    if [ -f "$Le_RealKeyPath" ] ; then
      rm -f $Le_RealKeyPath
    fi
    ln -s $CERT_KEY_PATH $Le_RealKeyPath
    
  fi
  _setopt $DOMAIN_CONF  "Le_ReloadCmd"         "="  "\"$Le_ReloadCmd\""
  
  if [ "$Le_ReloadCmd" ] ; then
    _info "Run Le_ReloadCmd: $Le_ReloadCmd"
    $Le_ReloadCmd
  fi
  
}



renew() {
  Le_Domain="$1"
  if [ -z "$Le_Domain" ] ; then
    echo Usage: $0  domain.com
    return 1
  fi
  
  DOMAIN_CONF=$WORKING_DIR/$Le_Domain/$Le_Domain.conf
  if [ -f "$DOMAIN_CONF" ] ; then
    source "$DOMAIN_CONF"
    if [ "$(date -u "+%s" )" -lt "$Le_NextRenewTime" ] ; then 
      _info "Skip, Next renwal time is: $Le_NextRenewTimeStr"
      return 2
    fi
  fi
  
  if [ -z "$Le_Webroot" ] ; then
    echo Le_Webroot can not found, please remove the conf file and issue a new cert
    return 1
  fi
  
  issue $Le_Domain

}

renewAll() {
  _info "renewAll"
  for d in $(ls -F $WORKING_DIR | grep  '/$') ; do
    d=$(echo $d | cut -d '/' -f 1)
    _info "renew $d"
    renew "$d"  
  done
  
}

install() {
  _initpath
  if ! command -v "curl" ; then
    _info "Please install curl first."
    _info "sudo apt-get install curl"
    return 1
  fi
  _info "Installing to $WORKING_DIR"
  
  mkdir -p $WORKING_DIR/
  cp  le.sh $WORKING_DIR/
  chmod +x $WORKING_DIR/le.sh
  
  if [ ! -f /bin/le.sh ] ; then
    ln -s $WORKING_DIR/le.sh /bin/le.sh
    ln -s $WORKING_DIR/le.sh /bin/le
  fi
  
  _info "Installing cron job"
  if ! crontab -l | grep 'le.sh renewAll' ; then 
    crontab -l | { cat; echo "0 0 * * * le.sh renewAll"; } | crontab -
    service cron restart
  fi  
  
  
  _info OK
}

uninstall() {
  _initpath
  _info "Removing cron job"
  crontab -l | sed "/le.sh renewAll/d" | crontab -
  
  _info "Removing /bin/le.sh"
  rm -f /bin/le
  rm -f /bin/le.sh
  
  _info "The keys and certs are in $WORKING_DIR, you can remove them by yourself."

}


showhelp() {
  echo "Usage: issue|renew|renewAll|createAccountKey|createDomainKey|createCSR|install|uninstall"

}


if [ -z "$1" ] ; then
  showhelp
fi



$1 $2 $3 $4 $5 $6 $7 $8




