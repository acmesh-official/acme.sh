#!/usr/bin/env sh
########################################################################
# NocWorx script for acme.sh
#
# Handles DNS Updates for the Following vendors:
#   - Nexcess.net
#   - Thermo.io
#   - Futurehosting.com
#
# Environment variables:
#
#  - NW_API_TOKEN  (Your API Token)
#  - NW_API_ENDPOINT (One of the following listed below)
#
# Endpoints:
#   - https://portal.nexcess.net (default)
#   - https://core.thermo.io
#   - https://my.futurehosting.com
#
#  Note: If you do not have an API token, one can be generated at one
#        of the following URLs:
#        - https://portal.nexcess.net/api-token
#        - https://core.thermo.io/api-token
#        - https://my.futurehosting.com/api-token
#
# Author: Frank Laszlo <flaszlo@nexcess.net>

NW_API_VERSION="0"

# dns_nw_add() - Add TXT record
# Usage: dns_nw_add _acme-challenge.subdomain.domain.com "XyZ123..."
dns_nw_add() {
  host="${1}"
  txtvalue="${2}"

  _debug host "${host}"
  _debug txtvalue "${txtvalue}"

  if ! _check_nw_api_creds; then
    return 1
  fi

  _info "Using NocWorx (${NW_API_ENDPOINT})"
  _debug "Calling: dns_nw_add() '${host}' '${txtvalue}'"

  _debug "Detecting root zone"
  if ! _get_root "${host}"; then
    _err "Zone for domain does not exist."
    return 1
  fi
  _debug _zone_id "${_zone_id}"
  _debug _sub_domain "${_sub_domain}"
  _debug _domain "${_domain}"

  _post_data="{\"zone_id\": \"${_zone_id}\", \"type\": \"TXT\", \"host\": \"${host}\", \"target\": \"${txtvalue}\", \"ttl\": \"300\"}"

  if _rest POST "dns-record" "${_post_data}" && [ -n "${response}" ]; then
    _record_id=$(printf "%s\n" "${response}" | _egrep_o "\"record_id\": *[0-9]+" | cut -d : -f 2 | tr -d " " | _head_n 1)
    _debug _record_id "${_record_id}"

    if [ -z "$_record_id" ]; then
      _err "Error adding the TXT record."
      return 1
    fi

    _info "TXT record successfully added."
    return 0
  fi

  return 1
}

# dns_nw_rm() - Remove TXT record
# Usage: dns_nw_rm _acme-challenge.subdomain.domain.com "XyZ123..."
dns_nw_rm() {
  host="${1}"
  txtvalue="${2}"

  _debug host "${host}"
  _debug txtvalue "${txtvalue}"

  if ! _check_nw_api_creds; then
    return 1
  fi

  _info "Using NocWorx (${NW_API_ENDPOINT})"
  _debug "Calling: dns_nw_rm() '${host}'"

  _debug "Detecting root zone"
  if ! _get_root "${host}"; then
    _err "Zone for domain does not exist."
    return 1
  fi
  _debug _zone_id "${_zone_id}"
  _debug _sub_domain "${_sub_domain}"
  _debug _domain "${_domain}"

  _parameters="?zone_id=${_zone_id}"

  if _rest GET "dns-record" "${_parameters}" && [ -n "${response}" ]; then
    response="$(echo "${response}" | tr -d "\n" | sed 's/^\[\(.*\)\]$/\1/' | sed -e 's/{"record_id":/|"record_id":/g' | sed 's/|/&{/g' | tr "|" "\n")"
    _debug response "${response}"

    record="$(echo "${response}" | _egrep_o "{.*\"host\": *\"${_sub_domain}\", *\"target\": *\"${txtvalue}\".*}")"
    _debug record "${record}"

    if [ "${record}" ]; then
      _record_id=$(printf "%s\n" "${record}" | _egrep_o "\"record_id\": *[0-9]+" | _head_n 1 | cut -d : -f 2 | tr -d \ )
      if [ "${_record_id}" ]; then
        _debug _record_id "${_record_id}"

        _rest DELETE "dns-record/${_record_id}"

        _info "TXT record successfully deleted."
        return 0
      fi

      return 1
    fi

    return 0
  fi

  return 1
}

_check_nw_api_creds() {
  NW_API_TOKEN="${NW_API_TOKEN:-$(_readaccountconf_mutable NW_API_TOKEN)}"
  NW_API_ENDPOINT="${NW_API_ENDPOINT:-$(_readaccountconf_mutable NW_API_ENDPOINT)}"

  if [ -z "${NW_API_ENDPOINT}" ]; then
    NW_API_ENDPOINT="https://portal.nexcess.net"
  fi

  if [ -z "${NW_API_TOKEN}" ]; then
    _err "You have not defined your NW_API_TOKEN."
    _err "Please create your token and try again."
    _err "If you need to generate a new token, please visit one of the following URLs:"
    _err "  - https://portal.nexcess.net/api-token"
    _err "  - https://core.thermo.io/api-token"
    _err "  - https://my.futurehosting.com/api-token"

    return 1
  fi

  _saveaccountconf_mutable NW_API_TOKEN "${NW_API_TOKEN}"
  _saveaccountconf_mutable NW_API_ENDPOINT "${NW_API_ENDPOINT}"
}

_get_root() {
  domain="${1}"
  i=2
  p=1

  if _rest GET "dns-zone"; then
    response="$(echo "${response}" | tr -d "\n" | sed 's/^\[\(.*\)\]$/\1/' | sed -e 's/{"zone_id":/|"zone_id":/g' | sed 's/|/&{/g' | tr "|" "\n")"

    _debug response "${response}"
    while true; do
      h=$(printf "%s" "${domain}" | cut -d . -f $i-100)
      _debug h "${h}"
      if [ -z "${h}" ]; then
        #not valid
        return 1
      fi

      hostedzone="$(echo "${response}" | _egrep_o "{.*\"domain\": *\"${h}\".*}")"
      if [ "${hostedzone}" ]; then
        _zone_id=$(printf "%s\n" "${hostedzone}" | _egrep_o "\"zone_id\": *[0-9]+" | _head_n 1 | cut -d : -f 2 | tr -d \ )
        if [ "${_zone_id}" ]; then
          _sub_domain=$(printf "%s" "${domain}" | cut -d . -f 1-${p})
          _domain="${h}"
          return 0
        fi
        return 1
      fi
      p=$i
      i=$(_math "${i}" + 1)
    done
  fi
  return 1
}

_rest() {
  method="${1}"
  ep="/${2}"
  data="${3}"

  _debug method "${method}"
  _debug ep "${ep}"

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  export _H3="Api-Version: ${NW_API_VERSION}"
  export _H4="User-Agent: NW-ACME-CLIENT"
  export _H5="Authorization: Bearer ${NW_API_TOKEN}"

  if [ "${method}" != "GET" ]; then
    _debug data "${data}"
    response="$(_post "${data}" "${NW_API_ENDPOINT}${ep}" "" "${method}")"
  else
    response="$(_get "${NW_API_ENDPOINT}${ep}${data}")"
  fi

  if [ "${?}" != "0" ]; then
    _err "error ${ep}"
    return 1
  fi
  _debug2 response "${response}"
  return 0
}
