#!/usr/bin/env sh

# Here is a scipt to deploy the cert to your TrueNAS using the REST API.
# https://www.truenas.com/docs/hub/additional-topics/api/rest_api.html
#
# Written by Frank Plass github@f-plass.de
# https://github.com/danb35/deploy-freenas/blob/master/deploy_freenas.py
# Thanks to danb35 for your template!
#
# Following environment variables must be set:
#
# export DEPLOY_TRUENAS_APIKEY="<API_KEY_GENERATED_IN_THE_WEB_UI"
#
# The following environmental variables may be set if you don't like their
# default values:
#
# DEPLOY_TRUENAS_HOSTNAME - defaults to localhost
# DEPLOY_TRUENAS_SCHEME - defaults to http, set alternatively to https
#
#returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain
truenas_deploy() {
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

  _getdeployconf DEPLOY_TRUENAS_APIKEY

  if [ -z "$DEPLOY_TRUENAS_APIKEY" ]; then
    _err "TrueNAS Api Key is not found, please define DEPLOY_TRUENAS_APIKEY."
    return 1
  fi
  _secure_debug2 DEPLOY_TRUENAS_APIKEY "$DEPLOY_TRUENAS_APIKEY"

  # Optional hostname, scheme for TrueNAS
  _getdeployconf DEPLOY_TRUENAS_HOSTNAME
  _getdeployconf DEPLOY_TRUENAS_SCHEME

  # default values for hostname and scheme
  [ -n "${DEPLOY_TRUENAS_HOSTNAME}" ] || DEPLOY_TRUENAS_HOSTNAME="localhost"
  [ -n "${DEPLOY_TRUENAS_SCHEME}" ] || DEPLOY_TRUENAS_SCHEME="http"

  _debug2 DEPLOY_TRUENAS_HOSTNAME "$DEPLOY_TRUENAS_HOSTNAME"
  _debug2 DEPLOY_TRUENAS_SCHEME "$DEPLOY_TRUENAS_SCHEME"

  _api_url="$DEPLOY_TRUENAS_SCHEME://$DEPLOY_TRUENAS_HOSTNAME/api/v2.0"
  _debug _api_url "$_api_url"

  _H1="Authorization: Bearer $DEPLOY_TRUENAS_APIKEY"
  _secure_debug3 _H1 "$_H1"

  _info "Testing Connection TrueNAS"
  _response=$(_get "$_api_url/system/state")
  _info "TrueNAS System State: $_response."

  if [ -z "$_response" ]; then
    _err "Unable to authenticate to $_api_url."
    _err 'Check your Connection and set DEPLOY_TRUENAS_HOSTNAME="192.168.178.x".'
    _err 'or'
    _err 'set DEPLOY_TRUENAS_HOSTNAME="<truenas_dnsname>".'
    _err 'Check your Connection and set DEPLOY_TRUENAS_SCHEME="https".'
    _err "Check your Api Key."
    return 1
  fi

  _savedeployconf DEPLOY_TRUENAS_APIKEY "$DEPLOY_TRUENAS_APIKEY"
  _savedeployconf DEPLOY_TRUENAS_HOSTNAME "$DEPLOY_TRUENAS_HOSTNAME"
  _savedeployconf DEPLOY_TRUENAS_SCHEME "$DEPLOY_TRUENAS_SCHEME"

  _info "Getting active certificate from TrueNAS"
  _response=$(_get "$_api_url/system/general")
  _active_cert_id=$(echo "$_response" | grep -B2 '"name":' | grep 'id' | tr -d -- '"id: ,')
  _active_cert_name=$(echo "$_response" | grep '"name":' | sed -n 's/.*: "\(.\{1,\}\)",$/\1/p')
  _param_httpsredirect=$(echo "$_response" | grep '"ui_httpsredirect":' | sed -n 's/.*": \(.\{1,\}\),$/\1/p')
  _debug Active_UI_Certificate_ID "$_active_cert_id"
  _debug Active_UI_Certificate_Name "$_active_cert_name"
  _debug Active_UI_http_redirect "$_param_httpsredirect"

  if [ "$DEPLOY_TRUENAS_SCHEME" = "http" ] && [ "$_param_httpsredirect" = "true" ]; then
    _info "http Redirect active"
    _info "Setting DEPLOY_TRUENAS_SCHEME to 'https'"
    DEPLOY_TRUENAS_SCHEME="https"
    _api_url="$DEPLOY_TRUENAS_SCHEME://$DEPLOY_TRUENAS_HOSTNAME/api/v2.0"
    _savedeployconf DEPLOY_TRUENAS_SCHEME "$DEPLOY_TRUENAS_SCHEME"
  fi

  _info "Upload new certifikate to TrueNAS"
  _certname="Letsencrypt_$(_utc_date | tr ' ' '_' | tr -d -- ':')"
  _debug3 _certname "$_certname"

  _certData="{\"create_type\": \"CERTIFICATE_CREATE_IMPORTED\", \"name\": \"${_certname}\", \"certificate\": \"$(_json_encode <"$_cfullchain")\", \"privatekey\": \"$(_json_encode <"$_ckey")\"}"
  _add_cert_result="$(_post "$_certData" "$_api_url/certificate" "" "POST" "application/json")"

  _debug3 _add_cert_result "$_add_cert_result"

  _info "Getting Certificate list to get new Cert ID"
  _cert_list=$(_get "$_api_url/system/general/ui_certificate_choices")
  _cert_id=$(echo "$_cert_list" | grep "$_certname" | sed -n 's/.*"\([0-9]\{1,\}\)".*$/\1/p')

  _debug3 _cert_id "$_cert_id"

  _info "Activate Certificate ID: $_cert_id"
  _activateData="{\"ui_certificate\": \"${_cert_id}\"}"
  _activate_result="$(_post "$_activateData" "$_api_url/system/general" "" "PUT" "application/json")"

  _debug3 _activate_result "$_activate_result"

  _info "Check if WebDAV certificate is the same as the WEB UI"
  _webdav_list=$(_get "$_api_url/webdav")
  _webdav_cert_id=$(echo "$_webdav_list" | grep '"certssl":' | tr -d -- '"certsl: ,')

  if [ "$_webdav_cert_id" = "$_active_cert_id" ]; then
    _info "Update the WebDAV Certificate"
    _debug _webdav_cert_id "$_webdav_cert_id"
    _webdav_data="{\"certssl\": \"${_cert_id}\"}"
    _activate_webdav_cert="$(_post "$_webdav_data" "$_api_url/webdav" "" "PUT" "application/json")"
    _webdav_new_cert_id=$(echo "$_activate_webdav_cert" | _json_decode | sed -n 's/.*: \([0-9]\{1,\}\) }$/\1/p')
    if [ "$_webdav_new_cert_id" -eq "$_cert_id" ]; then
      _info "WebDAV Certificate update successfully"
    else
      _err "Unable to set WebDAV certificate"
      _debug3 _activate_webdav_cert "$_activate_webdav_cert"
      _debug3 _webdav_new_cert_id "$_webdav_new_cert_id"
      return 1
    fi
    _debug3 _webdav_new_cert_id "$_webdav_new_cert_id"
  else
    _info "WebDAV certificate not set or not the same as Web UI"
  fi

  _info "Check if FTP certificate is the same as the WEB UI"
  _ftp_list=$(_get "$_api_url/ftp")
  _ftp_cert_id=$(echo "$_ftp_list" | grep '"ssltls_certificate":' | tr -d -- '"certislfa:_ ,')

  if [ "$_ftp_cert_id" = "$_active_cert_id" ]; then
    _info "Update the FTP Certificate"
    _debug _ftp_cert_id "$_ftp_cert_id"
    _ftp_data="{\"ssltls_certificate\": \"${_cert_id}\"}"
    _activate_ftp_cert="$(_post "$_ftp_data" "$_api_url/ftp" "" "PUT" "application/json")"
    _ftp_new_cert_id=$(echo "$_activate_ftp_cert" | _json_decode | sed -n 's/.*: \([0-9]\{1,\}\) }$/\1/p')
    if [ "$_ftp_new_cert_id" -eq "$_cert_id" ]; then
      _info "FTP Certificate update successfully"
    else
      _err "Unable to set FTP certificate"
      _debug3 _activate_ftp_cert "$_activate_ftp_cert"
      _debug3 _ftp_new_cert_id "$_ftp_new_cert_id"
      return 1
    fi
    _debug3 _activate_ftp_cert "$_activate_ftp_cert"
  else
    _info "FTP certificate not set or not the same as Web UI"
  fi

  _info "Delete old Certificate"
  _delete_result="$(_post "" "$_api_url/certificate/id/$_active_cert_id" "" "DELETE" "application/json")"

  _debug3 _delete_result "$_delete_result"

  _info "Reload WebUI from TrueNAS"
  _restart_UI=$(_get "$_api_url/system/general/ui_restart")
  _debug2 _restart_UI "$_restart_UI"

  if [ -n "$_add_cert_result" ] && [ -n "$_activate_result" ]; then
    return 0
  else
    _err "Certupdate was not succesfull, please use --debug"
    return 1
  fi
}
