#!/bin/bash

# Zimbra Assumptions:
#    1) acme.sh is installed as Zimbra
#    2) see: https://wiki.zimbra.com/wiki/index.php?curid=2441
# Related Questions to users: JDunphy and seidler in forums.zimbra.org

########  Public functions #####################

#domain keyfile certfile cafile fullchain
zimbra_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  # Zimbra's javastore still needs DST Root CA X3 to verify on some versions
  _IdentTrust="$(dirname "$_cca")/../IdentTrust.pem"
  _debug _IdentTrust "$_IdentTrust"

  # grab it if we don't have it
  if [ ! -f "$_IdentTrust" ]; then
     _debug No "$_IdentTrust"
     wget -q "https://ssl-tools.net/certificates/dac9024f54d8f6df94935fb1732638ca6ad77c13.pem" -O "$_IdentTrust" || return 1
  fi

  # append Intermediate 
  cat "$_cfullchain" "$(dirname "$_cca")/../IdentTrust.pem" > "${_cca}.real"
  /opt/zimbra/bin/zmcertmgr verifycrt comm "$_ckey" "$_ccert" "${_cca}.real" || return 1

  #if it verifies we can deploy it
  cp -f "$_ckey" /opt/zimbra/ssl/zimbra/commercial/commercial.key
  /opt/zimbra/bin/zmcertmgr deploycrt comm "$_ccert" "${_cca}.real" || return 1
  
  # %%% ldap wasn't being restarted leading to failed communication in the future
  # Adding a ldap restart was not tested so perhaps. Reload is restart when not defined by zimbra with
  # exception of ldap which they didn't provide a reload.
  #/opt/zimbra/bin/ldap restart
  #/opt/zimbra/bin/zmmailboxdctl reload
  #/opt/zimbra/bin/zmproxyctl reload
  #/opt/zimbra/bin/zmmtactl reload
  
  # Recommended by Zimbra for certificate reloads
  /opt/zimbra/bin/zmcontrol restart
  return 0
}
