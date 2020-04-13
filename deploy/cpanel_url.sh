#!/usr/bin/env sh

# Here is the script to deploy the cert to cpanel by calling UAPI's SSL::install_ssl Function in Custom Code
# https://documentation.cpanel.net/display/DD/Tutorial+-+Call+UAPI's+SSL%3A%3Ainstall_ssl+Function+in+Custom+Code

#export DEPLOY_CPANEL_USER=username
#export DEPLOY_CPANEL_PASS=password
#export DEPLOY_CPANEL_HOST=hostname:2083

########  Public functions #####################

#domain keyfile certfile cafile fullchain

cpanel_url_deploy() {
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

  if [ -z "$DEPLOY_CPANEL_HOST" ]; then
    _err "cPanel host is not defined, please define the target hostname and port: export DEPLOY_CPANEL_HOST=hostname:2083"
    return 1
  fi

  if [ -z "$DEPLOY_CPANEL_USER" ]; then
    _err "cPanel username is not defined, please define the target username: export DEPLOY_CPANEL_USER=username"
    return 1
  fi

  if [ -z "$DEPLOY_CPANEL_PASS" ]; then
    _err "cPanel pasword is not defined, please define the target password: export DEPLOY_CPANEL_PASS=password"
    return 1
  fi

  # read cert and key files and urlencode both
  _cert=$(_url_encode <"$_ccert")
  _key=$(_url_encode <"$_ckey")

  _debug _cert "$_cert"
  _debug _key "$_key"
  _debug DEPLOY_CPANEL_HOST "$DEPLOY_CPANEL_HOST"
  _debug DEPLOY_CPANEL_USER "$DEPLOY_CPANEL_USER"

  credentials=$(printf "%b" "$DEPLOY_CPANEL_USER:$DEPLOY_CPANEL_PASS" | _base64)
  export _H1="Authorization: Basic $credentials"

  resp=$(_post "domain=${_cdomain}&cert=${_cert}&key=${_key}" "https://$DEPLOY_CPANEL_HOST/execute/SSL/install_ssl")

  _debug response "$resp"
  if echo "$resp" | grep '"status":1' >/dev/null; then
    if echo "$resp" | grep '"errors":null' >/dev/null; then
      _info "Certificate successfully deployed"
      return 0
    fi
  fi
  _err "Unable to deploy certificate, response $resp"
  return 1
}
