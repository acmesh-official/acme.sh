#!/usr/bin/env sh

#Here is a script to deploy cert to rdp server.

#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
rdp_deploy() {
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
  
  openssl pkcs12 -export -out "$DOMAIN_PATH/$_cdomain.pfx" -in "$_ccert" -inkey "$_ckey" -passout pass:
  
  THUMBPRINT=$(powershell "(Import-PfxCertificate -FilePath \"$(cygpath -w "$DOMAIN_PATH/$_cdomain.pfx")\" -CertStoreLocation Cert:\LocalMachine\My).thumbprint")
  
  wmic /namespace:\\\\root\\cimv2\\TerminalServices PATH Win32_TSGeneralSetting Set SSLCertificateSHA1Hash=$THUMBPRINT

}
