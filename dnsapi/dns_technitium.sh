#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_technitium_info='Technitium DNS Server
Site: Technitium.com/dns/
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_technitium
Options:
 Technitium_Server Server Address
 Technitium_Token API Token
Issues: github.com/acmesh-official/acme.sh/issues/6116
Author: Henning Reich <acmesh@qupfer.de>
'

dns_technitium_add() {
  _info "add txt Record using Technitium"
  _Technitium_account
  fulldomain=$1
  txtvalue=$2
  response="$(_get "$Technitium_Server/api/zones/records/add?token=$Technitium_Token&domain=$fulldomain&type=TXT&text=${txtvalue}")"
  if _contains "$response" '"status":"ok"'; then
    return 0
  fi
  _err "Could not add txt record."
  return 1
}

dns_technitium_rm() {
  _info "remove txt record using Technitium"
  _Technitium_account
  fulldomain=$1
  txtvalue=$2
  response="$(_get "$Technitium_Server/api/zones/records/delete?token=$Technitium_Token&domain=$fulldomain&type=TXT&text=${txtvalue}")"
  if _contains "$response" '"status":"ok"'; then
    return 0
  fi
  _err "Could not remove txt record"
  return 1
}

####################  Private functions below ##################################

_Technitium_account() {
  Technitium_Server="${Technitium_Server:-$(_readaccountconf_mutable Technitium_Server)}"
  Technitium_Token="${Technitium_Token:-$(_readaccountconf_mutable Technitium_Token)}"
  if [ -z "$Technitium_Server" ] || [ -z "$Technitium_Token" ]; then
    Technitium_Server=""
    Technitium_Token=""
    _err "You don't specify Technitium Server and Token yet."
    _err "Please create your Token and add server address and try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable Technitium_Server "$Technitium_Server"
  _saveaccountconf_mutable Technitium_Token "$Technitium_Token"
}
