#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_efficientip_info='efficientip.com
Site: https://efficientip.com/
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_efficientip
Options:
  EfficientIP_Creds HTTP Basic Authentication credentials. E.g. "username:password"
  EfficientIP_Server EfficientIP SOLIDserver Management IP address or FQDN.
  EfficientIP_DNS_Name Name of the DNS smart or server hosting the zone. Optional.
  EfficientIP_View Name of the DNS view hosting the zone. Optional.
OptionsAlt:
  EfficientIP_Token_Key Alternative API token key, prefered over basic authentication.
  EfficientIP_Token_Secret Alternative API token secret, required when using a token key.
  EfficientIP_Server EfficientIP SOLIDserver Management IP address or FQDN.
  EfficientIP_DNS_Name Name of the DNS smart or server hosting the zone. Optional.
  EfficientIP_View Name of the DNS view hosting the zone. Optional.
Issues: github.com/acmesh-official/acme.sh/issues/6325
Author: EfficientIP-Labs <contact@efficientip.com>
'

dns_efficientip_add() {
  fulldomain=$1
  txtvalue=$2

  _info "Using EfficientIP API"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if { [ -z "${EfficientIP_Creds}" ] && { [ -z "${EfficientIP_Token_Key}" ] || [ -z "${EfficientIP_Token_Secret}" ]; }; } || [ -z "${EfficientIP_Server}" ]; then
    EfficientIP_Creds=""
    EfficientIP_Token_Key=""
    EfficientIP_Token_Secret=""
    EfficientIP_Server=""
    _err "You didn't specify any EfficientIP credentials or token or server (EfficientIP_Creds; EfficientIP_Token_Key; EfficientIP_Token_Secret; EfficientIP_Server)."
    _err "Please set them via EXPORT EfficientIP_Creds=username:password or EXPORT EfficientIP_server=ip/hostname"
    _err "or if you want to use Token instead EXPORT EfficientIP_Token_Key=yourkey"
    _err "and EXPORT EfficientIP_Token_Secret=yoursecret"
    _err "then try again."
    return 1
  fi

  if [ -z "${EfficientIP_DNS_Name}" ]; then
    EfficientIP_DNS_Name=""
  fi

  EfficientIP_DNSNameEncoded=$(printf "%b" "${EfficientIP_DNS_Name}" | _url_encode)

  if [ -z "${EfficientIP_View}" ]; then
    EfficientIP_View=""
  fi

  EfficientIP_ViewEncoded=$(printf "%b" "${EfficientIP_View}" | _url_encode)

  _saveaccountconf EfficientIP_Creds "${EfficientIP_Creds}"
  _saveaccountconf EfficientIP_Token_Key "${EfficientIP_Token_Key}"
  _saveaccountconf EfficientIP_Token_Secret "${EfficientIP_Token_Secret}"
  _saveaccountconf EfficientIP_Server "${EfficientIP_Server}"
  _saveaccountconf EfficientIP_DNS_Name "${EfficientIP_DNS_Name}"
  _saveaccountconf EfficientIP_View "${EfficientIP_View}"

  export _H1="Accept-Language:en-US"
  baseurlnObject="https://${EfficientIP_Server}/rest/dns_rr_add?rr_type=TXT&rr_ttl=300&rr_name=${fulldomain}&rr_value1=${txtvalue}"

  if [ "${EfficientIP_DNSNameEncoded}" != "" ]; then
    baseurlnObject="${baseurlnObject}&dns_name=${EfficientIP_DNSNameEncoded}"
  fi

  if [ "${EfficientIP_ViewEncoded}" != "" ]; then
    baseurlnObject="${baseurlnObject}&dnsview_name=${EfficientIP_ViewEncoded}"
  fi

  if [ -z "${EfficientIP_Token_Secret}" ] || [ -z "${EfficientIP_Token_Key}" ]; then
    EfficientIP_CredsEncoded=$(printf "%b" "${EfficientIP_Creds}" | _base64)
    export _H2="Authorization: Basic ${EfficientIP_CredsEncoded}"
  else
    TS=$(date +%s)
    Sig=$(printf "%b\n$TS\nPOST\n$baseurlnObject" "${EfficientIP_Token_Secret}" | _digest sha3-256 hex)
    EfficientIP_CredsEncoded=$(printf "%b:%b" "${EfficientIP_Token_Key}" "$Sig")
    export _H2="Authorization: SDS ${EfficientIP_CredsEncoded}"
    export _H3="X-SDS-TS: ${TS}"
  fi

  result="$(_post "" "${baseurlnObject}" "" "POST")"

  if [ "$(echo "${result}" | _egrep_o "ret_oid")" ]; then
    _info "DNS record successfully created"
    return 0
  else
    _err "Error creating DNS record"
    _err "${result}"
    return 1
  fi
}

# Build the EfficientIP auth headers for a single request.
# SOLIDserver's SDS token signature is computed over secret\nTS\nMETHOD\nURL,
# so it must be regenerated for every request (the URL and method differ
# between the dns_rr_list lookup and the dns_rr_delete). This helper sets
# _H1/_H2/_H3 for the given METHOD ($1) and full request URL ($2).
_efficientip_set_auth() {
  _eip_method="$1"
  _eip_url="$2"

  export _H1="Accept-Language:en-US"

  if [ -z "${EfficientIP_Token_Secret}" ] || [ -z "${EfficientIP_Token_Key}" ]; then
    EfficientIP_CredsEncoded=$(printf "%b" "${EfficientIP_Creds}" | _base64)
    export _H2="Authorization: Basic ${EfficientIP_CredsEncoded}"
    unset _H3 2>/dev/null || _H3=""
  else
    TS=$(date +%s)
    Sig=$(printf "%b\n$TS\n%s\n%s" "${EfficientIP_Token_Secret}" "${_eip_method}" "${_eip_url}" | _digest sha3-256 hex)
    EfficientIP_CredsEncoded=$(printf "%b:%b" "${EfficientIP_Token_Key}" "$Sig")
    export _H2="Authorization: SDS ${EfficientIP_CredsEncoded}"
    export _H3="X-SDS-TS: ${TS}"
  fi
}

dns_efficientip_rm() {
  fulldomain=$1
  txtvalue=$2

  _info "Using EfficientIP API"
  _debug fulldomain "${fulldomain}"
  _debug txtvalue "${txtvalue}"

  EfficientIP_ViewEncoded=$(printf "%b" "${EfficientIP_View}" | _url_encode)
  EfficientIP_DNSNameEncoded=$(printf "%b" "${EfficientIP_DNS_Name}" | _url_encode)

  # Step 1: resolve the record's rr_id.
  # On smart architectures SOLIDserver stores the FQDN in rr_full_name (the
  # relative label lives in rr_glue), so deleting by rr_name does not resolve
  # to a unique record and the API no-ops with {"connected":false}. We must
  # look the record up and delete by its unambiguous rr_id instead (this also
  # matches the vendor's own documented delete example).
  _eip_where="rr_full_name='${fulldomain}' and rr_type='TXT' and value1='${txtvalue}'"
  _eip_where_encoded=$(printf "%b" "${_eip_where}" | _url_encode)

  listurl="https://${EfficientIP_Server}/rest/dns_rr_list?WHERE=${_eip_where_encoded}"
  if [ "${EfficientIP_DNSNameEncoded}" != "" ]; then
    listurl="${listurl}&dns_name=${EfficientIP_DNSNameEncoded}"
  fi
  if [ "${EfficientIP_ViewEncoded}" != "" ]; then
    listurl="${listurl}&dnsview_name=${EfficientIP_ViewEncoded}"
  fi

  _efficientip_set_auth "GET" "${listurl}"
  listresult="$(_get "${listurl}")"
  _debug2 listresult "${listresult}"

  # Extract the first rr_id from the JSON list response.
  rr_id="$(echo "${listresult}" | _egrep_o '"rr_id" *: *"[0-9]+"' | _egrep_o '[0-9]+' | head -n 1)"

  if [ -z "${rr_id}" ]; then
    _err "Error deleting DNS record: could not find rr_id for ${fulldomain}"
    _err "${listresult}"
    return 1
  fi
  _debug rr_id "${rr_id}"

  # Step 2: delete by rr_id.
  deleteurl="https://${EfficientIP_Server}/rest/dns_rr_delete?rr_id=${rr_id}"

  _efficientip_set_auth "DELETE" "${deleteurl}"
  result="$(_post "" "${deleteurl}" "" "DELETE")"
  _debug2 result "${result}"

  if [ "$(echo "${result}" | _egrep_o "ret_oid")" ]; then
    _info "DNS Record successfully deleted"
    return 0
  else
    _err "Error deleting DNS record"
    _err "${result}"
    return 1
  fi
}
