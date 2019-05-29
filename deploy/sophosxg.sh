#!/usr/bin/env sh
#
# This deploy script deploys to a Sophos XG appliance
# DEPLOY_SOPHOSXG_HOST="<NO DEFAULT - REQUIRED - host:port>"
# DEPLOY_SOPHOSXG_USER="<NO DEFAULT - REQUIRED - string>"
# DEPLOY_SOPHOSXG_PASSWORD="<NO DEFAULT - REQUIRED - string>"
# DEPLOY_SOPHOSXG_NAME="domain"
# DEPLOY_SOPHOSXG_PFX_PASSWORD="s0ph0sXG"
# DEPLOY_SOPHOSXG_HTTPS_INSECURE="1"

########  Public functions #####################

#action pfx user password name pfxpass host
sophosxg_do_req() {

  # does curl request to upload certificate to sophos appliance

  # check number of args
  [ $# -eq 7 ] || return 1

  # set vars
  _do_req_action="$1"
  _do_req_pfx="$2"
  _do_req_user="$3"
  _do_req_password="$4"
  _do_req_name="$5"
  _do_req_pfxpass="$6"
  _do_req_host="$7"

  # create temp file for xml
  _info "Creating request XML"
  _do_req_xml="$(_mktemp)"
  if [ ! -f "$_do_req_xml" ]; then
    _err "Error creating temp file for XML"
    return 1
  fi

  # create xml request
  echo "
<Request>
  <Login>
    <Username>${_do_req_user}</Username>
    <Password>${_do_req_password}</Password>
  </Login>
  <Set operation=\"${_do_req_action}\">
    <Certificate>
      <Action>UploadCertificate</Action>
      <Name>${_do_req_name}</Name>
      <Password>${_do_req_pfxpass}</Password>
      <CertificateFormat>pkcs12</CertificateFormat>
      <CertificateFile>certificate.p12</CertificateFile>
      <PrivateKeyFile></PrivateKeyFile>
    </Certificate>
  </Set>
</Request>
" > "$_do_req_xml"

  # dont verify certificate if HTTPS_INSECURE was set
  if [ "$Le_Deploy_sophosxg_https_insecure" = "1" ] || [ "$HTTPS_INSECURE" ]; then
    _sophosxg_curl="$_sophosxg_curl --insecure"
  fi

  # do request with curl
  $_sophosxg_curl --silent -F "reqxml=<$_do_req_xml" -F "file=@$_do_req_pfx;filename=certificate.p12" "https://$_do_req_host/webconsole/APIController?" | grep -q '<Status code="200">'
  ret=$?

  # remove xml file
  rm -f "$_do_req_xml"

  return $ret
}

#domain keyfile certfile cafile fullchain
sophosxg_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  # check for curl first
  if _exists "curl"; then
    _sophosxg_curl="curl --silent"
  else
    _err "curl is required"
    return 1
  fi

  # Some defaults
  DEFAULT_SOPHOSXG_PFX_PASSWORD="s0ph0sXG"
  DEFAULT_SOPHOSXG_NAME="$_cdomain"
  DEFAULT_SOPHOSXG_HTTPS_INSECURE="1"

  if [ -f "$DOMAIN_CONF" ]; then
    # shellcheck disable=SC1090
    . "$DOMAIN_CONF"
  fi

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  # HOST is required
  if [ -z "$DEPLOY_SOPHOSXG_HOST" ]; then
    if [ -z "$Le_Deploy_sophosxg_host" ]; then
      _err "DEPLOY_SOPHOSXG_HOST not defined."
      return 1
    fi
  else
    Le_Deploy_sophosxg_host="$DEPLOY_SOPHOSXG_HOST"
    _savedomainconf Le_Deploy_sophosxg_host "$Le_Deploy_sophosxg_host"
  fi

  # USER is required
  if [ -z "$DEPLOY_SOPHOSXG_USER" ]; then
    if [ -z "$Le_Deploy_sophosxg_user" ]; then
      _err "DEPLOY_SOPHOSXG_USER not defined."
      return 1
    fi
  else
    Le_Deploy_sophosxg_user="$DEPLOY_SOPHOSXG_USER"
    _savedomainconf Le_Deploy_sophosxg_user "$Le_Deploy_sophosxg_user"
  fi

  # PASSWORD is required
  if [ -z "$DEPLOY_SOPHOSXG_PASSWORD" ]; then
    if [ -z "$Le_Deploy_sophosxg_password" ]; then
      _err "DEPLOY_SOPHOSXG_PASSWORD not defined."
      return 1
    fi
  else
    Le_Deploy_sophosxg_password="$DEPLOY_SOPHOSXG_PASSWORD"
    _savedomainconf Le_Deploy_sophosxg_password "$Le_Deploy_sophosxg_password"
  fi

  # PFX_PASSWORD is optional. If not provided then use default
  if [ -n "$DEPLOY_SOPHOSXG_PFX_PASSWORD" ]; then
    Le_Deploy_sophosxg_pfx_password="$DEPLOY_SOPHOSXG_PFX_PASSWORD"
    _savedomainconf Le_Deploy_sophosxg_pfx_password "$Le_Deploy_sophosxg_pfx_password"
  elif [ -z "$Le_Deploy_sophosxg_pfx_password" ]; then
    Le_Deploy_sophosxg_pfx_password="$DEFAULT_SOPHOSXG_PFX_PASSWORD"
  fi

  # NAME is optional. If not provided then use $_cdomain
  if [ -n "$DEPLOY_SOPHOSXG_NAME" ]; then
    Le_Deploy_sophosxg_name="$DEPLOY_SOPHOSXG_NAME"
    _savedomainconf Le_Deploy_sophosxg_name "$Le_Deploy_sophosxg_name"
  elif [ -z "$Le_Deploy_sophosxg_name" ]; then
    Le_Deploy_sophosxg_name="$DEFAULT_SOPHOSXG_NAME"
  fi

  # HTTPS_INSECURE is optional. Defaults to 1 (true)
  if [ -n "$DEPLOY_SOPHOSXG_HTTPS_INSECURE" ]; then
    Le_Deploy_sophosxg_https_insecure="$DEPLOY_SOPHOSXG_HTTPS_INSECURE"
    _savedomainconf Le_Deploy_sophosxg_https_insecure "$Le_Deploy_sophosxg_https_insecure"
  elif [ -z "$Le_Deploy_sophosxg_https_insecure" ]; then
    Le_Deploy_sophosxg_https_insecure="$DEFAULT_SOPHOSXG_HTTPS_INSECURE"
  fi

  # create temp pkcs12 file
  _info "Generating pkcs12 file"
  _import_pkcs12="$(_mktemp)"
  if [ ! -f "$_import_pkcs12" ]; then
    _err "Error creating temp file for pkcs12"
    return 1
  fi
  if ! _toPkcs "$_import_pkcs12" "$_ckey" "$_ccert" "$_cca" "$Le_Deploy_sophosxg_pfx_password"; then
    _err "Error exporting to pkcs12"
    [ -f "$_import_pkcs12" ] && rm -f "$_import_pkcs12"
    return 1
  fi

  # do upload of cert - attempt to "update" and on failure try "add"
  _req_action_success="no"
  for _req_action in update add; do
    _info "Uploading certificate: $_req_action"
    
    if sophosxg_do_req "$_req_action" "$_import_pkcs12" "$Le_Deploy_sophosxg_user" "$Le_Deploy_sophosxg_password" "$Le_Deploy_sophosxg_name" "$Le_Deploy_sophosxg_pfx_password" "$Le_Deploy_sophosxg_host"; then
      _req_action_success="yes"
      break
    fi
    _info "$_req_action failed"
  done

  # clean up pfx
  [ -f "$_import_pkcs12" ] && rm -f "$_import_pkcs12"

  # check final result
  if [ "$_req_action_success" = "no" ]; then
    _err "Upload failed permanently"
    return 1
  fi

  return 0 

}
