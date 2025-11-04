#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_dnshome_info='dnsHome.de
Site: dnsHome.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_dnshome
Options:
 DNSHOME_Subdomain Subdomain
 DNSHOME_SubdomainPassword Subdomain Password
Issues: github.com/acmesh-official/acme.sh/issues/3819
Author: @dnsHome-de
'

# Usage: add subdomain.ddnsdomain.tld "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_dnshome_add() {
  txtvalue=$2

  DNSHOME_Subdomain="${DNSHOME_Subdomain:-$(_readdomainconf DNSHOME_Subdomain)}"
  DNSHOME_SubdomainPassword="${DNSHOME_SubdomainPassword:-$(_readdomainconf DNSHOME_SubdomainPassword)}"

  if [ -z "$DNSHOME_Subdomain" ] || [ -z "$DNSHOME_SubdomainPassword" ]; then
    DNSHOME_Subdomain=""
    DNSHOME_SubdomainPassword=""
    _err "Please specify/export your dnsHome.de Subdomain and Password"
    return 1
  fi

  #save the credentials to the account conf file.
  _savedomainconf DNSHOME_Subdomain "$DNSHOME_Subdomain"
  _savedomainconf DNSHOME_SubdomainPassword "$DNSHOME_SubdomainPassword"

  DNSHOME_Api="https://$DNSHOME_Subdomain:$DNSHOME_SubdomainPassword@www.dnshome.de/dyndns.php"

  _DNSHOME_rest POST "acme=add&txt=$txtvalue"
  if ! echo "$response" | grep 'successfully' >/dev/null; then
    _err "Error"
    _err "$response"
    return 1
  fi

  return 0
}

# Usage: txtvalue
# Used to remove the txt record after validation
dns_dnshome_rm() {
  txtvalue=$2

  DNSHOME_Subdomain="${DNSHOME_Subdomain:-$(_readdomainconf DNSHOME_Subdomain)}"
  DNSHOME_SubdomainPassword="${DNSHOME_SubdomainPassword:-$(_readdomainconf DNSHOME_SubdomainPassword)}"

  DNSHOME_Api="https://$DNSHOME_Subdomain:$DNSHOME_SubdomainPassword@www.dnshome.de/dyndns.php"

  if [ -z "$DNSHOME_Subdomain" ] || [ -z "$DNSHOME_SubdomainPassword" ]; then
    DNSHOME_Subdomain=""
    DNSHOME_SubdomainPassword=""
    _err "Please specify/export your dnsHome.de Subdomain and Password"
    return 1
  fi

  _DNSHOME_rest POST "acme=rm&txt=$txtvalue"
  if ! echo "$response" | grep 'successfully' >/dev/null; then
    _err "Error"
    _err "$response"
    return 1
  fi

  return 0
}

####################  Private functions below ##################################
_DNSHOME_rest() {
  method=$1
  data="$2"
  _debug "$data"

  _debug data "$data"
  response="$(_post "$data" "$DNSHOME_Api" "" "$method")"

  if [ "$?" != "0" ]; then
    _err "error $data"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
