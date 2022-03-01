#!/usr/bin/env sh

#Here is a script to deploy cert to an AVM FRITZ!Box router.

#returns 0 means success, otherwise error.

#DEPLOY_FRITZBOX_USERNAME="username"
#DEPLOY_FRITZBOX_PASSWORD="password"
#DEPLOY_FRITZBOX_URL="https://fritz.box"

# Kudos to wikrie at Github for his FRITZ!Box update script:
# https://gist.github.com/wikrie/f1d5747a714e0a34d0582981f7cb4cfb

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

  if ! _exists iconv; then
    if ! _exists uconv; then
      if ! _exists perl; then
        _err "iconv or uconv or perl not found"
        return 1
      fi
    fi
  fi

  # Clear traces of incorrectly stored values
  _clearaccountconf DEPLOY_FRITZBOX_USERNAME
  _clearaccountconf DEPLOY_FRITZBOX_PASSWORD
  _clearaccountconf DEPLOY_FRITZBOX_URL

  # Read config from saved values or env
  _getdeployconf DEPLOY_FRITZBOX_USERNAME
  _getdeployconf DEPLOY_FRITZBOX_PASSWORD
  _getdeployconf DEPLOY_FRITZBOX_URL

  _debug DEPLOY_FRITZBOX_URL "$DEPLOY_FRITZBOX_URL"
  _debug DEPLOY_FRITZBOX_USERNAME "$DEPLOY_FRITZBOX_USERNAME"
  _secure_debug DEPLOY_FRITZBOX_PASSWORD "$DEPLOY_FRITZBOX_PASSWORD"

  if [ -z "$DEPLOY_FRITZBOX_USERNAME" ]; then
    _err "FRITZ!Box username is not found, please define DEPLOY_FRITZBOX_USERNAME."
    return 1
  fi
  if [ -z "$DEPLOY_FRITZBOX_PASSWORD" ]; then
    _err "FRITZ!Box password is not found, please define DEPLOY_FRITZBOX_PASSWORD."
    return 1
  fi
  if [ -z "$DEPLOY_FRITZBOX_URL" ]; then
    _err "FRITZ!Box url is not found, please define DEPLOY_FRITZBOX_URL."
    return 1
  fi

  # Save current values
  _savedeployconf DEPLOY_FRITZBOX_USERNAME "$DEPLOY_FRITZBOX_USERNAME"
  _savedeployconf DEPLOY_FRITZBOX_PASSWORD "$DEPLOY_FRITZBOX_PASSWORD"
  _savedeployconf DEPLOY_FRITZBOX_URL "$DEPLOY_FRITZBOX_URL"

  # Do not check for a valid SSL certificate, because initially the cert is not valid, so it could not install the LE generated certificate
  export HTTPS_INSECURE=1

  _info "Log in to the FRITZ!Box"
  _fritzbox_challenge="$(_get "${DEPLOY_FRITZBOX_URL}/login_sid.lua" | sed -e 's/^.*<Challenge>//' -e 's/<\/Challenge>.*$//')"
  if _exists iconv; then
    _fritzbox_hash="$(printf "%s-%s" "${_fritzbox_challenge}" "${DEPLOY_FRITZBOX_PASSWORD}" | iconv -f ASCII -t UTF16LE | _digest md5 hex)"
  elif _exists uconv; then
    _fritzbox_hash="$(printf "%s-%s" "${_fritzbox_challenge}" "${DEPLOY_FRITZBOX_PASSWORD}" | uconv -f ASCII -t UTF16LE | _digest md5 hex)"
  else
    _fritzbox_hash="$(printf "%s-%s" "${_fritzbox_challenge}" "${DEPLOY_FRITZBOX_PASSWORD}" | perl -p -e 'use Encode qw/encode/; print encode("UTF-16LE","$_"); $_="";' | _digest md5 hex)"
  fi
  _fritzbox_sid="$(_get "${DEPLOY_FRITZBOX_URL}/login_sid.lua?sid=0000000000000000&username=${DEPLOY_FRITZBOX_USERNAME}&response=${_fritzbox_challenge}-${_fritzbox_hash}" | sed -e 's/^.*<SID>//' -e 's/<\/SID>.*$//')"

  if [ -z "${_fritzbox_sid}" ] || [ "${_fritzbox_sid}" = "0000000000000000" ]; then
    _err "Logging in to the FRITZ!Box failed. Please check username, password and URL."
    return 1
  fi

  _info "Generate form POST request"
  _post_request="$(_mktemp)"
  _post_boundary="---------------------------$(date +%Y%m%d%H%M%S)"
  # _CERTPASSWORD_ is unset because Let's Encrypt certificates don't have a password. But if they ever do, here's the place to use it!
  _CERTPASSWORD_=
  {
    printf -- "--"
    printf -- "%s\r\n" "${_post_boundary}"
    printf "Content-Disposition: form-data; name=\"sid\"\r\n\r\n%s\r\n" "${_fritzbox_sid}"
    printf -- "--"
    printf -- "%s\r\n" "${_post_boundary}"
    printf "Content-Disposition: form-data; name=\"BoxCertPassword\"\r\n\r\n%s\r\n" "${_CERTPASSWORD_}"
    printf -- "--"
    printf -- "%s\r\n" "${_post_boundary}"
    printf "Content-Disposition: form-data; name=\"BoxCertImportFile\"; filename=\"BoxCert.pem\"\r\n"
    printf "Content-Type: application/octet-stream\r\n\r\n"
    cat "${_ckey}" "${_cfullchain}"
    printf "\r\n"
    printf -- "--"
    printf -- "%s--" "${_post_boundary}"
  } >>"${_post_request}"

  _info "Upload certificate to the FRITZ!Box"

  export _H1="Content-type: multipart/form-data boundary=${_post_boundary}"
  _post "$(cat "${_post_request}")" "${DEPLOY_FRITZBOX_URL}/cgi-bin/firmwarecfg" | grep SSL

  retval=$?
  if [ $retval = 0 ]; then
    _info "Upload successful"
  else
    _err "Upload failed"
  fi
  rm "${_post_request}"

  return $retval
}
