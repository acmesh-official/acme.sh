#!/usr/bin/env sh
# TESTING!!! # 
#Here is a script to deploy cert to apache server.

#returns 0 means success, otherwise error.
#acme.sh --install-cert -d example.com \
#--cert-file      /path/to/certfile/in/apache/cert.pem  \
#--key-file       /path/to/keyfile/in/apache/key.pem  \
#--fullchain-file /path/to/fullchain/certfile/apache/fullchain.pem \
#--reloadcmd     "service apache2 force-reload"
########  Public functions #####################
set -x
# get rid of _APACHECTL, and _exec after testing
_APACHECTL='httpd'

_exec() {
  eval "$@"
}

## $1 : new cert location $2: cp to location
_cpCert() {
  #return 0
  if cp -f ${1} ${2} && chmod 600 ${2}; then
    return 0
  fi
  return 1
}

_vhostBackupConf() {
  #return 0
  if cp -f "${1}" "${1}.bak"; then
    return 0
  fi
  return 1
}

_vhostRestoreConf() {
  #return 0
  if cp -f "${1}.bak" "${1}"; then
    return 0
  fi
  return 1
}

_testConf() {
  if ! _exec $_APACHECTL -t; then
    return 1
  fi
  return 0
}

## $1 : vhost config file to check and edit. $2: domain $3: port
_vhostConf() {
  if ! _vhostBackupConf "$1"; then
    # do something
    testvar=''
  fi

  serverName=$(awk '/ServerName/,/$/' "$1")
  serverName=$(awk -F ' ' '{print $2}' <<< ${serverName})
  serverAlias=$(awk '/ServerAlias/,/$/' "$1")
  serverAlias=$(awk -F ' ' '{print $2}' <<< ${serverAlias})
  docRoot=$(awk '/DocumentRoot/,/$/' "$1")
  docRoot=$(awk -F ' ' '{print $2}' <<< ${docRoot})
  rootParent=$(dirname ${docRoot})
  pri=$rootParent/ssl/private
  pub=$rootParent/ssl/public
  mkdir -m 700 -p ${pri:1}
  mkdir -m 700 -p ${pub:1}
  sslEng=$(awk '/SSLEngine/,/$/' "$1")
  sslEng=$(awk -F ' ' '{print $2}' <<< ${sslEng})
  sslPro=$(awk '/SSLProtocol/,/$/' "$1")
  sslPro=$(awk -F ' ' '{print $2}' <<< ${sslPro})
  sslCiph=$(awk '/SSLCipherSuite/,/$/' "$1")
  sslCiph=$(awk -F ' ' '{print $2}' <<< ${sslCiph})
  ciphOrd=$(awk '/SSLHonorCipherOrder/,/$/' "$1")
  ciphOrd=$(awk -F ' ' '{print $2}' <<< ${ciphOrd})
  crtFile=$(awk '/SSLCertificateFile/,/$/' "$1")
  crtFile=$(awk -F ' ' '{print $2}' <<< ${crtFile})
  keyFile=$(awk '/SSLCertificateKeyFile/,/$/' "$1")
  keyFile=$(awk -F ' ' '{print $2}' <<< ${keyFile})
  chainFile=$(awk '/SSLCertificateChainFile/,/$/' "$1")
  chainFile=$(awk -F ' ' '{print $2}' <<< ${chainFile})
  locSec1='<location '
  locSec2='>'
  locSec=$locSec1$docRoot$locSec2

  dirSlash=$(awk '/DirectorySlash/,/$/' "$1")
  dirSlash=$(awk -F ' ' '{print $2}' <<< ${dirSlash})
  rewriteEng=$(awk '/RewriteEngine/,/$/' "$1")
  rewriteEng=$(awk -F ' ' '{print $2}' <<< ${rewriteEng})
  rwCond1=$(awk '/RewriteCond %{HTTPS}/,/$/' "$1")
  rwCond1=$(awk -F ' ' '{print $2}' <<< ${rwCond1})
  rwCond2=$(awk '/RewriteCond %{HTTP_HOST}/,/$/' "$1")
  rwCond2=$(awk -F ' ' '{print $2}' <<< ${rwCond2})
  rwCond3=$(awk '/RewriteCond %{REQUEST_URI}/,/$/' "$1")
  rwCond3=$(awk -F ' ' '{print $2}' <<< ${rwCond3})
  rwRuleSsl=$(awk '/RewriteRule .*/,/$/' "$1")
  rwRuleSsl=$(awk -F ' ' '{print $2}' <<< ${rwRuleSsl})

  newRwRuleSsl1='RewriteRule .* https://'
  newRwRuleSsl2='/%{REQUEST_URI}/ [R=301,L,QSA]'
  newRwRuleSsl=$newRwRuleSsl1$serverName$newRwRuleSsl2


  if [ ! -z "${serverName}" ]; then
    # it is probably an alias on a wildcard port 80
    # so we will find where docroot matches and redirect there
    confRoot=$(dirname "$1")
    #confMatch=$(grep "$docRoot" "$configRoot/*.conf" /dev/null | head -n 1)
    confMatch="$(grep "${docRoot}" "${confRoot}"/*.conf /dev/null | head -n 1 | awk -F ':' '{print $1}')"
    if [ ! -z "${confMatch}" ]; then
      #confMatch="$(awk -F ':' '{print $1}' <<< ${confMatch})"
      matchServerName=$(awk '/ServerName/,/$/' "${confMatch}")
      matchServerName=$(awk -F ' ' '{print $2}' <<< "${matchServerName}")
      reWriteBlock=$(cat <<EOF
<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteRule .* https://${matchServerName}/%{REQUEST_URI}/ [R=301,L,QSA]
</IfModule>
EOF
)
      sed -i '/"${reWriteBlock}"/i </virtualhost>' "${confMatch}"
      return 0
    fi
    return 1
  fi
  if grep -q 'SSLEngine' "$1"; then
	sed -i '/SSLEngine /c\SSLEngine On' "$1"
	sed -i '/SSLProtocol /c\SSLProtocol -all +TLSv1.2' "$1"
	sed -i '/SSLCipherSuite /c\SSLCipherSuite ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:RSA+AESGCM:RSA+AES:!aNULL:!MD5:!DSS' "$1"
	sed -i '/SSLHonorCipherOrder /c\SSLHonorCipherOrder on' "$1"
	sed -i '/SSLCertificateFile /c\SSLCertificateFile ${rootParent}/ssl/public/${serverName}.crt' "$1"
	sed -i '/SSLCertificateChainFile /c\SSLCertificateChainFile ${rootParent}/ssl/public/${serverName}.chain.crt' "$1"
	sed -i '/SSLCertificateKeyFile /c\SSLCertificateKeyFile ${rootParent}/ssl/private/${serverName}.key' "$1"
	testvar=''
  else
    sslBlock=$(cat <<EOF
<virtualhost *:443>
  ServerName ${serverName}
  DocumentRoot ${docRoot}
  SSLEngine On
  SSLProtocol -all +TLSv1.2
  SSLCipherSuite ECDH+AESGCM:DH+AESGCM:ECDH+AES256:DH+AES256:ECDH+AES128:DH+AES:RSA+AESGCM:RSA+AES:!aNULL:!MD5:!DSS
  SSLHonorCipherOrder on
  SSLCertificateFile ${rootParent}/ssl/public/${serverName}.crt
  SSLCertificateChainFile ${rootParent}/ssl/public/${serverName}.chain.crt
  SSLCertificateKeyFile ${rootParent}/ssl/private/${serverName}.key

  ${locSec}
     DirectorySlash On
  </location>
</virtualhost>
EOF
)
    echo "${sslBlock}" >> "$1"
  fi

  #look for a location section eg. <location /var/www/html>

  if grep -q ${locSec} "$1"; then
    if grep -q ${dirSlash} "$1"; then
	  #set dir slash on
	  sed -i '/DirectorySlash /c\DirectorySlash On' "$1"
	  testvar=''
	else
      #append dir slash here
      sed -i '/${locSec}/a DirectorySlash On' "$1"
      testvar=''
    fi
  else
    locBlock=$(cat <<EOF
${locSec}
   DirectorySlash On
</location>
EOF
)
    # insert the new block here...
    sed -i '/<\/virtualhost>/i ${locBlock}' "$1"
  fi

  #look for mod_rewrite section
  modReWrite='<IfModule mod_rewrite.c>'
  if grep -q ${modReWrite} "$1"; then
    if grep -q "RewriteEngine On" "$1"; then
	  #set rewrite rules for ssl
	  # too many ways to redirect ssl for me to check....
	  testvar=''
	else
      #append rewrite rules for ssl
	  sed -i '/${modReWrite}/a RewriteEngine On' "$1"
	  sed -i '/RewriteEngine On/a RewriteCond %{HTTPS} !on [OR]' "$1"
	  sed -i '/RewriteCond %{HTTPS} !on [OR]/a RewriteCond %{HTTP_HOST} ^www\. [NC] [OR]' "$1"
	  sed -i '/RewriteCond %{HTTP_HOST} ^www\. [NC] [OR]/a RewriteCond %{REQUEST_URI} !(.*)/$' "$1"
	  sed -i '/RewriteCond %{REQUEST_URI} !(.*)/$/a ${newRwRuleSsl}' "$1"
      testvar=''
    fi
  else
    reWriteBlock=$(cat <<EOF
<IfModule mod_rewrite.c>
  RewriteEngine On
  RewriteCond %{HTTPS} !on [OR]
  RewriteCond %{HTTP_HOST} ^www\. [NC] [OR]
  RewriteCond %{REQUEST_URI} !(.*)/$
  ${newRwRuleSsl}
</IfModule>
EOF
)
    # insert the new block here...
    sed -i '/<\/virtualhost>/i ${reWriteBlock}' "$1"
  fi
  return
}


apache_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  all_hosts=$(eval "$_APACHECTL -S" | awk '/namevhost/,/\)/')
  #echo "$all_hosts"
  oldIFS=$IFS
  IFS='
'
  loopLog=''
  for h in $all_hosts; do
    d=$(awk -F ' ' '{print $4}' <<< "${h}")
    c=$(awk -F ' ' '{print $5}' <<< "${h}")
    c=$(echo "$c" | awk -v FS="(\\\\(|\\\\:)" '{print $2}')
    p=$(awk -F ' ' '{print $2}' <<< "${h}")
    #echo "$d $p $c"
    if echo ${d} | grep -q ${_cdomain}; then
      if _vhostConf "$c" "$d" "$p"; then
        c1='/ssl/public/'
        c2='/ssl/private/'
        k='.key'
        k1=$rootParent$c2$d$k
        c3='.crt'
        c4='.chain.crt'
        c5=$rootParent$c1$d$c3
        c6=$rootParent$c1$d$c4
        cp -f $_ckey ${k1:1}
        cp -f $_ccert ${c5:1}
        cp -f $_cfullchain ${c6:1}

      fi
    fi
  done
  IFS=$oldIFS

}

apache_deploy idragonfly.net /path/to/test.key /path/to/test.crt /path/to/test.cacert.crt /path/to/test.chain.crt
#echo "$testLog" >> test.log
set +x
