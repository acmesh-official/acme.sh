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
# DEPLOY_REDFISH_USE_BASIC_AUTH=0         # Optional (set to "1" to enable)
# DEPLOY_REDFISH_RESTART=0                # Optional (set to "1" to enable)
# DEPLOY_REDFISH_MANAGER=                 # Optional (e.g. "/redfish/v1/Managers/Self")
# DEPLOY_REDFISH_CERTIFICATE=             # Optional (e.g. "/redfish/v1/CertificateService/Certificates/1")
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

  _getdeployconf DEPLOY_REDFISH_HOST
  _getdeployconf DEPLOY_REDFISH_USERNAME
  _getdeployconf DEPLOY_REDFISH_PASSWORD
  _getdeployconf DEPLOY_REDFISH_USE_BASIC_AUTH
  _getdeployconf DEPLOY_REDFISH_RESTART
  _getdeployconf DEPLOY_REDFISH_MANAGER
  _getdeployconf DEPLOY_REDFISH_CERTIFICATE

  if [ -z "${DEPLOY_REDFISH_HOST}" ]; then
    _err 'DEPLOY_REDFISH_HOST must be set. Please specify the IP or domain name of the Redfish server.'
    return 1
  fi

  if [ -z "${DEPLOY_REDFISH_USERNAME}" ] || [ -z "${DEPLOY_REDFISH_PASSWORD}" ]; then
    _err 'DEPLOY_REDFISH_USERNAME and DEPLOY_REDFISH_PASSWORD must be set.'
    return 1
  fi

  DEPLOY_REDFISH_USE_BASIC_AUTH="${DEPLOY_REDFISH_USE_BASIC_AUTH:-0}"
  DEPLOY_REDFISH_RESTART="${DEPLOY_REDFISH_RESTART:-0}"

  _debug DEPLOY_REDFISH_HOST "${DEPLOY_REDFISH_HOST}"
  _debug DEPLOY_REDFISH_USERNAME "${DEPLOY_REDFISH_USERNAME}"
  _secure_debug DEPLOY_REDFISH_PASSWORD "${DEPLOY_REDFISH_PASSWORD}"
  _debug DEPLOY_REDFISH_USE_BASIC_AUTH "${DEPLOY_REDFISH_USE_BASIC_AUTH}"

  _redfish_log_in "$DEPLOY_REDFISH_USERNAME" "$DEPLOY_REDFISH_PASSWORD" || return 1

  # Credentials are proven correct now -- save them, rather than only at the
  # very end, so a later step failing doesn't discard a working login.
  _savedeployconf DEPLOY_REDFISH_HOST "${DEPLOY_REDFISH_HOST}"
  _savedeployconf DEPLOY_REDFISH_USERNAME "${DEPLOY_REDFISH_USERNAME}"
  _savedeployconf DEPLOY_REDFISH_PASSWORD "${DEPLOY_REDFISH_PASSWORD}" 'base64'
  _savedeployconf DEPLOY_REDFISH_USE_BASIC_AUTH "${DEPLOY_REDFISH_USE_BASIC_AUTH}"

  if ! _redfish_get_certificate_service_endpoint; then
    _err "Redfish server ${DEPLOY_REDFISH_HOST} doesn't support certificate management API."
    return 1
  fi

  _debug DEPLOY_REDFISH_RESTART "${DEPLOY_REDFISH_RESTART}"
  _debug DEPLOY_REDFISH_MANAGER "${DEPLOY_REDFISH_MANAGER}"
  _debug DEPLOY_REDFISH_CERTIFICATE "${DEPLOY_REDFISH_CERTIFICATE}"

  if [ -n "${DEPLOY_REDFISH_MANAGER}" ]; then
    _manager_endpoint="${DEPLOY_REDFISH_MANAGER}"
  else
    _info 'Identifying REST endpoint of primary Redfish manager.'
    _redfish_get_primary_manager_endpoint || return 1
    _savedeployconf DEPLOY_REDFISH_MANAGER "${_manager_endpoint}"
  fi

  if [ -n "${DEPLOY_REDFISH_CERTIFICATE}" ]; then
    _certificate_endpoint="${DEPLOY_REDFISH_CERTIFICATE}"
  else
    _info "Identifying REST endpoint of primary TLS certificate on: ${_manager_endpoint}"
    _redfish_get_manager_certificate_endpoint "${_manager_endpoint}" || return 1
  fi

  if [ -f "${_ckey}" ] && [ -f "${_cfullchain}" ]; then
    _info "Uploading private key and full certificate chain to: ${_certificate_endpoint}"

    if ! _redfish_supports_full_certificate_chains; then
      _err 'Redfish server does not support uploading full certificate chains!'
      _err "Please call 'GenerateCSR' API on server first, pass the CSR to 'acme.sh --sign-csr --csr <key.pem>', and try again."
      return 1
    elif ! _redfish_supports_private_key "${_ckey}" "${_certificate_service_endpoint}"; then
      _err "Redfish server does not support this type of private key."
      return 1
    fi

    _ckey_pkcs8="$("${ACME_OPENSSL_BIN:-openssl}" pkcs8 -topk8 -nocrypt -in "${_ckey}")"

    # shellcheck disable=SC2181
    if [ "$?" != '0' ] || [ -z "${_ckey_pkcs8}" ]; then
      _err 'Failed to convert private key to PKCS#8 format!'
      return 1
    fi

    _certificate_str="$({
      printf '%s\n' "${_ckey_pkcs8}"
      cat "${_cfullchain}"
    } | _json_encode)"
    _certificate_type='PEMchain'
  else
    _info "Private key and full certificate chain not available; we must be using a server-generated CSR."
    _info "Uploading only leaf certificate to: ${_certificate_endpoint}"

    _certificate_str="$(_json_encode <"${_ccert}")"
    _certificate_type='PEM'
  fi

  _body="$(printf '{"CertificateString":"%s","CertificateType":"%s","CertificateUri":{"@odata.id":"%s"}}' "${_certificate_str}" "${_certificate_type}" "${_certificate_endpoint}")"
  _redfish_rest POST "${_certificate_service_endpoint}/Actions/CertificateService.ReplaceCertificate" "${_body}" || return 1
  _code="$(_redfish_response_code)"

  if ! _startswith "${_code}" '2'; then
    _err "Failed to update Redfish server TLS certificate! (HTTP ${_code})"
    _err "Response: ${_response}"
    return 1
  fi

  _info 'Successfully updated Redfish server TLS certificate!'
  _savedeployconf DEPLOY_REDFISH_CERTIFICATE "${_certificate_endpoint}"

  if [ "${DEPLOY_REDFISH_RESTART}" = '1' ]; then
    _info 'Attempting to restart BMC gracefully.'
    _redfish_attempt_graceful_restart "${_manager_endpoint}" || return 0
    _info 'Successfully sent graceful restart command to BMC. After restarting, the new TLS certificate will be active.'
  else
    _info 'Please wait up to 20 seconds to take effect, or restart the BMC manually.'
  fi

  _savedeployconf DEPLOY_REDFISH_RESTART "${DEPLOY_REDFISH_RESTART}"

  return 0
}

_redfish_rest() {
  _method="$1"
  _endpoint="$2"
  _body="${3:-}"

  export _H1='OData-Version: 4.0'

  if [ "${_method}" = 'GET' ]; then
    _response="$(_get "https://${DEPLOY_REDFISH_HOST}${_endpoint}" | _normalizeJson)"
  else
    _response="$(_post "${_body}" "https://${DEPLOY_REDFISH_HOST}${_endpoint}" '' "${_method}" "${_body:+application/json}" | _normalizeJson)"
  fi

  _ret="$?"

  if [ "${_ret}" != '0' ]; then
    _err "Error while calling ${_method} ${_endpoint}. Deploy with --insecure if current certificate is invalid. Try deploying with --debug to troubleshoot."
  fi

  return "${_ret}"
}

_redfish_response_code() {
  _egrep_o <"${HTTP_HEADER}" '^HTTP[^ ]* [0-9]+' | _tail_n 1 | tr -d '\r\n' | cut -d ' ' -f 2
}

_redfish_get_odata_id() {
  _regex='s/{'
  for key in $(echo "$1" | tr '.' '\n'); do
    _regex="${_regex}.*\"${key}\":{"
  done
  sed -n "${_regex}[^}]*\"@odata\\.id\":\"\\([^\"]*\\)\".*/\\1/p"
}

_redfish_get_odata_members() {
  sed -n 's/.*"Members":\[\([^]]*\)\].*/\1/p' | sed 's/,/\n/g' | sed -n 's/.*{"@odata\.id":"\([^"]*\)"}.*/\1/p'
}

_redfish_get_odata_count() {
  sed -n 's/.*"Members@odata\.count":[[:space:]]*\([0-9][0-9]*\).*/\1/p'
}

_redfish_log_in() {
  _username="$1"
  _password="$2"

  _redfish_rest GET '/redfish/v1/' || return 1
  _info "Authenticating with Redfish API: ${DEPLOY_REDFISH_HOST}"

  if [ "${DEPLOY_REDFISH_USE_BASIC_AUTH}" = '1' ]; then
    _access_token="$(printf '%s:%s' "${_username}" "${_password}" | _base64)"
    export _H2="Authorization: Basic ${_access_token}"

    # Verify credentials are valid
    _account_service_endpoint="$(echo "${_response}" | _redfish_get_odata_id 'AccountService')"
    _redfish_rest GET "${_account_service_endpoint}" || return 1
    _code="$(_redfish_response_code)"

    if [ "${_code}" != '200' ]; then
      _err "Redfish authentication failed (HTTP ${_code})"
      _err "Response: ${_response}"
      return 1
    fi
  else
    # Create new session
    _sessions_endpoint="$(echo "${_response}" | _redfish_get_odata_id 'Links.Sessions')"
    _username="$(echo "${_username}" | _json_encode)"
    _password="$(echo "${_password}" | _json_encode)"
    _body="$(printf '{"UserName":"%s","Password":"%s"}' "${_username%\\n}" "${_password%\\n}")"
    _redfish_rest POST "${_sessions_endpoint}" "${_body}" || return 1
    _code="$(_redfish_response_code)"

    # Verify authentication succeeded
    if [ "${_code}" != '201' ]; then
      _err "Redfish authentication failed (HTTP ${_code})"
      _err "Response: ${_response}"
      if [ "${_code}" = '401' ] && grep -qi '^WWW-Authenticate: Basic.*$' "${HTTP_HEADER}"; then
        _err 'NOTE: Server supports Basic auth scheme. Consider setting DEPLOY_REDFISH_USE_BASIC_AUTH=1 and try again.'
      fi
      return 1
    fi

    _session="$(echo "${_response}" | _redfish_get_odata_id '')"
    _auth_token="$(grep -i '^X-Auth-Token: .*$' "${HTTP_HEADER}" | _tail_n 1 | tr -d ' \r\n' | cut -d ':' -f 2)"
    export _H2="X-Auth-Token: ${_auth_token}"
  fi

  trap '_redfish_log_out "${_session:-}"' EXIT INT
}

_redfish_log_out() {
  _session_endpoint="${1:-}"

  _info "Logging out of Redfish session on: ${DEPLOY_REDFISH_HOST}"

  if [ -n "${_session_endpoint}" ]; then
    _redfish_rest DELETE "${_session_endpoint}" || return 1
    _code="$(_redfish_response_code)"

    if ! _startswith "${_code}" '2'; then
      _err "Failed to log out of Redfish server (HTTP ${_code})."
      _err "Response: ${_response}"
    fi
  else
    _info 'Using basic HTTP auth, no need to log out of Redfish API.'
  fi

  export _H1=
  export _H2=
}

_redfish_get_certificate_service_endpoint() {
  _redfish_rest GET '/redfish/v1/' || return 1
  _certificate_service_endpoint="$(echo "${_response}" | _redfish_get_odata_id 'CertificateService')"
  [ -n "${_certificate_service_endpoint}" ]
}

_redfish_supports_full_certificate_chains() {
  _redfish_rest GET "/redfish/v1/\$metadata" || return 1

  _newest_certificate_schema_version="$(echo "${_response}" |
    sed -n 's/.*Namespace="Certificate\.v\([_0-9][_0-9]*\)".*/\1/p' |
    sort -t _ -k1,1n -k2,2n -k3,3n | _tail_n 1 | tr '_' '.')"
  _debug _newest_certificate_schema_version "${_newest_certificate_schema_version}"

  _schema_major=${_newest_certificate_schema_version%%.*}
  _schema_patch_minor=${_newest_certificate_schema_version#*.}
  _schema_minor=${_schema_patch_minor%%.*}
  _schema_patch=${_schema_patch_minor#*.}

  for var in _schema_major _schema_minor _schema_patch; do
    _debug "$var" "$(eval echo "\$$var")"
    case "$(eval echo "\$$var")" in
    '' | *[!0123456789]*) return 1 ;;
    *) continue ;;
    esac
  done

  [ "${_schema_major}" -gt '1' ] || { [ "${_schema_major}" -ge '1' ] && [ "${_schema_minor}" -ge '4' ]; }
}

_redfish_get_action() {
  unset _action _action_info

  _redfish_rest GET "$1" || return 1
  _action="$(echo "${_response}" | sed -n "s/{.*\"Actions\":{.*\"#$2\":\({[^}]*}\).*/\1/p")"
  _action_info_endpoint="$(echo "${_action}" | sed -n 's/.*"@Redfish\.ActionInfo":"\([^"]*\)".*/\1/p')"

  if [ -n "${_action_info_endpoint}" ]; then
    _redfish_rest GET "${_action_info_endpoint}" || return 1
    _code="$(_redfish_response_code)"

    if [ "${_code}" = '200' ]; then
      _action_info="${_response}"
    fi
  fi
}

_redfish_get_action_allowable_values() {
  _parameter="$1"

  _allowable_values="$(echo "${_action}" |
    sed -n "s/.*\"${_parameter}@Redfish\.AllowableValues\":\[\([^]]*\)\].*/\1/p" |
    tr -d '"')"

  if [ -n "${_allowable_values}" ]; then
    _debug2 "Found allowable values for '${_parameter}' in '@Redfish.Action': [${_allowable_values}]"
    echo "${_allowable_values}" | tr ',' '\n'
  elif [ -n "${_action_info}" ]; then
    _parameter_info="$(echo "${_action_info}" |
      sed -n 's/.*"Parameters":*\[\(\({[^}]*},\{0,1\}\)*\)\].*/\1/p' | _egrep_o '\{[^\}]{1,}\}' |
      grep "\"Name\":\"${_parameter}\"")"

    if [ -n "${_parameter_info}" ]; then
      _debug2 "Found allowable values for '${_parameter}' in @Redfish.ActionInfo: ${_parameter_info}"
      _data_type="$(echo "${_parameter_info}" | sed -n 's/.*"DataType":"\([^"]*\)".*/\1/p')"

      case "${_data_type}" in
      String)
        echo "${_parameter_info}" | sed -n 's/.*"AllowableValues":\[\([^]]*\)\].*/\1/p' | tr -d '"' | tr ',' '\n'
        ;;
      Number)
        echo "${_parameter_info}" | sed -n 's/.*"MinimumValue":\([0-9]\{1,\}\).*/\1/p'
        echo "${_parameter_info}" | sed -n 's/.*"MaximumValue":\([0-9]\{1,\}\).*/\1/p'
        ;;
      esac
    fi
  fi
}

_redfish_supports_private_key() {
  _private_key="$1"
  _certificate_service_endpoint="$2"

  if _isRSA "${_private_key}"; then
    _key_algo='RSA'
  elif _isEcc "${_private_key}"; then
    _key_algo='ECDSA'
  else
    _err 'Private key uses unknown cryptographic algorithm!'
    return 1
  fi

  _redfish_get_action "${_certificate_service_endpoint}" 'CertificateService.GenerateCSR' || return 1
  _allowed_key_algos="$(_redfish_get_action_allowable_values 'KeyPairAlgorithm' | paste -sd ',')"
  _allowed_key_curve_ids="$(_redfish_get_action_allowable_values 'KeyCurveId' | paste -sd ',')"
  _allowed_key_bit_lengths="$(_redfish_get_action_allowable_values 'KeyBitLength' | sort -n)"

  if [ -z "${_allowed_key_bit_lengths}" ] && [ -z "${_allowed_key_curve_ids}" ]; then
    _debug 'Failed to determine server crypto requirements, proceeding blindly.'
    return 0
  fi

  if [ -z "${_allowed_key_algos}" ]; then
    _debug 'GenerateCSR does not specify allowed KeyPairAlgorithm(s), so assuming TCG_ALG_RSA.'
    _allowed_key_algos='TCG_ALG_RSA'
  fi

  _debug _key_algo "${_key_algo}"
  _debug _allowed_key_algos "${_allowed_key_algos}"

  case "${_key_algo}:${_allowed_key_algos}" in
  RSA:*RSA*)
    _min_key_length="$(echo "${_allowed_key_bit_lengths}" | _head_n 1)"
    _max_key_length="$(echo "${_allowed_key_bit_lengths}" | _tail_n 1)"
    _debug _min_key_length "${_min_key_length}"
    _debug _max_key_length "${_max_key_length}"

    if ! expr "${_min_key_length}:${_max_key_length}" : '^[0-9]\{1,\}:[0-9]\{1,\}$' >/dev/null; then
      _err 'Server supports RSA private keys, but its minimum/maximum allowed key bit lengths could not be determined.'
      return 1
    fi

    # shellcheck disable=SC2154 # Le_Keylength is set by acme.sh core, not this hook
    if [ "${Le_Keylength}" -lt "${_min_key_length}" ] || [ "${Le_Keylength}" -gt "${_max_key_length}" ]; then
      _err "Unsupported RSA private key length ${Le_Keylength}!"
      _err "Please re-run acme.sh with --keylength set to a value between ${_min_key_length} and ${_max_key_length}."
      return 1
    fi
    ;;
  ECDSA:*ECDSA*)
    _debug _allowed_key_curve_ids "${_allowed_key_curve_ids}"

    # shellcheck disable=SC2154 # Le_Keylength is set by acme.sh core, not this hook
    if ! _contains "${_allowed_key_curve_ids}" "TPM_ECC_NIST_P${Le_Keylength#ec-}"; then
      _err "Unsupported ECDSA private key type! Server supports only: ${_allowed_key_curve_ids}"
      return 1
    fi
    ;;
  *)
    _err "Unsupported key pair algorithm ${_key_algo}! Server supports only: ${_allowed_key_algos}"
    return 1
    ;;
  esac
}

_redfish_get_primary_manager_endpoint() {
  _redfish_rest GET '/redfish/v1/' || return 1
  _managers_endpoint="$(echo "${_response}" | _redfish_get_odata_id 'Managers')"
  _redfish_rest GET "${_managers_endpoint}" || return 1
  _num_managers="$(echo "${_response}" | _redfish_get_odata_count)"

  if [ "${_num_managers}" != '1' ]; then
    _err "${_num_managers}"
    _all_managers="$(echo "${_response}" | _redfish_get_odata_members | paste -sd ',')"
    _err "Multiple Redfish managers identified (${_all_managers}), but expected exactly one."
    _err 'Please specify the correct manager in DEPLOY_REDFISH_MANAGER.'
    return 1
  fi

  _manager_endpoint="$(echo "${_response}" | _redfish_get_odata_members | _head_n 1)"
  [ -n "${_manager_endpoint}" ]
}

_redfish_get_manager_certificate_endpoint() {
  _manager_endpoint="$1"

  _redfish_rest GET "${_manager_endpoint}" || return 1
  _protocol_endpoint="$(echo "${_response}" | _redfish_get_odata_id 'NetworkProtocol')"
  _redfish_rest GET "${_protocol_endpoint}/HTTPS/Certificates" || return 1
  _num_certificates="$(echo "${_response}" | _redfish_get_odata_count)"

  if [ -z "${_num_certificates}" ]; then
    _certificate_endpoint="${_protocol_endpoint}/HTTPS/Certificates/1"
    return 0
  elif [ "${_num_certificates}" != '1' ]; then
    _all_certificates="$(echo "${_response}" | _redfish_get_odata_members | paste -sd ',')"
    _err "Multiple web service HTTPS certificates identified (${_all_certificates}), but expected exactly one."
    _err "Please specify which certificate should be replaced in DEPLOY_REDFISH_CERTIFICATE."
    return 1
  fi

  _certificate_endpoint="$(echo "${_response}" | _redfish_get_odata_members | _head_n 1)"
  [ -n "${_certificate_endpoint}" ]
}

_redfish_attempt_graceful_restart() {
  _manager_endpoint="$1"

  _redfish_get_action "${_manager_endpoint}" 'Manager.Reset' || return 1
  _allowed_reset_types="$(_redfish_get_action_allowable_values 'ResetType')"

  if ! _contains "${_allowed_reset_types}" 'GracefulRestart'; then
    _err "BMC doesn't support graceful restarts. Please wait up to 20 seconds to take effect, or restart the BMC manually."
    return 1
  fi

  _redfish_rest POST "${_manager_endpoint}/Actions/Manager.Reset" '{"ResetType":"GracefulRestart"}' || return 1
  _code="$(_redfish_response_code)"

  if ! _startswith "${_code}" '2'; then
    _err "Failed to gracefully restart BMC! (HTTP ${_code})"
    _err "Response: ${_response}"
    return 1
  fi
}
