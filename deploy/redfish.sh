#!/usr/bin/env sh

# Script to deploy certificates to compatible BMCs (baseboard management
# controllers) using the [Redfish API](https://www.dmtf.org/standards/redfish).
#
# Environment Variables:
#
# ```sh
# DEPLOY_REDFISH_HOST="ipmi.example.com"  # Required
# DEPLOY_REDFISH_USERNAME="Administrator" # Required
# DEPLOY_REDFISH_PASSWORD="superuser"     # Required
# # DEPLOY_REDFISH_USE_BASIC_AUTH=1
# # DEPLOY_REDFISH_RESTART_BMC=1
# # DEPLOY_REDFISH_MANAGER="/redfish/v1/Managers/Self"
# # DEPLOY_REDFISH_TARGET="/redfish/v1/CertificateService/Certificates/1"
# ```
#
# Compatibility:
#
# Compatible with any IPMI/BMC solution supporting Redfish v1.6.1 or newer (or
# Redfish Schema Bundle 2018.3), as defined in the following documents:
#
# <https://www.dmtf.org/sites/default/files/standards/documents/DSP0266_1.6.1.pdf>
# <https://www.dmtf.org/sites/default/files/standards/documents/DSP2046_2018.3.pdf>
# <https://www.dmtf.org/sites/default/files/standards/documents/DSP2059_1.0.0.pdf>
#
# This script is confirmed to work on the following systems:
#
# | IPMI Solution    | BMC Chipset    | Firmware Family  | Redfish Version |
# |------------------|----------------|------------------|-----------------|
# | ASUS ASMB12-iKVM | ASPEED AST2600 | AMI MegaRAC SP-X | 1.15.1          |
#
# However, this should also work with HPE iLO 5 v2.42 (or newer), Dell iDRAC9
# v5.0 (or newer), or any ASUS/Lenovo/Supermicro IPMI solution based on AMI
# MegaRAC SP-X v12.x (or newer).

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

  _redfish_load_deploy_conf DEPLOY_REDFISH_HOST
  _redfish_load_deploy_conf DEPLOY_REDFISH_USERNAME 'base64'
  _redfish_load_deploy_conf DEPLOY_REDFISH_PASSWORD 'base64'
  _redfish_load_deploy_conf DEPLOY_REDFISH_USE_BASIC_AUTH
  _redfish_load_deploy_conf DEPLOY_REDFISH_RESTART_BMC
  _redfish_load_deploy_conf DEPLOY_REDFISH_MANAGER
  _redfish_load_deploy_conf DEPLOY_REDFISH_TARGET

  if [ -z "${DEPLOY_REDFISH_HOST}" ]; then
    _err 'DEPLOY_REDFISH_HOST must be set. Please specify the IP or domain name of the Redfish server.'
    return 1
  fi

  if [ -z "${DEPLOY_REDFISH_USERNAME}" ] || [ -z "${DEPLOY_REDFISH_PASSWORD}" ]; then
    _err 'DEPLOY_REDFISH_USERNAME and DEPLOY_REDFISH_PASSWORD must be set.'
    return 1
  fi

  # Scoped to this hook's own subshell -- does not affect the rest of the
  # acme.sh run (e.g. the connection to the ACME CA).
  export HTTPS_INSECURE=1

  # 1. Authenticate with the Redfish server and store the auth header.

  if ! _redfish_log_in "$DEPLOY_REDFISH_USERNAME" "$DEPLOY_REDFISH_PASSWORD"; then
    return 1
  fi

  trap '_redfish_log_out "${_session:-}"' EXIT INT

  # 2. Verify Redfish server supports certificate management API.

  _redfish_rest GET '/redfish/v1/'
  _managers_path="$(echo "${_response}" | jq -r '.Managers.["@odata.id"]')"
  _certificate_service_path="$(echo "${_response}" | jq -r '.CertificateService.["@odata.id"]')"

  if [ -z "${_certificate_service_path}" ] || _contains "${_certificate_service_path}" 'null'; then
    _err "Redfish server ${DEPLOY_REDFISH_HOST} doesn't support certificate management API."
    return 1
  fi

  # 3. Verify supported key algorithms/lengths/curves and that key is compatible.

  if [ -n "${_ckey}" ]; then
    _debug 'Identifying compatibility of private key with Redfish server.'

    if _isRSA "${_ckey}"; then
      _key_algo='RSA'
    elif _isEcc "${_ckey}"; then
      _key_algo='ECDSA'
    else
      _err 'Private key uses unknown cryptographic algorithm!'
      return 1
    fi

    _redfish_rest GET "${_certificate_service_path}"
    _generate_csr_info_path="$(echo "${_response}" | jq -r '.Actions["#CertificateService.GenerateCSR"].["@Redfish.ActionInfo"]')"
    _redfish_rest GET "${_generate_csr_info_path}"
    _allowed_key_algos="$(echo "${_response}" | jq -r '.Parameters[] | select(.Name == "KeyPairAlgorithm") | .AllowableValues[]' | paste -sd ', ' -)"

    if [ -z "${_allowed_key_algos}" ]; then
      _allowed_key_algos='TCG_ALG_RSA'
    fi

    _debug _key_algo "${_key_algo}"
    _debug _allowed_key_algos "${_allowed_key_algos}"

    case "${_key_algo}:${_allowed_key_algos}" in
    RSA:*RSA*)
      _allowed_key_bit_lengths="$(echo "${_response}" | jq -cr '.Parameters[] | select(.Name == "KeyBitLength")')"
      _min_key_length="$(echo "${_allowed_key_bit_lengths}" | jq -r '.MinimumValue')"
      _min_key_length="$(echo "${_allowed_key_bit_lengths}" | jq -r '.MaximumValue')"
      _debug _allowed_key_bit_lengths "${_allowed_key_bit_lengths}"

      if ! expr "${_min_key_length}:${_min_key_length}" : '^[0-9]\{1,\}:[0-9]\{1,\}$' >/dev/null; then
        _err "Server supports RSA, but its minimum/maximum allowed key bit lengths could not be determined."
        return 1
      fi

      # shellcheck disable=SC2154 # Le_Keylength is set by acme.sh core, not this hook
      if [ "${Le_Keylength}" -le "${_min_key_length}" ] || [ "${Le_Keylength}" -gt "${_min_key_length}" ]; then
        _err "Unsupported RSA private key length ${Le_Keylength}!"
        _err "Please re-run acme.sh with --keylength set to a value between ${_max_key_len} and ${_min_key_len}."
        return 1
      fi
      ;;
    ECDSA:*ECDSA*)
      _allowed_key_curve_ids="$(echo "${_response}" | jq -r '.Parameters[] | select(.Name == "KeyCurveId") | .AllowableValues[]')"

      # shellcheck disable=SC2154 # Le_Keylength is set by acme.sh core, not this hook
      if ! _contains "${_allowed_key_curve_ids}" "${Le_Keylength}"; then
        _err "Unsupported ECDSA private key type! Supports only: ${_allowed_key_curve_ids}"
        return 1
      fi
      ;;
    *)
      _err "This Redfish server does not support ${_key_algo} private keys! Supports only: ${_allowed_key_algos}"
      return 1
      ;;
    esac
  else
    _info "Not checking cipher suite compatibility due to --sign-csr. Assuming correct private key is already on the server."
  fi

  # 4. Perform 3.3 of this PDF: https://www.dmtf.org/sites/default/files/standards/documents/DSP2059_1.2.0.pdf
  #    * When deploying, do it according to 2.2.1.1 "Web Service Certificates".
  #    * Since `acme.sh` is generating the certificate itself rather using the
  #      Redfish API to do so, append the private key (`_ckey`) to
  #      `_cfullchain` in 3.1.7 If `_ckey` is undefined, we must be in
  #      `--sign-csr` mode; assume the CSR was already generated on the Redfish
  #      host itself using the `GenerateCSR` API and simply send `_cfullchain`
  #      without `_ckey` (log it with a warning, though).

  _debug 'Identifying REST endpoint for primary TLS certificate.'

  if [ -n "${DEPLOY_REDFISH_MANAGER}" ]; then
    _manager_path="${DEPLOY_REDFISH_MANAGER}"
  else
    _redfish_rest GET "${_managers_path}"
    _num_managers="$(echo "${_response}" | jq -r '.["Members@odata.count"]')"

    if [ "${_num_managers}" != '1' ]; then
      _all_managers="$(echo "${_response}" | jq -c '[.Members[].["@odata.id"]]')"
      _err "Multiple Redfish managers identified (${_all_managers}), but expected exactly one."
      _err "Please specify the manager in DEPLOY_REDFISH_MANAGER."
      return 1
    fi

    _manager_path="$(echo "${_response}" | jq -r '.Members[0].["@odata.id"]')"
    _savedeployconf DEPLOY_REDFISH_MANAGER "${_manager_path}"
  fi

  if [ -n "${DEPLOY_REDFISH_TARGET}" ]; then
    _certificate_path="${DEPLOY_REDFISH_TARGET}"
  else
    _redfish_rest GET "${_manager_path}"
    _network_protocol_path="$(echo "${_response}" | jq -r '.NetworkProtocol.["@odata.id"]')"
    _redfish_rest GET "${_network_protocol_path}/HTTPS/Certificates"
    _num_certificates="$(echo "${_response}" | jq -r '.["Members@odata.count"]')"

    if [ "${_num_certificates}" != '1' ]; then
      _all_certificates="$(echo "${_response}" | jq -c '[.Members[].["@odata.id"]]')"
      _err "Multiple web service HTTPS certificates identified (${_all_certificates}), but expected exactly one."
      _err "Please specify the exact certificate destination in DEPLOY_REDFISH_TARGET."
      return 1
    fi

    _certificate_path="$(echo "${_response}" | jq -r '.Members[0].["@odata.id"]')"
    _savedeployconf DEPLOY_REDFISH_TARGET "${_certificate_path}"
  fi

  _info "Deploying TLS certificate to: ${_certificate_path}"
  _redfish_rest GET "${_certificate_path}"

  if [ -n "${_ckey}" ]; then
    _ckey_pkcs8="$(_mktemp)"

    if ! _toPkcs8 "${_ckey_pkcs8}" "${_ckey}"; then
      _err 'Failed to convert private key to PKCS#8 format!'
      return 1
    fi

    _info "Uploading private key and full certificate chain to Redfish server."
    _certificate_str="$(paste -sd '\n' "${_ckey_pkcs8}" "${_cfullchain}" | _json_encode)"
    _certificate_type="PEMchain"
  else
    _info "Uploading only certificate chain to Redfish server, due to --sign-csr."
    _certificate_str="$(_json_encode <"${_cfullchain}")"
    _certificate_type="PEM"
  fi

  _debug _certificate_path "${_certificate_path}"
  _debug _certificate_type "${_certificate_type}"
  _secure_debug _certificate_str "${_certificate_str}"

  _body="$(printf '{"CertificateString":"%s","CertificateType":"%s","CertificateUri":{"@odata.id":"%s"}}' "${_certificate_str}" "${_certificate_type}" "${_certificate_path}")"
  _redfish_rest POST "${_certificate_service_path}/Actions/CertificateService.ReplaceCertificate" "${_body}"
  _code="$(_redfish_response_code)"

  if [ "${_code}" != '204' ]; then
    _err "Failed to update Redfish server TLS certificate! Status code: ${_code}"
    _err "Response: ${_response}"
    return 1
  fi

  _info 'Successfully updated Redfish server TLS certificate!'

  if [ -n "${DEPLOY_REDFISH_RESTART_BMC}" ]; then
    _info 'Attempting to restart BMC gracefully.'

    _redfish_rest GET "${_manager_path}"
    _manager_reset_action_info="$(echo "${_response}" | jq -r '.Actions["#Manager.Reset"].["@Redfish.ActionInfo"]')"
    _redfish_rest GET "${_manager_reset_action_info}"

    if _contains "${_response}" 'GracefulRestart'; then
      _redfish_rest POST "${_manager_path}/Actions/Manager.Reset" '{"ResetType":"GracefulRestart"}'
      _code="$(_redfish_response_code)"

      if [ "${_code}" = '204' ]; then
        _info "Successfully sent graceful restart command to BMC. After restarting, the new TLS certificate will be active."
      else
        _err "Failed to gracefully restart BMC! Status code: ${_code}"
        _err "Response: ${_response}"
        return 1
      fi
    else
      _info "BMC doesn't support graceful restarts. Please wait up to 20 seconds to take effect, or restart the BMC manually."
    fi
  else
    _info 'Please wait up to 20 seconds to take effect, or restart the BMC manually.'
  fi

  return 0
}

_redfish_load_deploy_conf() {
  _var="$1"
  _encode_base64="${2:-}"

  if [ -n "$(eval echo "\$$_var")" ]; then
    _debug2 "Detected environment variable $_var, saving to file."
    _savedeployconf "$_var" "$(eval echo "\$$_var")" "${_encode_base64}"
  else
    _debug2 "Attempting to load variable $_var from file."
    _getdeployconf "$_var"
  fi

  if [ -n "${_encode_base64}" ]; then
    _secure_debug2 "$_var" "$(eval echo "\$$_var")"
  else
    _debug2 "$_var" "$(eval echo "\$$_var")"
  fi
}

_redfish_rest() {
  _method="$1"
  _endpoint="$2"
  _body="${3:-}"

  export _H1='OData-Version: 4.0'

  if [ "${_method}" = 'GET' ]; then
    _response="$(_get "https://${DEPLOY_REDFISH_HOST}${_endpoint}")"
    _ret="$?"
  else
    _response="$(_post "${_body}" "https://${DEPLOY_REDFISH_HOST}${_endpoint}" '' "${_method}" "${_body:+application/json}")"
    _ret="$?"
  fi

  if [ "${_ret}" != '0' ]; then
    _err "Error while calling ${_method} ${_endpoint}"
    return 1
  fi

  return "${_ret}"
}

_redfish_response_code() {
  _egrep_o <"${HTTP_HEADER}" '^HTTP[^ ]* [0-9]+' | _tail_n 1 | tr -d '\r\n' | cut -d ' ' -f 2
}

_redfish_log_in() {
  _username="$1"
  _password="$2"

  if ! _redfish_rest GET '/redfish/v1/'; then
    return 1
  fi

  if [ -n "${DEPLOY_REDFISH_USE_BASIC_AUTH:-}" ]; then
    _info "Authenticating with Redfish API (basic HTTP auth) on: ${DEPLOY_REDFISH_HOST}"
    _access_token="$(printf '%s:%s' "${_username}" "${_password}" | _base64)"
    export _H2="Authorization: Basic ${_access_token}"
  else
    _info "Authenticating with Redfish API: ${DEPLOY_REDFISH_HOST}"

    # Get sessions endpoint URI path
    _session_path="$(echo "${_response}" | jq -r '.Links.Sessions.["@odata.id"]')"

    # Create new session
    _body="$(jq -nc '{"UserName":$user,"Password":$pass}' --arg user "${_username}" --arg pass "${_password}")"
    if ! _redfish_rest POST "${_session_path}" "${_body}"; then
      return 1
    fi

    _code="$(_redfish_response_code)"

    # Verify authentication succeeded
    if [ "${_code}" != '201' ]; then
      _err "Redfish authentication failed (HTTP ${_code})"
      _err "Response: ${_response}"
      return 1
    fi

    _auth_token="$(grep -i '^X-Auth-Token: .*$' "${HTTP_HEADER}" | _tail_n 1 | tr -d ' \r\n' | cut -d ':' -f 2)"
    export _H2="X-Auth-Token: ${_auth_token}"

    _session="$(grep -i '^Location: .*$' "${HTTP_HEADER}" | _tail_n 1 | tr -d ' \r\n' | cut -d ':' -f 2)"
  fi
}

_redfish_log_out() {
  _session_path="${1:-}"

  _info "Logging out of Redfish session on: ${DEPLOY_REDFISH_HOST}"

  if [ -n "${_session_path}" ]; then
    _redfish_rest DELETE "${_session_path}"
    _code="$(_redfish_response_code)"

    if [ "${_code}" != '204' ]; then
      _err "Failed to log out of Redfish server (HTTP ${_code})."
      _err "Response: ${_response}"
    fi
  else
    _info 'Using basic HTTP auth, no need to log out of Redfish API.'
  fi

  export _H1=
  export _H2=
}
