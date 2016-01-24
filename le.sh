#!/bin/bash
VER=1.1.1
PROJECT="https://github.com/Neilpang/le"

DEFAULT_CA="https://acme-v01.api.letsencrypt.org"
DEFAULT_AGREEMENT="https://letsencrypt.org/documents/LE-SA-v1.0.1-July-27-2015.pdf"

STAGE_CA="https://acme-staging.api.letsencrypt.org"

VTYPE_HTTP="http-01"
VTYPE_DNS="dns-01"

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
    openssl genrsa $length > "$ACCOUNT_KEY_PATH"
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
  
  if [ -f "$CERT_KEY_PATH" ] && ! [ "$FORCE" ] ; then 
    if [ "$IS_RENEW" ] ; then
      _info "Domain key exists, skip"
      return 0
    else
      _err "Domain key exists, do you want to overwrite the key?"
      _err "Set FORCE=1, and try again."
      return 1
    fi
  else
    #generate account key
    openssl genrsa $length > "$CERT_KEY_PATH"
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
  
  if [ -f "$CSR_PATH" ]  && [ "$IS_RENEW" ] && ! [ "$FORCE" ]; then
    _info "CSR exists, skip"
    return
  fi
  
  if [ -z "$domainlist" ] ; then
    #single domain
    _info "Single domain" $domain
    openssl req -new -sha256 -key "$CERT_KEY_PATH" -subj "/CN=$domain" > "$CSR_PATH"
  else
    alt="DNS:$(echo $domainlist | sed "s/,/,DNS:/g")"
    #multi 
    _info "Multi domain" "$alt"
    openssl req -new -sha256 -key "$CERT_KEY_PATH" -subj "/CN=$domain" -reqexts SAN -config <(printf "[ req_distinguished_name ]\n[ req ]\ndistinguished_name = req_distinguished_name\n[SAN]\nsubjectAltName=$alt") -out "$CSR_PATH"
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
  if [ ! -f "$__conf" ] ; then
    touch "$__conf"
  fi
  if grep -H -n "^$__opt$__sep" "$__conf" > /dev/null ; then
    _debug OK
    if [[ "$__val" == *"&"* ]] ; then
      __val="$(echo $__val | sed 's/&/\\&/g')"
    fi
    sed -i "s|^$__opt$__sep.*$|$__opt$__sep$__val$__end|" "$__conf"
  else
    _debug APP
    echo "$__opt$__sep$__val$__end" >> "$__conf"
  fi
  _debug "$(grep -H -n "^$__opt$__sep" $__conf)"
}

_startserver() {
  content="$1"
  _NC="nc -q 1"
  if nc -h | grep "nmap.org/ncat" >/dev/null ; then
    _NC="nc"
  fi
#  while true ; do
    if [ "$DEBUG" ] ; then
      echo -e -n "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC -l -p 80 -vv
    else
      echo -e -n "HTTP/1.1 200 OK\r\n\r\n$content" | $_NC -l -p 80 > /dev/null
    fi
#  done
}

_stopserver() {
  pid="$1"

}

_initpath() {

  if command -v sudo > /dev/null ; then
    if [ "$(sudo -n uptime 2>&1|grep "load"|wc -l)" != "0" ] ; then
      SUDO=sudo
    fi
  fi
  
  if [ -z "$API" ] ; then
    if [ -z "$STAGE" ] ; then
      API="$DEFAULT_CA"
    else
      API="$STAGE_CA"
      _info "Using stage api:$API"
    fi  
  fi
  
  if [ -z "$WORKING_DIR" ]; then
    WORKING_DIR=$HOME/.le
  fi
  
  if [ -z "$ACME_DIR" ] ; then
    ACME_DIR="/home/.acme"
  fi
  
  if [ -z "$APACHE_CONF_BACKUP_DIR" ] ; then
    APACHE_CONF_BACKUP_DIR="$WORKING_DIR/"
  fi
  
  domain="$1"
  mkdir -p "$WORKING_DIR"
  
  if [ -z "$ACCOUNT_KEY_PATH" ] ; then
    ACCOUNT_KEY_PATH="$WORKING_DIR/account.acc"
  fi
  
  if [ -z "$domain" ] ; then
    return 0
  fi
  
  mkdir -p "$WORKING_DIR/$domain"

  if [ -z "$DOMAIN_CONF" ] ; then
    DOMAIN_CONF="$WORKING_DIR/$domain/$Le_Domain.conf"
  fi
  if [ -z "$CSR_PATH" ] ; then
    CSR_PATH="$WORKING_DIR/$domain/$domain.csr"
  fi
  if [ -z "$CERT_KEY_PATH" ] ; then 
    CERT_KEY_PATH="$WORKING_DIR/$domain/$domain.key"
  fi
  if [ -z "$CERT_PATH" ] ; then
    CERT_PATH="$WORKING_DIR/$domain/$domain.cer"
  fi
  if [ -z "$CA_CERT_PATH" ] ; then
    CA_CERT_PATH="$WORKING_DIR/$domain/ca.cer"
  fi

  
}


_apachePath() {
  httpdroot="$(apachectl -V | grep HTTPD_ROOT= | cut -d = -f 2 | sed s/\"//g)"
  httpdconfname="$(apachectl -V | grep SERVER_CONFIG_FILE= | cut -d = -f 2 | sed s/\"//g)"
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
    _info "skip for removelevel:$2"
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

    netprc="$(ss -ntpl | grep ':80 ')"
    if [ "$netprc" ] ; then
      _err "$netprc"
      _err "tcp port 80 is already used by $(echo "$netprc" | cut -d :  -f 4)"
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
  
  if ! createDomainKey $Le_Domain $Le_Keylength ; then 
    _err "Create domain key error."
    return 1
  fi
  
  if ! createCSR  $Le_Domain  $Le_Alt ; then
    _err "Create CSR error."
    return 1
  fi

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
    _clearup
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
    alldomains=$(echo "$Le_Domain,$Le_Alt" | sed "s/,/ /g")
    for d in $alldomains   
    do  
      # check if domain is already verified for the account
      _info "Checking if domain is already verified"
      uri=$(echo $d | cut -d $sep -f 3)
      if ! _get $uri ; then
        _err "$d:Verify pending"

        _info "Geting token for domain" $d
        _send_signed_request "$API/acme/new-authz" "{\"resource\": \"new-authz\", \"identifier\": {\"type\": \"dns\", \"value\": \"$d\"}}"
        if [ ! -z "$code" ] && [ ! "$code" == '201' ] ; then
          _err "new-authz error: $response"
          _clearup
          return 1
        fi

        entry=$(echo $response | egrep -o  '{[^{]*"type":"'$vtype'"[^}]*')
        _debug entry "$entry"

        token=$(echo "$entry" | sed 's/,/\n'/g| grep '"token":'| cut -d : -f 2|sed 's/"//g')
        _debug token $token

        uri=$(echo "$entry" | sed 's/,/\n'/g| grep '"uri":'| cut -d : -f 2,3|sed 's/"//g')
        _debug uri $uri

        keyauthorization="$token.$thumbprint"
        _debug keyauthorization "$keyauthorization"

        dvlist="$d$sep$keyauthorization$sep$uri"
        _debug dvlist "$dvlist"

        vlist="$vlist$dvlist,"
      else
        _info "$d:Already verified"
      fi

    done

    #add entry
    dnsadded=""
    ventries=$(echo "$vlist" | sed "s/,/ /g")
    for ventry in $ventries
    do
      d=$(echo $ventry | cut -d $sep -f 1)
      keyauthorization=$(echo $ventry | cut -d $sep -f 2)

      if [ "$vtype" == "$VTYPE_DNS" ] ; then
        dnsadded='0'
        txtdomain="_acme-challenge.$d"
        _debug txtdomain "$txtdomain"
        txt="$(echo -e -n $keyauthorization | sha256sum | xxd -r -p | base64 -w 0 | _b64)"
        _debug txt "$txt"
        #dns
        #1. check use api
        _err "Add the following txt record:"
        _err "Domain:$txtdomain"
        _err "Txt value:$txt"
        #dnsadded='1'
      fi
    done

    if [ "$dnsadded" == '0' ] ; then
      _setopt "$DOMAIN_CONF"  "Le_Vlist" "=" "\"$vlist\""
      _debug "Dns record not added yet, so, save to $DOMAIN_CONF and exit."
      _err "Please add the txt records to the domains, and retry again."
      return 1
    fi
    
  fi
  
  
  _debug "ok, let's start to verify"
  ventries=$(echo "$vlist" | sed "s/,/ /g")
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

        webroot_owner=$(stat -c '%U:%G' $Le_Webroot)
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
      
      status=$(echo $response | egrep -o  '"status":"[^"]+"' | cut -d : -f 2 | sed 's/"//g')
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
  der="$(openssl req  -in $CSR_PATH -outform DER | base64 -w 0 | _b64)"
  _send_signed_request "$API/acme/new-cert" "{\"resource\": \"new-cert\", \"csr\": \"$der\"}" "needbase64"
  
  
  Le_LinkCert="$(grep -i -o '^Location.*' $CURL_HEADER |sed 's/\r//g'| cut -d " " -f 2)"
  _setopt "$DOMAIN_CONF"  "Le_LinkCert"           "="  "$Le_LinkCert"

  if [ "$Le_LinkCert" ] ; then
    echo -----BEGIN CERTIFICATE----- > "$CERT_PATH"
    curl --silent "$Le_LinkCert" | base64  >> "$CERT_PATH"
    echo -----END CERTIFICATE-----  >> "$CERT_PATH"
    _info "Cert success."
    cat "$CERT_PATH"
    
    _info "Your cert is in $CERT_PATH"
  fi
  

  if [ -z "$Le_LinkCert" ] ; then
    response="$(echo $response | base64 -d)"
    _err "Sign failed: $(echo "$response" | grep -o  '"detail":"[^"]*"')"
    return 1
  fi
  
  _setopt "$DOMAIN_CONF"  'Le_Vlist' '=' "\"\""
  
  Le_LinkIssuer=$(grep -i '^Link' $CURL_HEADER | cut -d " " -f 2| cut -d ';' -f 1 | sed 's/<//g' | sed 's/>//g')
  _setopt "$DOMAIN_CONF"  "Le_LinkIssuer"         "="  "$Le_LinkIssuer"
  
  if [ "$Le_LinkIssuer" ] ; then
    echo -----BEGIN CERTIFICATE----- > "$CA_CERT_PATH"
    curl --silent "$Le_LinkIssuer" | base64  >> "$CA_CERT_PATH"
    echo -----END CERTIFICATE-----  >> "$CA_CERT_PATH"
    _info "The intermediate CA cert is in $CA_CERT_PATH"
  fi
  
  Le_CertCreateTime=$(date -u "+%s")
  _setopt "$DOMAIN_CONF"  "Le_CertCreateTime"     "="  "$Le_CertCreateTime"
  
  Le_CertCreateTimeStr=$(date -u "+%Y-%m-%d %H:%M:%S UTC")
  _setopt "$DOMAIN_CONF"  "Le_CertCreateTimeStr"  "="  "\"$Le_CertCreateTimeStr\""
  
  if [ ! "$Le_RenewalDays" ] ; then
    Le_RenewalDays=80
  fi
  
  _setopt "$DOMAIN_CONF"  "Le_RenewalDays"      "="  "$Le_RenewalDays"
  
  Le_NextRenewTime=$(date -u -d "+$Le_RenewalDays day" "+%s")
  _setopt "$DOMAIN_CONF"  "Le_NextRenewTime"      "="  "$Le_NextRenewTime"
  
  Le_NextRenewTimeStr=$(date -u -d "+$Le_RenewalDays day" "+%Y-%m-%d %H:%M:%S UTC")
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

  if [ -f "$DOMAIN_CONF" ] ; then
    source "$DOMAIN_CONF"
    if [ -z "$FORCE" ] && [ "$Le_NextRenewTime" ] && [ "$(date -u "+%s" )" -lt "$Le_NextRenewTime" ] ; then 
      _info "Skip, Next renewal time is: $Le_NextRenewTimeStr"
      return 2
    fi
  fi
  IS_RENEW="1"
  issue "$Le_Webroot" "$Le_Domain" "$Le_Alt" "$Le_Keylength" "$Le_RealCertPath" "$Le_RealKeyPath" "$Le_RealCACertPath" "$Le_ReloadCmd"
  IS_RENEW=""
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
    
    DOMAIN_CONF=""
    CSR_PATH=""
    CERT_KEY_PATH=""
    CERT_PATH=""
    CA_CERT_PATH=""
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
    $Le_ReloadCmd
  fi

}

installcronjob() {
  _initpath
  _info "Installing cron job"
  if ! crontab -l | grep 'le.sh cron' ; then 
    if [ -f "$WORKING_DIR/le.sh" ] ; then
      lesh="\"$WORKING_DIR\"/le.sh"
    else
      _err "Can not install cronjob, le.sh not found."
      return 1
    fi
    crontab -l | { cat; echo "0 0 * * * $SUDO WORKING_DIR=\"$WORKING_DIR\" $lesh cron > /dev/null"; } | crontab -
  fi
  return 0
}

uninstallcronjob() {
  _info "Removing cron job"
  cr="$(crontab -l | grep 'le.sh cron')"
  if [ "$cr" ] ; then 
    crontab -l | sed "/le.sh cron/d" | crontab -
    WORKING_DIR="$(echo "$cr" | cut -d ' ' -f 7 | cut -d '=' -f 2 | tr -d '"')"
    _info WORKING_DIR "$WORKING_DIR"
  fi 
  _initpath
  
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

  #try install to /bin if is root
  if [ ! -f /usr/local/bin/le.sh ] ; then
    #if root
    if $SUDO cp le.sh /usr/local/bin/le.sh 2>&1 > /dev/null; then
      $SUDO chmod 755 /usr/local/bin/le.sh
      $SUDO ln -s "/usr/local/bin/le.sh" /usr/local/bin/le
      rm -f $WORKING_DIR/le.sh
      $SUDO ln -s /usr/local/bin/le.sh $WORKING_DIR/le.sh
      _info "Installed to /usr/local/bin/le"
    else
      #install to home, for non root user
      cp le.sh $WORKING_DIR/
      chmod +x $WORKING_DIR/le.sh
      _info "Installed to $WORKING_DIR/le.sh" 
    fi
  fi
  rm -f $WORKING_DIR/le
  ln -s $WORKING_DIR/le.sh  $WORKING_DIR/le

  installcronjob
  
  _info OK
}

uninstall() {
  uninstallcronjob
  _initpath

  if [ -f "/usr/local/bin/le.sh" ] ; then
    _info "Removing /usr/local/bin/le.sh"
    if $SUDO rm -f /usr/local/bin/le.sh ; then
      $SUDO rm -f /usr/local/bin/le
    fi
  fi
  rm -f $WORKING_DIR/le
  rm -f $WORKING_DIR/le.sh
  _info "The keys and certs are in $WORKING_DIR, you can remove them by yourself."

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
  "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9"
fi
