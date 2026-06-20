#!/usr/bin/env sh
dns_netim_info='Netim.com
Site: netim.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_netim
Options:
 NETIM_USER Netim reseller UserID
 NETIM_SECRET Password
Issues: github.com/acmesh-official/acme.sh/issues/6273
Author: Fabio Bas <ctrlaltca@gmail.com>
'

NETIM_SOAP_URL="https://api.netim.com/2.0/"
NETIM_SESSION=""

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_netim_add() {
  fulldomain=$1
  txtvalue=$2

  NETIM_USER="${NETIM_USER:-$(_readaccountconf_mutable NETIM_USER)}"
  NETIM_SECRET="${NETIM_SECRET:-$(_readaccountconf_mutable NETIM_SECRET)}"
  if [ -z "$NETIM_USER" ] || [ -z "$NETIM_SECRET" ]; then
    NETIM_USER=""
    NETIM_SECRET=""
    _err "You don't specify Netim username and secret yet."
    _err "Please create your key and try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable NETIM_USER "$NETIM_USER"
  _saveaccountconf_mutable NETIM_SECRET "$NETIM_SECRET"

  if _dns_netim_session_open; then
    _info "Adding TXT record to ${_domain} as ${fulldomain}"

    _debug "First detect the root zone"
    if ! _get_root "$fulldomain"; then
      _err "invalid domain"
      return 1
    fi
    _debug _subdomain "$_subdomain"
    _debug _domain "$_domain"

    _dns_netim_soap Services domainZoneCreate IDSession "${NETIM_SESSION}" domain "${_domain}" subdomain "${_subdomain}" type TXT value "${txtvalue}"
    if _contains "${response}" '>Done</STATUS'; then
      _dns_netim_session_close
      return 0
    fi
    _dns_netim_session_close
    _err "Could not create resource record, check logs"
  fi
  return 1
}

# Usage: fulldomain txtvalue
# Used to remove the txt record after validation
dns_netim_rm() {
  fulldomain=$1
  txtvalue=$2

  if _dns_netim_session_open; then
    _info "Deleting TXT record to ${_domain} as ${fulldomain}"

    _debug "First detect the root zone"
    if ! _get_root "$fulldomain"; then
      _err "invalid domain"
      return 1
    fi
    _debug _subdomain "$_subdomain"
    _debug _domain "$_domain"

    _dns_netim_soap Services domainZoneDelete IDSession "${NETIM_SESSION}" domain "${_domain}" subdomain "${_subdomain}" type TXT value "${txtvalue}"
    if _contains "${response}" '>Done</STATUS'; then
      _dns_netim_session_close
      return 0
    fi
    _dns_netim_session_close
    _err "Could not delete record, check logs"
  fi
  return 1
}

####################  Private functions below ##################################
_dns_netim_session_open() {
  _info "Authenticating as ${NETIM_USER}"
  _dns_netim_soap DRS sessionOpen idReseller "${NETIM_USER}" password "${NETIM_SECRET}" language "EN"
  NETIM_SESSION=$(echo "$response" |
    _egrep_o "<IDSession.*>[0-9a-f]{32}</IDSession" |
    _egrep_o ">[0-9a-f]{32}<" |
    tr -d '><')
  _debug "NETIM_SESSION $NETIM_SESSION"
  if [ -z "$NETIM_SESSION" ]; then
    _err "Authentication failed, are NETIM_USER and NETIM_SECRET set correctly?"
    return 1
  fi
  return 0
}

_dns_netim_session_close() {
  _info "Closing session"
  _dns_netim_soap DRS sessionClose idSession "${NETIM_SESSION}"
  if _contains "${response}" 'sessionCloseResponse'; then
    return 0
  else
    _err "Authentication failed, are NETIM_USER and NETIM_SECRET set correctly?"
  fi
  return 1
}

_dns_netim_soap() {
  ns="$1"
  shift
  func="$1"
  shift
  # put the parameters to xml
  body="<ns1:${func}>"
  while [ "$1" ]; do
    _k="$1"
    shift
    _v="$1"
    shift
    body="$body<$_k xsi:type=\"xsd:string\">$_v</$_k>"
  done
  body="$body</ns1:${func}>"
  _debug2 "SOAP request ${body}"

  # build SOAP XML
  _xml='<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns1="urn:'"${ns}"'" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/" SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <SOAP-ENV:Body>'"$body"'</SOAP-ENV:Body>
</SOAP-ENV:Envelope>'

  # set SOAP headers
  export _H1="SOAPAction: ${NETIM_SOAP_URL}#${func}"

  if ! response="$(_post "${_xml}" "${NETIM_SOAP_URL}")"; then
    _err "Error <$1>"
    return 1
  fi
  _debug2 "SOAP response $response"
  return 0
}

_get_root() {
  domain=$1
  filter=$(printf "%s" "$domain" | rev | cut -d . -f 1-2 | rev)
  if ! _dns_netim_soap Services queryDomainList IDSession "${NETIM_SESSION}" filter "${filter}"; then
    _debug "Cant query domain list"
    return 1
  fi

  i=1
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "<domain xsi:type=\"xsd:string\">$h</domain>"; then
      _subdomain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  _debug "$domain not found"
  return 1
}
