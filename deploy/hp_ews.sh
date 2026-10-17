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
# The hook authenticates with HTTP Basic auth. Printers whose EWS only offers
# Digest auth are not supported.
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

  export _H1="Authorization: Basic $(printf "%s:%s" "$HP_EWS_USERNAME" "$HP_EWS_PASSWORD" | _base64)"
  if [ "$HP_EWS_INSECURE" ]; then
    export HTTPS_INSECURE=1
  fi

  _info "Uploading the certificate to $_hp_ews_url"
  if ! _post_file "$_hp_ews_body" "$_hp_ews_url" "" "POST" "multipart/form-data; boundary=$_hp_ews_boundary" >/dev/null; then
    if [ -z "$HTTPS_INSECURE" ]; then
      _err "If the printer still serves its self-signed certificate, set HP_EWS_INSECURE=1 and try again."
    fi
    return 1
  fi

  # The EWS answers 201 Created on a successful install.
  _hp_ews_code="$(grep "^HTTP" "$HTTP_HEADER" | _tail_n 1 | cut -d " " -f 2 | tr -d "\r\n")"
  _debug _hp_ews_code "$_hp_ews_code"

  if [ "$_hp_ews_code" != "201" ] && [ "$_hp_ews_code" != "200" ]; then
    _err "The printer rejected the certificate (HTTP $_hp_ews_code)."
    if [ "$_hp_ews_code" = "401" ] || [ "$_hp_ews_code" = "403" ]; then
      _err "Check HP_EWS_USERNAME and HP_EWS_PASSWORD. Only HTTP Basic authentication is"
      _err "supported; printers that only offer Digest cannot be used with this hook."
    fi
    return 1
  fi

  _info "Certificate installed (HTTP $_hp_ews_code). The printer restarts its web server shortly."
  return 0
}
