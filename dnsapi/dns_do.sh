#!/usr/bin/env sh

# DNS API for Domain-Offensive / Resellerinterface / Domainrobot

# DO_PID="KD-1234567"
# DO_PW="cdfkjl3n2"

DO_URL="https://soap.resellerinterface.de/"

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_do_add() {
  fulldomain=$1
  txtvalue=$2
  _cookiejar="$(_mktemp)"
  if _dns_do_authenticate; then
    _info "Adding TXT record to ${_domain} as ${fulldomain}"
    _dns_do_soap createRR origin "${_domain}" name "${fulldomain}" type TXT data "${txtvalue}" ttl 300
    if _contains "${response}" '>success<'; then
      return 0
    fi
    _err "Could not create resource record, check logs"
  fi
  return 1
}

#fulldomain
dns_do_rm() {
  fulldomain=$1
  _cookiejar="$(_mktemp)"
  if _dns_do_authenticate; then
    if _dns_do_list_rrs; then
      for _rrid in ${_rr_list}; do
        _info "Deleting resource record $_rrid for $_domain"
        _dns_do_soap deleteRR origin "${_domain}" rrid "${_rrid}"
        if ! _contains "${response}" '>success<'; then
          _err "Could not delete resource record for ${_domain}, id ${_rrid}"
        fi
      done
      return 0
    fi
  fi
  return 1
}

####################  Private functions below ##################################
_dns_do_authenticate() {
  _info "Authenticating as ${DO_PID}"
  _dns_do_soap authPartner partner "${DO_PID}" password "${DO_PW}"
  if _contains "${response}" '>success<'; then
    _get_root "$fulldomain"
    _debug "_domain $_domain"
    return 0
  else
    _err "Authentication failed, check logs"
  fi
  return 1
}

_dns_do_list_rrs() {
  _dns_do_soap getRRList origin "${_domain}"
  if ! _contains "${response}" 'SOAP-ENC:Array'; then
    _err "getRRList origin ${_domain} failed"
    return 1
  fi
  _rr_list="$(echo "${response}" \
    | tr -d "\n\r\t" \
    | sed -e 's/<item xsi:type="ns2:Map">/\n/g' \
    | grep -F ">${fulldomain}</value>" \
    | sed -e 's/<item>/\n\0/g' \
    | grep -F '>id</key>' \
    | sed -re 's/.*<value[^>]*>([^<]+)<\/value>.*/\1/')"
  [ "${_rr_list}" ]
}

_dns_do_soap() {
  func="$1"
  shift
  # put the parameters to xml
  body="<tns:${func} xmlns:tns=\"${DO_URL}\">"
  while [ "$1" ] ; do
    _k="$1"
    shift
    _v="$1"
    shift
    body="$body<$_k>$_v</$_k>"
  done
  body="$body</tns:${func}>"
  _debug2 "SOAP request ${body}"

  # build SOAP XML
  _xml='<?xml version="1.0" encoding="UTF-8"?>
<env:Envelope xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">
  <env:Body>'"$body"'</env:Body>
</env:Envelope>'

  # set SOAP headers
  _H1="SOAPAction: ${DO_URL}#${func}"
  # add cookie header if present
  [ -s "${_cookiejar}" ] && _H2="$(cat "${_cookiejar}")"

  if ! response="$(_post "${_xml}" "${DO_URL}")"; then
    _err "Error <$1>"
    return 1
  fi
  _debug2 "SOAP response $response"

  # retrieve cookie header
  grep -F 'Set-Cookie:' "$HTTP_HEADER" | sed -re 's/^Set-(Cookie: [^;]+).*/\1/' | head -1 > "${_cookiejar}"

  return 0
}

_get_root() {
  domain=$1
  i=1

  _all_domains="$(_mktemp)"
  _dns_do_soap getDomainList
  echo "${response}" | tr -d "\n\r\t " | grep -Eo 'domain</key><value[^>]+>[^<]+' | sed -re 's/^domain<\/key><value[^>]+>//g' > "${_all_domains}"

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      return 1
    fi

    if grep -qF "$h" "${_all_domains}"; then
      _domain="$h"
      return 0
    fi

    i=$(_math $i + 1)
  done
  _debug "$domain not found"

  return 1
}

_info() {
  if [ -z "$2" ]; then
    echo "[$(date)] $1"
  else
    echo "[$(date)] $1='$2'"
  fi
}

_err() {
  _info "$@" >&2
  return 1
}

_debug() {
  if [ -z "$DEBUG" ]; then
    return
  fi
  _err "$@"
  return 0
}

_debug2() {
  if [ "$DEBUG" ] && [ "$DEBUG" -ge "2" ]; then
    _debug "$@"
  fi
  return
}
