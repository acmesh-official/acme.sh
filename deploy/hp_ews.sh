#!/usr/bin/env sh

# Here is a script to deploy cert to an HP printer's Embedded Web Server (EWS).
#
# Docs: https://github.com/acmesh-official/acme.sh/wiki/deployhooks#47-deploy-the-certificate-to-an-hp-printer-ews
#
# Tested on an HP Color LaserJet Pro MFP M479fdw, firmware
# CLRWTRXXXN002.2539E.00. It should work on any modern HP printer whose EWS
# exposes the "Install Certificate" flow at
# /Security/DeviceCertificates/NewCertWithPassword/Upload -- that endpoint
# takes a password-protected PKCS#12 bundle, which this hook builds from the
# issued certificate, its key and the CA chain.
#
# ```sh
# export HP_EWS_PASSWORD=mysecret
# export HP_EWS_INSECURE=1          # needed until the printer serves a trusted cert
# acme.sh --deploy -d printer.example.com --deploy-hook hp_ews
# ```
#
# Environment variables:
#   HP_EWS_PASSWORD      (required)  EWS administrator password.
#   HP_EWS_HOST          (optional)  IP or hostname of the printer.
#                                    Default: the certificate's domain.
#   HP_EWS_USERNAME      (optional)  EWS administrator user. Default: admin
#   HP_EWS_PFX_PASSWORD  (optional)  Password for the generated PKCS#12
#                                    bundle. A random one is used per run if
#                                    unset; set it only if you want the
#                                    bundle to be reproducible.
#   HP_EWS_INSECURE      (optional)  Set to a non-empty value to skip TLS
#                                    verification when talking to the
#                                    printer. Needed on the first deploy,
#                                    because the printer still serves its
#                                    self-signed certificate at that point.
#                                    acme.sh's global HTTPS_INSECURE is
#                                    honoured as well.
#
# Requires openssl, to build the PKCS#12 bundle.
#
# returns 0 means success, otherwise error.

########  Public functions #####################

#domain keyfile certfile cafile fullchain pfx
hp_ews_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  _cpfx="$6"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _debug _cpfx "$_cpfx"

  _getdeployconf HP_EWS_HOST
  _getdeployconf HP_EWS_USERNAME
  _getdeployconf HP_EWS_PASSWORD
  _getdeployconf HP_EWS_PFX_PASSWORD
  _getdeployconf HP_EWS_INSECURE

  HP_EWS_HOST="${HP_EWS_HOST:-$_cdomain}"
  HP_EWS_USERNAME="${HP_EWS_USERNAME:-admin}"

  _debug HP_EWS_HOST "$HP_EWS_HOST"
  _debug HP_EWS_USERNAME "$HP_EWS_USERNAME"
  _secure_debug HP_EWS_PASSWORD "$HP_EWS_PASSWORD"
  _secure_debug HP_EWS_PFX_PASSWORD "$HP_EWS_PFX_PASSWORD"
  _debug HP_EWS_INSECURE "$HP_EWS_INSECURE"

  if [ -z "$HP_EWS_PASSWORD" ]; then
    _err "HP_EWS_PASSWORD is required. Please set the password of the printer's EWS administrator account."
    return 1
  fi

  _savedeployconf HP_EWS_HOST "$HP_EWS_HOST"
  _savedeployconf HP_EWS_USERNAME "$HP_EWS_USERNAME"
  _savedeployconf HP_EWS_PASSWORD "$HP_EWS_PASSWORD" "base64"
  _savedeployconf HP_EWS_PFX_PASSWORD "$HP_EWS_PFX_PASSWORD" "base64"
  _savedeployconf HP_EWS_INSECURE "$HP_EWS_INSECURE"

  if ! _exists "${ACME_OPENSSL_BIN:-openssl}"; then
    _err "openssl is required by this deploy hook, but was not found."
    return 1
  fi

  # The bundle password only has to survive the single upload below, so a
  # fresh random one is used unless the operator asked for a fixed value.
  _HP_EWS_PFXPW="$HP_EWS_PFX_PASSWORD"
  if [ -z "$_HP_EWS_PFXPW" ]; then
    _HP_EWS_PFXPW="$(${ACME_OPENSSL_BIN:-openssl} rand -hex 24)"
    if [ -z "$_HP_EWS_PFXPW" ]; then
      _err "Could not generate a random password for the PKCS#12 bundle."
      return 1
    fi
  fi
  export _HP_EWS_PFXPW

  # $6 is only materialised when Le_PFXPassword is set for this domain, and
  # it would be built without the CA chain, so build our own bundle instead.
  _hp_ews_pfx="$(_mktemp)"
  _hp_ews_body="$(_mktemp)"
  if [ -z "$_hp_ews_pfx" ] || [ -z "$_hp_ews_body" ]; then
    _err "Could not create the temporary files needed for the upload."
    _hp_ews_cleanup
    return 1
  fi

  _hp_ews_ret=0
  if ! _hp_ews_make_pfx; then
    _hp_ews_ret=1
  elif ! _hp_ews_upload; then
    _hp_ews_ret=1
  fi

  _hp_ews_cleanup

  return "$_hp_ews_ret"
}

####################  Private functions below ##################################

_hp_ews_cleanup() {
  [ -n "$_hp_ews_pfx" ] && rm -f "$_hp_ews_pfx"
  [ -n "$_hp_ews_body" ] && rm -f "$_hp_ews_body"
  unset _HP_EWS_PFXPW
  # Do not leak the request header into any hook that runs after this one.
  export _H1=""
  return 0
}

# Bundle key, certificate and chain into $_hp_ews_pfx, protected by
# $_HP_EWS_PFXPW. The password goes through the environment rather than the
# command line so that it does not show up in ps output.
_hp_ews_make_pfx() {
  _info "Building the PKCS#12 bundle"

  if ! ${ACME_OPENSSL_BIN:-openssl} pkcs12 -export \
    -out "$_hp_ews_pfx" \
    -inkey "$_ckey" \
    -in "$_ccert" \
    -certfile "$_cca" \
    -passout env:_HP_EWS_PFXPW; then
    _err "Failed to build the PKCS#12 bundle."
    return 1
  fi

  if [ ! -s "$_hp_ews_pfx" ]; then
    _err "The PKCS#12 bundle is empty."
    return 1
  fi

  return 0
}

# Build the multipart body in $_hp_ews_body and POST it to the printer.
_hp_ews_upload() {
  _hp_ews_url="https://${HP_EWS_HOST}/Security/DeviceCertificates/NewCertWithPassword/Upload"
  _hp_ews_boundary="----------------------------acmesh$(${ACME_OPENSSL_BIN:-openssl} rand -hex 16)"

  {
    printf -- "--%s\r\n" "$_hp_ews_boundary"
    printf "Content-Disposition: form-data; name=\"certificate\"; filename=\"%s.pfx\"\r\n" "$_cdomain"
    printf "Content-Type: application/x-pkcs12\r\n\r\n"
    cat "$_hp_ews_pfx"
    printf "\r\n"
    printf -- "--%s\r\n" "$_hp_ews_boundary"
    printf "Content-Disposition: form-data; name=\"password\"\r\n\r\n%s\r\n" "$_HP_EWS_PFXPW"
    printf -- "--%s--\r\n" "$_hp_ews_boundary"
  } >"$_hp_ews_body"

  export _H1="Content-Type: multipart/form-data; boundary=$_hp_ews_boundary"

  _info "Uploading the certificate to $_hp_ews_url"
  _hp_ews_post "$_hp_ews_body" "$_hp_ews_url" || return 1

  # The EWS answers 201 Created on a successful install.
  _hp_ews_code="$(_hp_ews_status)"
  _debug _hp_ews_code "$_hp_ews_code"

  if [ "$_hp_ews_code" != "201" ] && [ "$_hp_ews_code" != "200" ]; then
    _err "The printer rejected the certificate (HTTP $_hp_ews_code)."
    if [ "$_hp_ews_code" = "401" ] || [ "$_hp_ews_code" = "403" ]; then
      _err "Check HP_EWS_USERNAME and HP_EWS_PASSWORD. If they are correct, the printer may"
      _err "be asking for an authentication scheme that could not be negotiated; re-run with"
      _err "--debug 2 and check the WWW-Authenticate header in the response."
    fi
    return 1
  fi

  _info "Certificate installed (HTTP $_hp_ews_code). The printer restarts its web server shortly."
  return 0
}

# The final response status recorded in $HTTP_HEADER by _hp_ews_post.
_hp_ews_status() {
  grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n"
}

# POST a body file. The body holds a binary PKCS#12, which cannot survive a
# shell variable, so it is passed by filename -- curl reads it with
# --data-binary @ and wget with --post-file. Modelled on
# deploy/zyxel_gs1900.sh's _zyxel_upload_pkcs12, and built on $_ACME_CURL /
# $_ACME_WGET so that acme.sh's own CA_PATH/CA_BUNDLE, IPv4/IPv6 and debug
# settings still apply.
#
# Usage: _hp_ews_post [body file name] [url]
_hp_ews_post() {
  _hp_ews_bodyfile="$1"
  _hp_ews_posturl="$2"

  _debug2 "_hp_ews_bodyfile" "$_hp_ews_bodyfile"
  _debug "_hp_ews_posturl" "$_hp_ews_posturl"

  _inithttp

  if [ "$_ACME_CURL" ] && [ "${ACME_USE_WGET:-0}" = "0" ]; then
    _CURL="$_ACME_CURL"
    if [ "$HTTPS_INSECURE" ] || [ "$HP_EWS_INSECURE" ]; then
      _CURL="$_CURL --insecure  "
    fi
    _debug "_CURL" "$_CURL"

    # --anyauth so that either a Basic or a Digest challenge is satisfied.
    response="$($_CURL --user-agent "$USER_AGENT" -X POST --anyauth -u "$HP_EWS_USERNAME:$HP_EWS_PASSWORD" -H "$_H1" -H "$_H2" -H "$_H3" -H "$_H4" -H "$_H5" --data-binary "@${_hp_ews_bodyfile}" "$_hp_ews_posturl")"
    _ret="$?"

    if [ "$_ret" != "0" ]; then
      _err "Please refer to https://curl.haxx.se/libcurl/c/libcurl-errors.html for error code: $_ret"
      if [ "$_ret" = "60" ]; then
        _err "The printer's current certificate could not be verified. This is expected before the first successful deploy -- set HP_EWS_INSECURE=1 and try again."
      fi
      if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ]; then
        _err "Here is the curl dump log:"
        _err "$(cat "$_CURL_DUMP")"
      fi
    fi
  elif [ "$_ACME_WGET" ]; then
    _WGET="$_ACME_WGET"
    if [ "$HTTPS_INSECURE" ] || [ "$HP_EWS_INSECURE" ]; then
      _WGET="$_WGET --no-check-certificate "
    fi
    _debug "_WGET" "$_WGET"

    # wget negotiates Basic or Digest from the challenge on its own. Deliberately
    # no --auth-no-challenge, which would force preemptive Basic and rule out Digest.
    response="$($_WGET -S -O - --user-agent="$USER_AGENT" --http-user="$HP_EWS_USERNAME" --http-password="$HP_EWS_PASSWORD" --header "$_H5" --header "$_H4" --header "$_H3" --header "$_H2" --header "$_H1" --post-file="${_hp_ews_bodyfile}" "$_hp_ews_posturl" 2>"$HTTP_HEADER")"
    _ret="$?"

    if [ "$_ret" = "8" ]; then
      _ret=0
      _debug "wget returned 8 as the server returned a non-2xx response. Let's process the response later."
    fi
    if [ "$_ret" != "0" ]; then
      _err "Please refer to https://www.gnu.org/software/wget/manual/html_node/Exit-Status.html for error code: $_ret"
    fi
    if _contains "$_WGET" " -d "; then
      # Demultiplex wget debug output
      cat "$HTTP_HEADER" >&2
      _sed_i '/^[^ ][^ ]/d; /^ *$/d' "$HTTP_HEADER"
    fi
    # remove leading whitespaces from header to match curl format
    _sed_i 's/^  //g' "$HTTP_HEADER"
  else
    _err "Neither curl nor wget have been found, cannot make the POST request."
    return 1
  fi

  _debug "_ret" "$_ret"
  _debug2 "response" "$response"
  return "$_ret"
}
