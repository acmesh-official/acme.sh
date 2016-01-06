#!/bin/bash



DEFAULT_CA="https://acme-v01.api.letsencrypt.org"
DEFAULT_AGREEMENT="https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf"

API="$DEFAULT_CA"
AGREEMENT="$DEFAULT_AGREEMENT"

_debug() {

  if [ -z "$DEBUG" ] ; then
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

_err() {
  if [ -z "$2" ] ; then
    echo "$1" >&2
  else
    echo "$1:$2" >&2
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
    _info "Use default length 2048"
    length=2048
  fi
  _initpath
  
  if [ -f "$ACCOUNT_KEY_PATH" ] ; then
    _info "Account key exists, skip"
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
    _info "Use default length 2048"
    length=2048
  fi
  _initpath $domain
  mkdir -p $WORKING_DIR/$domain
  CERT_KEY_PATH=$WORKING_DIR/$domain/$domain.key
  
  if [ -f "$CERT_KEY_PATH" ] ; then 
    _info "Domain key exists, skip"
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
    _info "CSR exists, skip"
    return
  fi
  
  if [ -z "$domainlist" ] ; then
    #single domain
    _info "Single domain" $domain
    openssl req -new -sha256 -key $CERT_KEY_PATH -subj "/CN=$domain" > $CSR_PATH
  else
    alt=DNS:$(echo $domainlist | sed "s/,/,DNS:/g")
    #multi 
    _info "Multi domain" $alt
    openssl req -new -sha256 -key $CERT_KEY_PATH -subj "/CN=$domain" -reqexts SAN -config <(printf "[ req_distinguished_name ]\n[ req ]\ndistinguished_name = req_distinguished_name\n[SAN]\nsubjectAltName=$alt") -out $CSR_PATH
  fi

}

_b64() {
  __n=$(cat)
  echo $__n | tr '/+' '_-' | tr -d '= '
}

_send_signed_request() {
  url=$1
  payload=$2
  needbase64=$3
  
  _debug url $url
  _debug payload "$payload"
  
  CURL_HEADER="$WORKING_DIR/curl.header"
  dp="$WORKING_DIR/curl.dump"
  CURL="curl --silent --dump-header $CURL_HEADER "
  if [ "$DEBUG" ] ; then
    CURL="$CURL --trace-ascii $dp "
  fi
  payload64=$(echo -n $payload | base64 -w 0 | _b64)
  _debug payload64 $payload64
  
  nonceurl="$API/directory"
  nonce=$($CURL -I $nonceurl | grep "^Replay-Nonce:" | sed s/\\r//|sed s/\\n//| cut -d ' ' -f 2)

  _debug nonce $nonce
  
  protected=$(echo -n "$HEADERPLACE" | sed "s/NONCE/$nonce/" )
  _debug protected "$protected"
  
  protected64=$( echo -n $protected | base64 -w 0 | _b64)
  _debug protected64 "$protected64"
  
  sig=$(echo -n "$protected64.$payload64" |  openssl   dgst   -sha256  -sign  $ACCOUNT_KEY_PATH | base64 -w 0 | _b64)
  _debug sig "$sig"
  
  body="{\"header\": $HEADER, \"protected\": \"$protected64\", \"payload\": \"$payload64\", \"signature\": \"$sig\"}"
  _debug body "$body"
  
  if [ "$needbase64" ] ; then
    response="$($CURL -X POST --data "$body" $url | base64 -w 0)"
  else
    response="$($CURL -X POST --data "$body" $url)"
  fi

  responseHeaders="$(sed 's/\r//g' $CURL_HEADER)"
  
  _debug responseHeaders "$responseHeaders"
  _debug response  "$response"
  code="$(grep ^HTTP $CURL_HEADER | tail -1 | cut -d " " -f 2)"
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
    echo usage: $0  '"file"  "opt"  "="  "value" [";"]'
    return
  fi
  if [ ! -f $__conf ] ; then
    touch $__conf
  fi
  if grep -H -n "^$__opt$__sep" $__conf > /dev/null ; then
    _debug OK
    sed -i "s|^$__opt$__sep.*$|$__opt$__sep$__val$__end|" $__conf 
  else
    _debug APP
    echo "$__opt$__sep$__val$__end" >> $__conf
  fi
  _debug "$(grep -H -n "^$__opt$__sep" $__conf)"
}

_startserver() {
  content="$1"
  while true ; do
    if [ -z "$DEBUG" ] ; then
      echo -e -n "HTTP/1.1 200 OK\r\n\r\n$content" | nc -q 1 -l -p 80 > /dev/null
    else
      echo -e -n "HTTP/1.1 200 OK\r\n\r\n$content" | nc -q 1 -l -p 80
    fi
  done
}

_stopserver() {
  pid="$1"
  if [ "$pid" ] ; then
    if [ "$DEBUG" ] ; then
      kill -s 9 $pid 2>&1
      killall -s 9  nc 2>&1
    else
      kill -s 9 $pid 2>&1 > /dev/null
      killall -s 9  nc 2>&1 > /dev/null
    fi
  fi
}

_initpath() {
  if [ -z "$WORKING_DIR" ]; then
    WORKING_DIR=~/.le
  fi
  
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
  
  CA_CERT_PATH=$WORKING_DIR/$domain/ca.cer
}

#issue webroot a.com [www.a.com,b.com,c.com]  [key-length] [cert-file-path] [key-file-path] [reloadCmd]
issue() {
  if [ -z "$1" ] ; then
    echo "Usage: $0 webroot a.com [www.a.com,b.com,c.com]  [key-length] [cert-file-path] [key-file-path] [ca-cert-file-path] [reloadCmd]"
    return 1
  fi
  Le_Webroot=$1
  Le_Domain=$2
  Le_Alt=$3
  Le_Keylength=$4
  Le_RealCertPath=$5
  Le_RealKeyPath=$6
  Le_RealCACertPath=$7
  Le_ReloadCmd=$8
  
  if [ -z "$Le_Domain" ] ; then 
    Le_Domain="$1"
  fi
  
  _initpath $Le_Domain
  
  DOMAIN_CONF=$WORKING_DIR/$Le_Domain/$Le_Domain.conf
  if [ -f "$DOMAIN_CONF" ] ; then
    source "$DOMAIN_CONF"
    if [ -z "$FORCE" ] && [ "$Le_NextRenewTime" ] && [ "$(date -u "+%s" )" -lt "$Le_NextRenewTime" ] ; then 
      _info "Skip, Next renwal time is: $Le_NextRenewTimeStr"
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
  
  if [ "$Le_Webroot" == "no" ] ; then
    _info "Standalone mode."
    if ! command -v "nc" > /dev/null ; then
      _err "Please install netcat(nc) tools first."
      return 1
    fi
    if ! command -v "netstat" > /dev/null ; then
      _err "Please install netstat first."
      return 1
    fi
    netprc="$(netstat -ntpl | grep ':80 ')"
    if [ "$netprc" ] ; then
      _err "$netprc"
      _err "tcp port 80 is already used by $(echo "$netprc" | cut -d '/' -f 2)"
      _err "Please stop it first"
      return 1
    fi
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
  n=$(echo $modulus| xxd -r -p | base64 -w 0 | _b64 )

  jwk='{"e": "'$e'", "kty": "RSA", "n": "'$n'"}'
  
  HEADER='{"alg": "RS256", "jwk": '$jwk'}'
  HEADERPLACE='{"nonce": "NONCE", "alg": "RS256", "jwk": '$jwk'}'
  _debug HEADER "$HEADER"
  
  accountkey_json=$(echo -n "$jwk" | sed "s/ //g")
  thumbprint=$(echo -n "$accountkey_json" | sha256sum | xxd -r -p | base64 -w 0 | _b64)
  
  
  _info "Registering account"
  regjson='{"resource": "new-reg", "agreement": "'$AGREEMENT'"}'
  if [ "$ACCOUNT_EMAIL" ] ; then
    regjson='{"resource": "new-reg", "contact": ["mailto: '$ACCOUNT_EMAIL'"], "agreement": "'$AGREEMENT'"}'
  fi  
  _send_signed_request   "$API/acme/new-reg"  "$regjson"
  
  if [ "$code" == "" ] || [ "$code" == '201' ] ; then
    _info "Registered"
    echo $response > $WORKING_DIR/account.json
  elif [ "$code" == '409' ] ; then
    _info "Already registered"
  else
    _err "Register account Error."
    return 1
  fi
  
  # verify each domain
  _info "Verify each domain"
  
  alldomains=$(echo "$Le_Domain,$Le_Alt" | sed "s/,/ /g")
  for d in $alldomains   
  do  
    _info "Verifing domain" $d
    
    _send_signed_request "$API/acme/new-authz" "{\"resource\": \"new-authz\", \"identifier\": {\"type\": \"dns\", \"value\": \"$d\"}}"
 
    if [ ! -z "$code" ] && [ ! "$code" == '201' ] ; then
      _err "new-authz error: $response"
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
    
    if [ "$Le_Webroot" == "no" ] ; then
      _info "Standalone mode server"
      _startserver "$keyauthorization" 2>&1 >/dev/null &
      serverproc="$!"
      sleep 2
      _debug serverproc $serverproc
    else
      wellknown_path="$Le_Webroot/.well-known/acme-challenge"
      _debug wellknown_path "$wellknown_path"
      
      mkdir -p "$wellknown_path"
      wellknown_path="$wellknown_path/$token"
      echo -n "$keyauthorization" > $wellknown_path
    fi
    wellknown_url="http://$d/.well-known/acme-challenge/$token"
    _debug wellknown_url "$wellknown_url"
    
    _debug challenge "$challenge"
    _send_signed_request $uri "{\"resource\": \"challenge\", \"keyAuthorization\": \"$keyauthorization\"}"
    
    if [ ! -z "$code" ] && [ ! "$code" == '202' ] ; then
      _err "challenge error: $d"
      _stopserver $serverproc
      return 1
    fi
    
    while [ "1" ] ; do
      _debug "sleep 5 secs to verify"
      sleep 5
      _debug "checking"
      
      if ! _get $uri ; then
        _err "Verify error:$resource"
        _stopserver $serverproc
        return 1
      fi
      
      status=$(echo $response | egrep -o  '"status":"[^"]+"' | cut -d : -f 2 | sed 's/"//g')
      if [ "$status" == "valid" ] ; then
        _info "Success"
        break;
      fi
      
      if [ "$status" == "invalid" ] ; then
         error=$(echo $response | egrep -o '"error":{[^}]*}' | grep -o '"detail":"[^"]*"' | cut -d '"' -f 4)
        _err "Verify error:$error"
        _stopserver $serverproc
        return 1;
      fi
      
      if [ "$status" == "pending" ] ; then
        _info "Pending"
      else
        _err "Verify error:$response" 
        _stopserver $serverproc
        return 1
      fi
      
    done
    _stopserver $serverproc
  done 
  
  _info "Verify finished, start to sign."
  der="$(openssl req  -in $CSR_PATH -outform DER | base64 -w 0 | _b64)"
  _send_signed_request "$API/acme/new-cert" "{\"resource\": \"new-cert\", \"csr\": \"$der\"}" "needbase64"
  
  
  Le_LinkCert="$(grep -i -o '^Location.*' $CURL_HEADER |sed 's/\r//g'| cut -d " " -f 2)"
  _setopt $DOMAIN_CONF  "Le_LinkCert"           "="  "$Le_LinkCert"
  
  if [ "$Le_LinkCert" ] ; then
    echo -----BEGIN CERTIFICATE----- > $CERT_PATH
    curl --silent $Le_LinkCert | base64  >> $CERT_PATH
    echo -----END CERTIFICATE-----  >> $CERT_PATH
    _info "Cert success."
    cat $CERT_PATH
    
    _info "Your cert is in $CERT_PATH"
  fi
  
  _setopt $DOMAIN_CONF  "Le_Domain"             "="  "$Le_Domain"
  _setopt $DOMAIN_CONF  "Le_Alt"                "="  "$Le_Alt"
  _setopt $DOMAIN_CONF  "Le_Webroot"            "="  "$Le_Webroot"
  _setopt $DOMAIN_CONF  "Le_Keylength"          "="  "$Le_Keylength"
  _setopt $DOMAIN_CONF  "Le_RealCertPath"       "="  "\"$Le_RealCertPath\""
  _setopt $DOMAIN_CONF  "Le_RealCACertPath"     "="  "\"$Le_RealCACertPath\""
  _setopt $DOMAIN_CONF  "Le_RealKeyPath"        "="  "\"$Le_RealKeyPath\""
  _setopt $DOMAIN_CONF  "Le_ReloadCmd"          "="  "\"$Le_ReloadCmd\""
  
  if [ -z "$Le_LinkCert" ] ; then
    response="$(echo $response | base64 -d)"
    _info "Sign failed: $(echo "$response" | grep -o  '"detail":"[^"]*"')"
    return 1
  fi
  
  Le_LinkIssuer=$(grep -i '^Link' $CURL_HEADER | cut -d " " -f 2| cut -d ';' -f 1 | sed 's/<//g' | sed 's/>//g')
  _setopt $DOMAIN_CONF  "Le_LinkIssuer"         "="  "$Le_LinkIssuer"
  
  if [ "$Le_LinkIssuer" ] ; then
    echo -----BEGIN CERTIFICATE----- > $CA_CERT_PATH
    curl --silent $Le_LinkIssuer | base64  >> $CA_CERT_PATH
    echo -----END CERTIFICATE-----  >> $CA_CERT_PATH
    _info "The intermediate CA cert is in $CA_CERT_PATH"
  fi
  
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
    
  
  if [ "$Le_RealCertPath" ] ; then
    if [ -f "$Le_RealCertPath" ] ; then
      rm -f $Le_RealCertPath
    fi
    ln -s $CERT_PATH $Le_RealCertPath
  fi
  
  
  if [ "$Le_RealCACertPath" ] ; then
    if [ -f "$Le_RealCACertPath" ] ; then
      rm -f $Le_RealCACertPath
    fi
    ln -s $CA_CERT_PATH $Le_RealCACertPath
  fi  

  
  if [ "$Le_RealKeyPath" ] ; then
    if [ -f "$Le_RealKeyPath" ] ; then
      rm -f $Le_RealKeyPath
    fi
    ln -s $CERT_KEY_PATH $Le_RealKeyPath
  fi
  
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

  issue $Le_Domain

}

renewAll() {
  _initpath
  _info "renewAll"
  
  for d in $(ls -F $WORKING_DIR | grep  '/$') ; do
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
    
    renew "$d"  
  done
  
}

install() {
  _initpath
  if ! command -v "curl" > /dev/null ; then
    _err "Please install curl first."
    _err "Ubuntu: sudo apt-get install curl"
    _err "CentOS: yum install curl"
    return 1
  fi
  
  if ! command -v "crontab" > /dev/null ; then
    _err "Please install crontab first."
    _err "CentOs: yum -y install crontabs"
    return 1
  fi
  
  if ! command -v "openssl" > /dev/null ; then
    _err "Please install openssl first."
    _err "CentOs: yum -y install openssl"
    return 1
  fi
  
  if ! command -v "xxd" > /dev/null ; then
    _err "Please install xxd first."
    _err "CentOs: yum install vim-common"
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
    if command -v crond > /dev/null ; then
      service crond reload 2>/dev/null
    else
      service cron reload 2>/dev/null
    fi
  fi  
  
  
  _info OK
}

uninstall() {
  _initpath
  _info "Removing cron job"

  if crontab -l | grep 'le.sh renewAll' ; then 
    crontab -l | sed "/le.sh renewAll/d" | crontab -
    if command -v crond > /dev/null ; then
      service crond reload 2>/dev/null
    else
      service cron reload 2>/dev/null
    fi
  fi 

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




