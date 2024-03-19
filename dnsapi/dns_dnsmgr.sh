#!/usr/bin/env sh

# Ispsystem dnsmanager API
# Author: Oleg from Reddock
# Created: 2020-09-13
#
#     export ISP_DNS_URL="https://dnsmanager_url/dnsmgr"
#     export ISP_DNS_USER="username"
#     export ISP_DNS_PASS="password"
#
# Usage:
#     acme.sh --issue --dns dns_dnsmgr -d example.com

ISP_DNS_URL="${ISP_DNS_URL:-$(_readaccountconf_mutable ISP_DNS_URL)}"
############################ Public Functions ##############################
#Usage: dns_dnsmgr_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dnsmgr_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using ispsystem dnsmanager api"
  _debug fulldomain "${fulldomain}"
  _debug txtvalue "${txtvalue}"
  ISP_DNS_USER="${ISP_DNS_USER:-$(_readaccountconf_mutable ISP_DNS_USER)}"
  ISP_DNS_PASS="${ISP_DNS_PASS:-$(_readaccountconf_mutable ISP_DNS_PASS)}"
  if [ -z "${ISP_DNS_USER}" ] || [ -z "${ISP_DNS_PASS}" ]; then
    ISP_DNS_USER=""
    ISP_DNS_PASS=""
    _err "Ispsystem dnsmanager username and password must be present."
    return 1
  fi
  _saveaccountconf_mutable ISP_DNS_USER "${ISP_DNS_USER}"
  _saveaccountconf_mutable ISP_DNS_PASS "${ISP_DNS_PASS}"
  _saveaccountconf_mutable ISP_DNS_URL "${ISP_DNS_URL}"

  _debug "First detect the root zone"
  if ! _get_root "${fulldomain}"; then
    _err "invalid domain"
    return 1
  fi

  _debug "Adding txt record"

  if _zone_add_record "${_domain}" "${fulldomain}" "${txtvalue}"; then
    if _contains "${response}" "\"ok\":true" >/dev/null; then
      _info "Added, OK"
      return 0
    else
      _err "Adding txt record error."
      return 1
    fi
  else
    _err "Adding txt record error."
  fi
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_dnsmgr_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using ispsystem dnsmanager api"
  _debug fulldomain "${fulldomain}"
  _debug txtvalue "${txtvalue}"
  ISP_DNS_USER="${ISP_DNS_USER:-$(_readaccountconf_mutable ISP_DNS_USER)}"
  ISP_DNS_PASS="${ISP_DNS_PASS:-$(_readaccountconf_mutable ISP_DNS_PASS)}"
  if [ -z "${ISP_DNS_USER}" ] || [ -z "${ISP_DNS_PASS}" ]; then
    ISP_DNS_USER=""
    ISP_DNS_PASS=""
    _err "Ispsystem dnsmanager username and password must be present."
    return 1
  fi
  _saveaccountconf_mutable ISP_DNS_USER "${ISP_DNS_USER}"
  _saveaccountconf_mutable ISP_DNS_PASS "${ISP_DNS_PASS}"
  _saveaccountconf_mutable ISP_DNS_URL "${ISP_DNS_URL}"

  _debug "First detect the root zone"
  if ! _get_root "${fulldomain}"; then
    _err "invalid domain"
    return 1
  fi

  _zone_rm_record "${_domain}" "${fulldomain}" "${txtvalue}"
  _debug response: "${response}"
  _info "Record deleted"
  return 0
}

############################ Private Functions ##############################
_zone_find() {
  _isp_domain="$1"
  _isp_body="authinfo=${ISP_DNS_USER}:${ISP_DNS_PASS}&func=domain&filter=on&out=bjson&name=${_isp_domain}"
  response="$(_post "${_isp_body}" "${ISP_DNS_URL}")"
  if [ "$?" != "0" ]; then
    _err "error ${_isp_domain} find domain"
    return 1
  fi
  _debug2 response "${response}"
  return 0
}
#
_zone_add_record() {
  _isp_domain="$1"
  _isp_record_name="$2"
  _isp_record_value="$3"

  _isp_body="authinfo=${ISP_DNS_USER}:${ISP_DNS_PASS}&func=domain.record.edit&ttl=90&sok=ok&rtype=txt&out=bjson&plid=${_isp_domain}&name=${_isp_record_name}.&value=${_isp_record_value}"
  response="$(_post "${_isp_body}" "${ISP_DNS_URL}")"
  if [ "$?" != "0" ]; then
    _err "error ${_isp_domain} add domain record"
    return 1
  fi
  _debug2 response "${response}"
  return 0
}
#
_zone_rm_record() {
  _isp_domain="$1"
  _isp_record_name="$2"
  _isp_record_value="$3"

  _isp_body="authinfo=${ISP_DNS_USER}:${ISP_DNS_PASS}&func=domain.record.delete&sok=ok&out=bjson&plid=${_isp_domain}&elid=${_isp_record_name}.%20TXT%20%20${_isp_record_value}"
  response="$(_post "${_isp_body}" "${ISP_DNS_URL}")"
  if [ "$?" != "0" ]; then
    _err "error ${_isp_domain} delete domain record"
    return 1
  fi
  _debug2 response "${response}"
  return 0
}
#
_get_root() {
  domain=$1
  i=2
  while true; do
    h=$(printf "%s" "${domain}" | cut -d . -f ${i}-100)
    _debug h "${h}"
    if [ -z "${h}" ]; then
      return 1
    fi
    if ! _zone_find "${h}"; then
      return 1
    fi
    if _contains "${response}" "\"name\":\"${h}\"" >/dev/null; then
      _domain="${h}"
      return 0
    fi
    i="$(_math "${i}" + 1)"
  done
  return 0
}
