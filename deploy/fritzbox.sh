#!/usr/bin/env sh

#Here is a script to deploy cert to an AVM FRITZ!Box router.

#returns 0 means success, otherwise error.

#DEPLOY_FRITZBOX_USERNAME="username"
#DEPLOY_FRITZBOX_PASSWORD="password"
#DEPLOY_FRITZBOX_URL="https://fritz.box"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
fritzbox_deploy() {
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

  if ! _exists wget; then
    _err "wget not found"
    return 1
  fi
  if ! exists iconv; then
    _err "iconv not found"
    return 1
  fi

  _fritzbox_username="${DEPLOY_FRITZBOX_USERNAME}"
  _fritzbox_password="${DEPLOY_FRITZBOX_PASSWORD}"
  _fritzbox_url="${DEPLOY_FRITZBOX_URL}"

  _debug _fritzbox_url "$_fritzbox_url"
  _debug _fritzbox_usename "$_fritzbox_username"
  _secure_debug _fritzbox_password "$_fritzbox_password"
  if [ ! -z "$_fritzbox_username" ]; then
    _err "FRITZ!Box username is not found, please define DEPLOY_FRITZBOX_USERNAME."
    return 1
  fi
  if [ ! -z "$_fritzbox_password" ]; then
    _err "FRITZ!Box password is not found, please define DEPLOY_FRITZBOX_PASSWORD."
    return 1
  fi
  if [ ! -z "$_fritzbox_url" ]; then
    _err "FRITZ!Box url is not found, please define DEPLOY_FRITZBOX_URL."
    return 1
  fi

  _info "Log in in to the FRITZ!Box"
  _fritzbox_challenge="$(wget -q -O - ${_fritzbox_url}/login_sid.lua | sed -e 's/^.*<Challenge>//' -e 's/<\/Challenge>.*$//')"
  _fritzbox_hash="$(echo -n ${_fritzbox_challenge}-${_fritzbox_password} | iconv -f ASCII -t UTF16LE | md5sum | awk '{print $1}')"
  _fritzbox_sid="$(wget -q -O - ${_fritzbox_url}/login_sid.lua?sid=0000000000000000\&username=${_frithbox_username}\&response=${_fritzbox_challenge}-${_fritzbox_hash} | sed -e 's/^.*<SID>//' -e 's/<\/SID>.*$//')"

  _info "Generate form POST request"
  _post_request="$(_mktemp)"
  _post_boundary="---------------------------$(date +%Y%m%d%H%M%S)"
  printf -- "--${_post_boundary}\r\n" >> "${_post_request}"
  printf "Content-Disposition: form-data; name=\"sid\"\r\n\r\n${_fritzbox_sid}\r\n" >> "${_post_request}"
  printf -- "--${_post_boundary}\r\n" >> "${_post_request}"
  # _CERTPASSWORD_ is unset because Let's Encrypt certificates don't have a passwort. But if they ever do, here's the place to use it!
  printf "Content-Disposition: form-data; name=\"BoxCertPassword\"\r\n\r\n${_CERTPASSWORD_}\r\n" >> "${_post_request}"
  printf -- "--${_post_boundary}\r\n" >> "${_post_request}"
  printf "Content-Disposition: form-data; name=\"BoxCertImportFile\"; filename=\"BoxCert.pem\"\r\n" >> "${_post_request}"
  printf "Content-Type: application/octet-stream\r\n\r\n" >> "${_post_request}"
  cat "${_ckey}" >> "${_post_request}"
  cat "${_cfullchain}" >> "${_post_request}"
  printf "\r\n" >> "${_post_request}"
  printf -- "--${_post_boundary}--" >> "${_post_request}"

  _info "Upload certificate to the FRITZ!Box"
  wget -q -O - "${_fritzbox_url}/cgi-bin/firmwarecfg" --header="Content-type: multipart/form-data boundary=${_post_boundary}" --post-file "${_post_request}"

  _info "Upload successful"
  rm "${_post_request}"

  return 0
}

