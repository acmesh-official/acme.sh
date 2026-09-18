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

  _redfish_log_in "$DEPLOY_REDFISH_HOST" "$DEPLOY_REDFISH_USERNAME" "$DEPLOY_REDFISH_PASSWORD" "$DEPLOY_REDFISH_USE_BASIC_AUTH"
  trap '_redfish_log_out "$DEPLOY_REDFISH_HOST" "${_session:-}"' EXIT INT

  # 2. Verify Redfish server supports certificate management API.

  _response="$(_get "https://${_host}/redfish/v1/")"
  _managers_path="$(echo "${_response}" | jq -r '.Managers.["@odata.id"]')"
  _certificate_service_path="$(echo "${_response}" | jq -r '.CertificateService.["@odata.id"]')"

  if _contains "${_certificate_service_path}" 'null'; then
    _err "Redfish server ${_host} doesn't support certificate management API."
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

    _response="$(_get "https://${_host}${_certificate_service_path}")"
    _generate_csr_info_path="$(echo "${_response}" | jq -r '.Actions["#CertificateService.GenerateCSR"].["@Redfish.ActionInfo"]')"
    _response="$(_get "https://${_host}${_generate_csr_info_path}")"
    _allowed_key_algos="$(echo "${_response}" | jq -r '.Parameters[] | select(.Name == "KeyPairAlgorithm") | .AllowableValues[]' | paste -sd ', ' -)"

    if [ -z "${_allowed_key_algos}" ]; then
      _allowed_key_algos='TCG_ALG_RSA'
    fi

    _debug _key_algo "${_key_algo}"
    _debug _allowed_key_algos "${_allowed_key_algos}"

    case "${_key_algo}:${_allowed_key_algos}" in
    RSA:*RSA*)
      _allowed_key_bit_lengths="$(echo "${_response}" | jq -r '.Parameters[] | select(.Name == "KeyBitLength")')"
      _key_bits_min="$(echo "${_allowed_key_bit_lengths}" | jq -r '.MinimumValue')"
      _key_bits_max="$(echo "${_allowed_key_bit_lengths}" | jq -r '.MaximumValue')"

      # shellcheck disable=SC2154 # Le_Keylength is set by acme.sh core, not this hook
      if [ "${Le_Keylength}" -le "${_key_bits_min}" ] || [ "${Le_Keylength}" -gt "${_key_bits_max}" ]; then
        _err "Unsupported RSA private key length ${Le_Keylength}!"
        _err "Please re-run acme.sh with --keylength set to a value between ${_allowed_key_bit_length_max} and ${_allowed_key_bit_length_min}."
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
    _info "Not checking cipher suite compatibility with ${_host}, due to --sign-csr. Assuming correct private key is already on the server."
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
    _response="$(_get "https://${_host}${_managers_path}")"
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
    _response="$(_get "https://${_host}${_manager_path}")"
    _network_protocol_path="$(echo "${_response}" | jq -r '.NetworkProtocol.["@odata.id"]')"
    _response="$(_get "https://${_host}${_network_protocol_path}/HTTPS/Certificates")"
    _num_certificates="$(echo "${_response}" | jq -r '.["Members@odata.count"]')"

    if [ "${_num_certificates}" != '1' ]; then
      _all_managers="$(echo "${_response}" | jq -c '[.Members[].["@odata.id"]]')"
      _err "Multiple web service HTTPS certificates identified (${_all_managers}), but expected exactly one."
      _err "Please specify the exact certificate destination in DEPLOY_REDFISH_TARGET."
      return 1
    fi

    _certificate_path="$(echo "${_response}" | jq -r '.Members[0].["@odata.id"]')"
    _savedeployconf DEPLOY_REDFISH_TARGET "${_certificate_path}"
  fi

  _info "Deploying TLS certificate to ${_certificate_path}."
  _response="$(_get "https://${_host}${_certificate_path}")"

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
  _response="$(_post "${_body}" "https://${_host}${_certificate_service_path}/Actions/CertificateService.ReplaceCertificate" '' 'POST' 'application/json')"
  _code="$(_egrep_o <"${HTTP_HEADER}" '^HTTP[^ ]* [0-9]+' | _tail_n 1 | tr -d '\r\n' | cut -d ' ' -f 2)"

  if [ "${_code}" != '204' ]; then
    _err "Failed to update Redfish server TLS certificate! Status code: ${_code}"
    _err "Response: ${_response}"
    return 1
  fi

  _info 'Successfully updated Redfish server TLS certificate!'

  if [ -n "${DEPLOY_REDFISH_RESTART_BMC}" ]; then
    _info 'Attempting to restart BMC gracefully.'

    _response="$(_get "https://${_host}${_manager_path}")"
    _manager_reset_action_info="$(echo "${_response}" | jq -r '.Actions["#Manager.Reset"].["@Redfish.ActionInfo"]')"
    _response="$(_get "https://${_host}${_manager_reset_action_info}")"

    if _contains "${_response}" 'GracefulRestart'; then
      _response="$(_post '{"ResetType":"GracefulRestart"}' "https://${_host}${_manager_path}/Actions/Manager.Reset" '' 'POST' 'application/json')"
      _code="$(_egrep_o <"${HTTP_HEADER}" '^HTTP[^ ]* [0-9]+' | _tail_n 1 | tr -d '\r\n' | cut -d ' ' -f 2)"

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

_redfish_log_in() {
  _host="$1"
  _username="$2"
  _password="$3"
  _use_basic_auth="${4:-}"

  export _H1='OData-Version: 4.0'

  if [ -n "${_use_basic_auth}" ]; then
    _info "Authenticating with Redfish API on ${_host} (basic HTTP auth)."
    _access_token="$(printf '%s:%s' "${_username}" "${_password}" | _base64)"
    export _H2="Authorization: Basic ${_access_token}"
  else
    _info "Authenticating with Redfish API on ${_host}."

    # Get sessions endpoint URI path
    _response="$(_get "https://${_host}/redfish/v1/")"
    _session_path="$(echo "${_response}" | jq -r '.Links.Sessions.["@odata.id"]')"

    # Create new session
    _body="$(jq -n '{"UserName":$user,"Password":$pass}' --arg user "${_username}" --arg pass "${_password}" | _normalizeJson)"
    _response="$(_post "${_body}" "https://${_host}${_session_path}" '' 'POST' 'application/json')"
    _code="$(_egrep_o <"${HTTP_HEADER}" '^HTTP[^ ]* [0-9]+' | _tail_n 1 | tr -d '\r\n' | cut -d ' ' -f 2)"

    # Verify authentication succeeded
    if [ "${_code}" != '201' ]; then
      _err "Redfish authentication failed (HTTP ${_code})"
      _err "Response: ${_response}"
      return 1
    fi

    _session="$(grep -i '^Location: .*$' "${HTTP_HEADER}" | _tail_n 1 | tr -d ' \r\n' | cut -d ':' -f 2)"
    _auth_token="$(grep -i '^X-Auth-Token: .*$' "${HTTP_HEADER}" | _tail_n 1 | tr -d ' \r\n' | cut -d ':' -f 2)"
    export _H2="X-Auth-Token: ${_auth_token}"
  fi
}

_redfish_log_out() {
  _host="$1"
  _session_path="${2:-}"

  _info "Ending active Redfish session on ${_host}."

  if [ -n "${_session_path}" ]; then
    _response="$(_post '' "https://${_host}${_session_path}" '' 'DELETE')"
    _code="$(_egrep_o <"${HTTP_HEADER}" '^HTTP[^ ]* [0-9]+' | _tail_n 1 | tr -d '\r\n' | cut -d ' ' -f 2)"

    if [ "${_code}" != '204' ]; then
      _err "Failed to log out of Redfish server (HTTP ${_code})."
      _err "Response: ${_response}"
    fi
  else
    _info 'Using basic HTTP auth, no need to sign out of Redfish API.'
  fi

  export _H1=
  export _H2=
}
