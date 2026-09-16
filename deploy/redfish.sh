#!/usr/bin/env sh

# https://www.dmtf.org/sites/default/files/standards/documents/DSP0266_1.24.0.pdf
# https://www.dmtf.org/sites/default/files/standards/documents/DSP2059_1.2.0.pdf

########  Public functions #####################

#domain keyfile certfile cafile fullchain
redfish_deploy() {
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

  if ! _exists jq; then
    _err 'jq binary not found in PATH. Please install it using the system package manager.'
    return 1
  fi

  _getdeployconf DEPLOY_REDFISH_USERNAME
  _getdeployconf DEPLOY_REDFISH_PASSWORD

  # 1. Authenticate with the Redfish server and store the auth header.
  #    * Create new Redfish session token using the username/password provided.
  #    * Unless we have `DEPLOY_REDFISH_USE_BASIC_AUTH` defined, where we will
  #      authenticate via `Authorization: Basic $(_base64 "username:password")`.

  # Scoped to this hook's own subshell -- does not affect the rest of the
  # acme.sh run (e.g. the connection to the ACME CA).
  export HTTPS_INSECURE=1

  _redfish_authenticate "$DEPLOY_REDFISH_HOST" "$DEPLOY_REDFISH_USERNAME" "$DEPLOY_REDFISH_PASSWORD" ''
  trap '_redfish_end_session "$DEPLOY_REDFISH_HOST" "${_redfish_session:-}"' EXIT INT

  # 2. Verify Redfish server supports certificate management.

  _redfish_response="$(_get "https://${_redfish_host}/redfish/v1/")"
  _redfish_certificate_service_path="$(echo "${_redfish_response}" | jq -r '.CertificateService.["@odata.id"]')"

  if _contains "${_redfish_certificate_service_path}" 'null'; then
    _err "Redfish server doesn't support certificate management API. Exiting..."
    return 1
  fi

  # 3. Perform 3.3 of this PDF: https://www.dmtf.org/sites/default/files/standards/documents/DSP2059_1.2.0.pdf
  #    * When deploying, do it according to 2.2.1.1 "Web Service Certificates".
  #    * Since `acme.sh` is generating the certificate itself rather using the
  #      Redfish API to do so, append the private key (`_ckey`) to
  #      `_cfullchain` in 3.1.7 If `_ckey` is undefined, we must be in
  #      `--signcsr` mode; assume the CSR was already generated on the Redfish
  #      host itself using the `GenerateCSR` API and simply send `_cfullchain`
  #      without `_ckey` (log it with a warning, though).

  _redfish_managers_path="$(echo "${_redfish_response}" | jq -r '.Managers.["@odata.id"]')"
  _redfish_response="$(_get "https://${_redfish_host}${_redfish_managers_path}")"
  _redfish_num_managers="$(echo "${_redfish_response}" | jq -r '.["Members@odata.count"]')"

  _getdeployconf DEPLOY_REDFISH_MANAGER

  if [ -z "${DEPLOY_REDFISH_MANAGER}" ] && [ "${_redfish_num_managers}" != "1" ]; then
    if [ "${_redfish_num_managers}" = "0" ]; then
      _err "Unable to identify any Redfish managers."
    else
      _redfish_all_managers="$(echo "${_redfish_response}" | jq -c '[.Members[].["@odata.id"]]')"
      _err "Multiple Redfish managers identified (${_redfish_all_managers}). Please set exactly one in DEPLOY_REDFISH_MANAGER."
    fi
    return 1
  fi

  _redfish_manager_path="$(echo "${_redfish_response}" | jq -r '.Members[0].["@odata.id"]')"
  _redfish_response="$(_get "https://${_redfish_host}${_redfish_manager_path}")"
  _redfish_network_protocol_path="$(echo "${_redfish_response}" | jq -r '.NetworkProtocol.["@odata.id"]')"

  _redfish_response="$(_get "https://${_redfish_host}${_redfish_network_protocol_path}/HTTPS/Certificates")"
  _redfish_num_certificates="$(echo "${_redfish_response}" | jq -r '.["Members@odata.count"]')"

  if [ "${_redfish_num_certificates}" != "1" ]; then
    _redfish_all_managers="$(echo "${_redfish_response}" | jq -c '[.Members[].["@odata.id"]]')"
    _err "Multiple web service HTTPS certificates identified (${_redfish_all_managers}), but expected exactly one."
    return 1
  fi

  _redfish_certificate_path="$(echo "${_redfish_response}" | jq -r '.Members[0].["@odata.id"]')"
  _redfish_response="$(_get "https://${_redfish_host}${_redfish_certificate_path}")"

  if [ -n "${_ckey}" ]; then
    _redfish_ckey_pkcs8="$(_mktemp)"

    if ! "${ACME_OPENSSL_BIN:-openssl}" pkcs8 -topk8 -inform PEM -outform PEM -in "${_ckey}" -out "${_redfish_ckey_pkcs8}" -nocrypt; then
      _err 'Failed to convert private key to PKCS#8 format!'
      return 1
    fi

    _redfish_certificate_str="$(paste -sd '\n' "${_redfish_ckey_pkcs8}" "${_ccert}" "${_cfullchain}" | _json_encode)"
    _redfish_certificate_type="PEMchain"
  else
    _redfish_certificate_str="$(_json_encode <"${_cfullchain}")"
    _redfish_certificate_type="PEM"
  fi

  _redfish_body="$(printf '{"CertificateString":"%s","CertificateType":"%s","CertificateUri":{"@odata.id":"%s"}}' "${_redfish_certificate_str}" "${_redfish_certificate_type}" "${_redfish_certificate_path}")"
  _redfish_response="$(_post "${_redfish_body}" "https://${_redfish_host}${_redfish_certificate_service_path}/Actions/CertificateService.ReplaceCertificate" '' 'POST' 'application/json')"
  _debug2 _redfish_response "$(echo "${_redfish_response}" | jq -sRr .)"
}

_redfish_authenticate() {
  _redfish_host="$1"
  _redfish_username="$2"
  _redfish_password="$3"
  _redfish_use_basic_auth="${4:-}"

  export _H1='OData-Version: 4.0'

  if [ -n "${_redfish_use_basic_auth}" ]; then
    _redfish_access_token="$(printf '%s:%s' "${_redfish_username}" "${_redfish_password}" | _base64)"
    export _H2="Authorization: Basic ${_redfish_access_token}"
  else
    # Get sessions endpoint URI path
    _redfish_response="$(_get "https://${_redfish_host}/redfish/v1/")"
    _redfish_session_path="$(echo "${_redfish_response}" | jq -r '.Links.Sessions.["@odata.id"]')"
    _debug2 _redfish_response "${_redfish_response}"

    # Create new session
    _redfish_body="$(jq -n '{"UserName":$user,"Password":$pass}' --arg user "${_redfish_username}" --arg pass "${_redfish_password}" | _normalizeJson)"
    _redfish_response="$(_post "${_redfish_body}" "https://${_redfish_host}${_redfish_session_path}" '' 'POST' 'application/json')"
    _redfish_session="$(grep -i '^Location: .*$' "${HTTP_HEADER}" | _tail_n 1 | tr -d ' \r\n' | cut -d ':' -f 2)"
    _redfish_auth_token="$(grep -i '^X-Auth-Token: .*$' "${HTTP_HEADER}" | _tail_n 1 | tr -d ' \r\n' | cut -d ':' -f 2)"
    export _H2="X-Auth-Token: ${_redfish_auth_token}"

    # Verify authentication succeeded
    if ! _contains "${_redfish_response}" "\"${_redfish_session}\""; then
      _err "Active Redfish session \"${_redfish_session}\" not found"
      return 1
    fi
  fi
}

_redfish_end_session() {
  _redfish_host="$1"
  _redfish_session_path="${2:-}"

  _info 'Ending active Redfish session'

  if [ -n "${_redfish_session_path}" ]; then
    _redfish_response="$(_post '' "https://${_redfish_host}${_redfish_session_path}" '' 'DELETE')"
    _code="$(_egrep_o <"${HTTP_HEADER}" '^HTTP[^ ]* [0-9]+' | _tail_n 1 | tr -d '\r\n' | cut -d ' ' -f 2)"

    if [ "${_code}" != "204" ]; then
      _err "Failed to end Redfish session! Status code: ${_code}"
      _debug2 _redfish_response "${_redfish_response}"
    fi
  else
    _info 'Using basic HTTP auth, no need to sign out.'
  fi

  export _H1=
  export _H2=
}
