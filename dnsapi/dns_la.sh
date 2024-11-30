#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_la_info='dns.la
Site: dns.la
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_la
Options:
 LA_Id API ID
 LA_Key API key
Issues: github.com/acmesh-official/acme.sh/issues/4257
'

LA_Api="https://api.dns.la/api"

########  Public functions #####################

#Usage: dns_la_add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_la_add() {
  fulldomain=$1
  txtvalue=$2

  LA_Id="${LA_Id:-$(_readaccountconf_mutable LA_Id)}"
  LA_Key="${LA_Key:-$(_readaccountconf_mutable LA_Key)}"

  if [ -z "$LA_Id" ] || [ -z "$LA_Key" ]; then
    LA_Id=""
    LA_Key=""
    _err "You didn't specify a dnsla api id and key yet."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable LA_Id "$LA_Id"
  _saveaccountconf_mutable LA_Key "$LA_Key"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"
  if _la_rest "record.ashx?cmd=create&apiid=$LA_Id&apipass=$LA_Key&rtype=json&domainid=$_domain_id&host=$_sub_domain&recordtype=TXT&recorddata=$txtvalue&recordline="; then
    if _contains "$response" '"resultid":'; then
      _info "Added, OK"
      return 0
    elif _contains "$response" '"code":532'; then
      _info "Already exists, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1

}

#fulldomain txtvalue
dns_la_rm() {
  fulldomain=$1
  txtvalue=$2

  LA_Id="${LA_Id:-$(_readaccountconf_mutable LA_Id)}"
  LA_Key="${LA_Key:-$(_readaccountconf_mutable LA_Key)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  if ! _la_rest "record.ashx?cmd=listn&apiid=$LA_Id&apipass=$LA_Key&rtype=json&domainid=$_domain_id&domain=$_domain&host=$_sub_domain&recordtype=TXT&recorddata=$txtvalue"; then
    _err "Error"
    return 1
  fi

  if ! _contains "$response" '"recordid":'; then
    _info "Don't need to remove."
    return 0
  fi

  record_id=$(printf "%s" "$response" | grep '"recordid":' | cut -d : -f 2 | cut -d , -f 1 | tr -d '\r' | tr -d '\n')
  _debug "record_id" "$record_id"
  if [ -z "$record_id" ]; then
    _err "Can not get record id to remove."
    return 1
  fi
  if ! _la_rest "record.ashx?cmd=remove&apiid=$LA_Id&apipass=$LA_Key&rtype=json&domainid=$_domain_id&domain=$_domain&recordid=$record_id"; then
    _err "Delete record error."
    return 1
  fi
  _contains "$response" '"code":300'

}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _la_rest "domain.ashx?cmd=get&apiid=$LA_Id&apipass=$LA_Key&rtype=json&domain=$h"; then
      return 1
    fi

    if _contains "$response" '"domainid":'; then
      _domain_id=$(printf "%s" "$response" | grep '"domainid":' | cut -d : -f 2 | cut -d , -f 1 | tr -d '\r' | tr -d '\n')
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain="$h"
        return 0
      fi
      return 1
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

#Usage:  URI
_la_rest() {
  url="$LA_Api/$1"
  _debug "$url"

  if ! response="$(_get "$url" | tr -d ' ' | tr "}" ",")"; then
    _err "Error: $url"
    return 1
  fi

  _debug2 response "$response"
  return 0
}
