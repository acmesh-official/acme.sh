#!/usr/bin/env sh

# Created by Laraveluser
#
# Pass credentials before "acme.sh --issue --dns dns_limacity ..."
# --
# export LIMACITY_APIKEY="<API-KEY>"
# --
#
# Pleas note: APIKEY must have following roles: dns.admin, domains.reader

########  Public functions #####################

LIMACITY_APIKEY="${LIMACITY_APIKEY:-$(_readaccountconf_mutable LIMACITY_APIKEY)}"
AUTH=$(printf "%s" "api:$LIMACITY_APIKEY" | _base64 -w 0)
export _H1="Authorization: Basic $AUTH"
export _H2="Content-Type: application/json"
APIBASE=https://www.lima-city.de/usercp

#Usage: dns_limacity_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_limacity_add() {
  _debug LIMACITY_APIKEY "$LIMACITY_APIKEY"
  if [ "$LIMACITY_APIKEY" = "" ]; then
    _err "No Credentials given"
    return 1
  fi

  # save the dns server and key to the account conf file.
  _saveaccountconf_mutable LIMACITY_APIKEY "${LIMACITY_APIKEY}"

  fulldomain=$1
  txtvalue=$2
  if ! _lima_get_domain_id "$fulldomain"; then return 1; fi

  msg=$(_post "{\"nameserver_record\":{\"name\":\"${fulldomain}\",\"type\":\"TXT\",\"content\":\"${txtvalue}\",\"ttl\":60}}" "${APIBASE}/domains/${LIMACITY_DOMAINID}/records.json" "" "POST")
  _debug "$msg"

  if [ "$(echo "$msg" | _egrep_o "\"status\":\"ok\"")" = "" ]; then
    _err "$msg"
    return 1
  fi

  return 0
}

#Usage: dns_limacity_rm   _acme-challenge.www.domain.com
dns_limacity_rm() {

  fulldomain=$1
  txtvalue=$2
  if ! _lima_get_domain_id "$fulldomain"; then return 1; fi

  for recordId in $(_get "${APIBASE}/domains/${LIMACITY_DOMAINID}/records.json" | _egrep_o "{\"id\":[0-9]*[^}]*,\"name\":\"${fulldomain}\"" | _egrep_o "[0-9]*"); do
    _post "" "https://www.lima-city.de/usercp/domains/${LIMACITY_DOMAINID}/records/${recordId}" "" "DELETE"
  done

  return 0
}

####################  Private functions below ##################################

_lima_get_root() {
  _lima_get_root=$1
  i=1
  while true; do
    h=$(printf "%s" "$_lima_get_root" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 0
    fi

    if _contains "$h" "\."; then
      domain=$h
    fi

    i=$(_math "$i" + 1)
  done
}

_lima_get_domain_id() {
  _lima_get_root "$1"
  _debug "$domain"

  LIMACITY_DOMAINID=$(_get "${APIBASE}/domains.json" | _egrep_o "{\"id\":[0-9]*[^}]*$domain" | _egrep_o "[0-9]*")

  _debug "$LIMACITY_DOMAINID"
  if [ -z "$LIMACITY_DOMAINID" ]; then
    return 1
  fi

  return 0
}
