#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_hetznercloud_info='Hetzner Cloud DNS
Site: Hetzner.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_hetznercloud
Options:
 HETZNER_TOKEN API token for the Hetzner Cloud DNS API
Optional:
 HETZNER_TTL Custom TTL for new TXT rrsets (default 120)
 HETZNER_API Override API endpoint (default https://api.hetzner.cloud/v1)
Issues: github.com/acmesh-official/acme.sh/issues
'

HETZNERCLOUD_API_DEFAULT="https://api.hetzner.cloud/v1"
HETZNERCLOUD_TTL_DEFAULT=120

########  Public functions #####################

dns_hetznercloud_add() {
  fulldomain="$(_idn "${1}")"
  txtvalue="${2}"

  _info "Using Hetzner Cloud DNS API to add record"

  if ! _hetznercloud_init; then
    return 1
  fi

  if ! _hetznercloud_prepare_zone "${fulldomain}"; then
    _err "Unable to determine Hetzner Cloud zone for ${fulldomain}"
    return 1
  fi

  if ! _hetznercloud_get_rrset; then
    return 1
  fi

  if [ "${_hetznercloud_last_http_code}" = "200" ]; then
    if _hetznercloud_rrset_contains_value "${txtvalue}"; then
      _info "TXT record already present; nothing to do."
      return 0
    fi
  elif [ "${_hetznercloud_last_http_code}" != "404" ]; then
    _hetznercloud_log_http_error "Failed to query existing TXT rrset" "${_hetznercloud_last_http_code}"
    return 1
  fi

  add_payload="$(_hetznercloud_build_add_payload "${txtvalue}")"
  if [ -z "${add_payload}" ]; then
    _err "Failed to build request payload."
    return 1
  fi

  if ! _hetznercloud_api POST "${_hetznercloud_rrset_action_add}" "${add_payload}"; then
    return 1
  fi

  case "${_hetznercloud_last_http_code}" in
  200 | 201 | 202 | 204)
    _info "Hetzner Cloud TXT record added."
    return 0
    ;;
  401 | 403)
    _err "Hetzner Cloud DNS API authentication failed (HTTP ${_hetznercloud_last_http_code}). Check HETZNER_TOKEN for the new API."
    _hetznercloud_log_http_error "" "${_hetznercloud_last_http_code}"
    return 1
    ;;
  409 | 422)
    _hetznercloud_log_http_error "Hetzner Cloud DNS rejected the add_records request" "${_hetznercloud_last_http_code}"
    return 1
    ;;
  *)
    _hetznercloud_log_http_error "Hetzner Cloud DNS add_records request failed" "${_hetznercloud_last_http_code}"
    return 1
    ;;
  esac
}

dns_hetznercloud_rm() {
  fulldomain="$(_idn "${1}")"
  txtvalue="${2}"

  _info "Using Hetzner Cloud DNS API to remove record"

  if ! _hetznercloud_init; then
    return 1
  fi

  if ! _hetznercloud_prepare_zone "${fulldomain}"; then
    _err "Unable to determine Hetzner Cloud zone for ${fulldomain}"
    return 1
  fi

  if ! _hetznercloud_get_rrset; then
    return 1
  fi

  if [ "${_hetznercloud_last_http_code}" = "404" ]; then
    _info "TXT rrset does not exist; nothing to remove."
    return 0
  fi

  if [ "${_hetznercloud_last_http_code}" != "200" ]; then
    _hetznercloud_log_http_error "Failed to query existing TXT rrset" "${_hetznercloud_last_http_code}"
    return 1
  fi

  if _hetznercloud_rrset_contains_value "${txtvalue}"; then
    remove_payload="$(_hetznercloud_build_remove_payload "${txtvalue}")"
    if [ -z "${remove_payload}" ]; then
      _err "Failed to build remove_records payload."
      return 1
    fi
    if ! _hetznercloud_api POST "${_hetznercloud_rrset_action_remove}" "${remove_payload}"; then
      return 1
    fi
    case "${_hetznercloud_last_http_code}" in
    200 | 201 | 202 | 204)
      _info "Hetzner Cloud TXT record removed."
      return 0
      ;;
    401 | 403)
      _err "Hetzner Cloud DNS API authentication failed (HTTP ${_hetznercloud_last_http_code}). Check HETZNER_TOKEN for the new API."
      _hetznercloud_log_http_error "" "${_hetznercloud_last_http_code}"
      return 1
      ;;
    404)
      _info "TXT rrset already absent after remove action."
      return 0
      ;;
    409 | 422)
      _hetznercloud_log_http_error "Hetzner Cloud DNS rejected the remove_records request" "${_hetznercloud_last_http_code}"
      return 1
      ;;
    *)
      _hetznercloud_log_http_error "Hetzner Cloud DNS remove_records request failed" "${_hetznercloud_last_http_code}"
      return 1
      ;;
    esac
  else
    _info "TXT value not present; nothing to remove."
    return 0
  fi
}

####################  Private functions ##################################

_hetznercloud_init() {
  HETZNER_TOKEN="${HETZNER_TOKEN:-$(_readaccountconf_mutable HETZNER_TOKEN)}"
  if [ -z "${HETZNER_TOKEN}" ]; then
    _err "The environment variable HETZNER_TOKEN must be set for the Hetzner Cloud DNS API."
    return 1
  fi
  HETZNER_TOKEN=$(echo "${HETZNER_TOKEN}" | tr -d '"')
  _saveaccountconf_mutable HETZNER_TOKEN "${HETZNER_TOKEN}"

  HETZNER_API="${HETZNER_API:-$(_readaccountconf_mutable HETZNER_API)}"
  if [ -z "${HETZNER_API}" ]; then
    HETZNER_API="${HETZNERCLOUD_API_DEFAULT}"
  fi
  _saveaccountconf_mutable HETZNER_API "${HETZNER_API}"

  HETZNER_TTL="${HETZNER_TTL:-$(_readaccountconf_mutable HETZNER_TTL)}"
  if [ -z "${HETZNER_TTL}" ]; then
    HETZNER_TTL="${HETZNERCLOUD_TTL_DEFAULT}"
  fi
  ttl_check=$(printf "%s" "${HETZNER_TTL}" | tr -d '0-9')
  if [ -n "${ttl_check}" ]; then
    _err "HETZNER_TTL must be an integer value."
    return 1
  fi
  _saveaccountconf_mutable HETZNER_TTL "${HETZNER_TTL}"

  return 0
}

_hetznercloud_prepare_zone() {
  _hetznercloud_zone_id=""
  _hetznercloud_zone_name=""
  _hetznercloud_zone_name_lc=""
  _hetznercloud_rr_name=""
  _hetznercloud_rrset_path=""
  _hetznercloud_rrset_action_add=""
  _hetznercloud_rrset_action_remove=""
  fulldomain_lc=$(printf "%s" "${1}" | sed 's/\.$//' | _lower_case)

  i=2
  p=1
  while true; do
    candidate=$(printf "%s" "${fulldomain_lc}" | cut -d . -f "${i}"-100)
    if [ -z "${candidate}" ]; then
      return 1
    fi

    if _hetznercloud_get_zone_by_candidate "${candidate}"; then
      zone_name_lc="${_hetznercloud_zone_name_lc}"
      if [ "${fulldomain_lc}" = "${zone_name_lc}" ]; then
        _hetznercloud_rr_name="@"
      else
        suffix=".${zone_name_lc}"
        if _endswith "${fulldomain_lc}" "${suffix}"; then
          _hetznercloud_rr_name="${fulldomain_lc%"${suffix}"}"
        else
          _hetznercloud_rr_name="${fulldomain_lc}"
        fi
      fi
      _hetznercloud_rrset_path=$(printf "%s" "${_hetznercloud_rr_name}" | _url_encode)
      _hetznercloud_rrset_action_add="/zones/${_hetznercloud_zone_id}/rrsets/${_hetznercloud_rrset_path}/TXT/actions/add_records"
      _hetznercloud_rrset_action_remove="/zones/${_hetznercloud_zone_id}/rrsets/${_hetznercloud_rrset_path}/TXT/actions/remove_records"
      return 0
    fi
    p=${i}
    i=$(_math "${i}" + 1)
  done
}

_hetznercloud_get_zone_by_candidate() {
  candidate="${1}"
  zone_key=$(printf "%s" "${candidate}" | sed 's/[^A-Za-z0-9]/_/g')
  zone_conf_key="HETZNERCLOUD_ZONE_ID_for_${zone_key}"

  cached_zone_id=$(_readdomainconf "${zone_conf_key}")
  if [ -n "${cached_zone_id}" ]; then
    if _hetznercloud_api GET "/zones/${cached_zone_id}"; then
      if [ "${_hetznercloud_last_http_code}" = "200" ]; then
        zone_data=$(printf "%s" "${response}" | _normalizeJson | sed 's/^{"zone"://' | sed 's/}$//')
        if _hetznercloud_parse_zone_fields "${zone_data}"; then
          zone_name_lc=$(printf "%s" "${_hetznercloud_zone_name}" | _lower_case)
          if [ "${zone_name_lc}" = "${candidate}" ]; then
            return 0
          fi
        fi
      elif [ "${_hetznercloud_last_http_code}" = "404" ]; then
        _cleardomainconf "${zone_conf_key}"
      fi
    else
      return 1
    fi
  fi

  if _hetznercloud_api GET "/zones/${candidate}"; then
    if [ "${_hetznercloud_last_http_code}" = "200" ]; then
      zone_data=$(printf "%s" "${response}" | _normalizeJson | sed 's/^{"zone"://' | sed 's/}$//')
      if _hetznercloud_parse_zone_fields "${zone_data}"; then
        zone_name_lc=$(printf "%s" "${_hetznercloud_zone_name}" | _lower_case)
        if [ "${zone_name_lc}" = "${candidate}" ]; then
          _savedomainconf "${zone_conf_key}" "${_hetznercloud_zone_id}"
          return 0
        fi
      fi
    elif [ "${_hetznercloud_last_http_code}" != "404" ]; then
      _hetznercloud_log_http_error "Hetzner Cloud zone lookup failed" "${_hetznercloud_last_http_code}"
      return 1
    fi
  else
    return 1
  fi

  encoded_candidate=$(printf "%s" "${candidate}" | _url_encode)
  if ! _hetznercloud_api GET "/zones?name=${encoded_candidate}"; then
    return 1
  fi
  if [ "${_hetznercloud_last_http_code}" != "200" ]; then
    if [ "${_hetznercloud_last_http_code}" = "404" ]; then
      return 1
    fi
    _hetznercloud_log_http_error "Hetzner Cloud zone search failed" "${_hetznercloud_last_http_code}"
    return 1
  fi

  zone_data=$(_hetznercloud_extract_zone_from_list "${response}" "${candidate}")
  if [ -z "${zone_data}" ]; then
    return 1
  fi
  if ! _hetznercloud_parse_zone_fields "${zone_data}"; then
    return 1
  fi
  _savedomainconf "${zone_conf_key}" "${_hetznercloud_zone_id}"
  return 0
}

_hetznercloud_parse_zone_fields() {
  zone_json="${1}"
  if [ -z "${zone_json}" ]; then
    return 1
  fi
  normalized=$(printf "%s" "${zone_json}" | _normalizeJson)
  zone_id=$(printf "%s" "${normalized}" | _egrep_o '"id":[^,}]*' | _head_n 1 | cut -d : -f 2 | tr -d ' "')
  zone_name=$(printf "%s" "${normalized}" | _egrep_o '"name":"[^"]*"' | _head_n 1 | cut -d : -f 2 | tr -d '"')
  if [ -z "${zone_id}" ] || [ -z "${zone_name}" ]; then
    return 1
  fi
  _hetznercloud_zone_id="${zone_id}"
  _hetznercloud_zone_name="${zone_name}"
  _hetznercloud_zone_name_lc=$(printf "%s" "${zone_name}" | sed 's/\.$//' | _lower_case)
  return 0
}

_hetznercloud_extract_zone_from_list() {
  list_response=$(printf "%s" "${1}" | _normalizeJson)
  candidate="${2}"
  escaped_candidate=$(_hetznercloud_escape_regex "${candidate}")
  printf "%s" "${list_response}" | _egrep_o "{[^{}]*\"name\":\"${escaped_candidate}\"[^{}]*}" | _head_n 1
}

_hetznercloud_escape_regex() {
  printf "%s" "${1}" | sed 's/\\/\\\\/g' | sed 's/\./\\./g' | sed 's/-/\\-/g'
}

_hetznercloud_get_rrset() {
  if [ -z "${_hetznercloud_zone_id}" ] || [ -z "${_hetznercloud_rrset_path}" ]; then
    return 1
  fi
  if ! _hetznercloud_api GET "/zones/${_hetznercloud_zone_id}/rrsets/${_hetznercloud_rrset_path}/TXT"; then
    return 1
  fi
  return 0
}

_hetznercloud_rrset_contains_value() {
  wanted_value="${1}"
  normalized=$(printf "%s" "${response}" | _normalizeJson)
  escaped_value=$(_hetznercloud_escape_value "${wanted_value}")
  search_pattern="\"value\":\"\\\\\"${escaped_value}\\\\\"\""
  if _contains "${normalized}" "${search_pattern}"; then
    return 0
  fi
  return 1
}

_hetznercloud_build_add_payload() {
  value="${1}"
  escaped_value=$(_hetznercloud_escape_value "${value}")
  printf '{"ttl":%s,"records":[{"value":"\\"%s\\""}]}' "${HETZNER_TTL}" "${escaped_value}"
}

_hetznercloud_build_remove_payload() {
  value="${1}"
  escaped_value=$(_hetznercloud_escape_value "${value}")
  printf '{"records":[{"value":"\\"%s\\""}]}' "${escaped_value}"
}

_hetznercloud_escape_value() {
  printf "%s" "${1}" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g'
}

_hetznercloud_error_message() {
  if [ -z "${response}" ]; then
    return 1
  fi
  message=$(printf "%s" "${response}" | _normalizeJson | _egrep_o '"message":"[^"]*"' | _head_n 1 | cut -d : -f 2 | tr -d '"')
  if [ -n "${message}" ]; then
    printf "%s" "${message}"
    return 0
  fi
  return 1
}

_hetznercloud_log_http_error() {
  context="${1}"
  code="${2}"
  message="$(_hetznercloud_error_message)"
  if [ -n "${context}" ]; then
    if [ -n "${message}" ]; then
      _err "${context} (HTTP ${code}): ${message}"
    else
      _err "${context} (HTTP ${code})"
    fi
  else
    if [ -n "${message}" ]; then
      _err "Hetzner Cloud DNS API error (HTTP ${code}): ${message}"
    else
      _err "Hetzner Cloud DNS API error (HTTP ${code})"
    fi
  fi
}

_hetznercloud_api() {
  method="${1}"
  ep="${2}"
  data="${3}"
  retried="${4}"

  if [ -z "${method}" ]; then
    method="GET"
  fi

  if ! _startswith "${ep}" "/"; then
    ep="/${ep}"
  fi
  url="${HETZNER_API}${ep}"

  export _H1="Authorization: Bearer ${HETZNER_TOKEN}"
  export _H2="Accept: application/json"
  export _H3=""
  export _H4=""
  export _H5=""

  : >"${HTTP_HEADER}"

  if [ "${method}" = "GET" ]; then
    response="$(_get "${url}")"
  else
    if [ -z "${data}" ]; then
      data="{}"
    fi
    response="$(_post "${data}" "${url}" "" "${method}" "application/json")"
  fi
  ret="${?}"

  _hetznercloud_last_http_code=$(grep "^HTTP" "${HTTP_HEADER}" | _tail_n 1 | cut -d " " -f 2 | tr -d '\r\n')

  if [ "${ret}" != "0" ]; then
    return 1
  fi

  if [ "${_hetznercloud_last_http_code}" = "429" ] && [ "${retried}" != "retried" ]; then
    retry_after=$(grep -i "^Retry-After" "${HTTP_HEADER}" | _tail_n 1 | cut -d : -f 2 | tr -d ' \r')
    if [ -z "${retry_after}" ]; then
      retry_after=1
    fi
    _info "Hetzner Cloud DNS API rate limit hit; retrying in ${retry_after} seconds."
    _sleep "${retry_after}"
    if ! _hetznercloud_api "${method}" "${ep}" "${data}" "retried"; then
      return 1
    fi
    return 0
  fi

  return 0
}
