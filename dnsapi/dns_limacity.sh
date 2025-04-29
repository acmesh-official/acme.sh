#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_limacity_info='lima-city.de
Site: www.lima-city.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_limacity
Options:
 LIMACITY_APIKEY API Key. Note: The API Key must have following roles: dns.admin, domains.reader
Issues: github.com/acmesh-official/acme.sh/issues/4758
Author: @Laraveluser
'

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
    _post "" "${APIBASE}/domains/${LIMACITY_DOMAINID}/records/${recordId}" "" "DELETE"
  done

  return 0
}

####################  Private functions below ##################################

_lima_get_domain_id() {
  domain="$1"
  _debug "$domain"
  i=2
  p=1

  domains=$(_get "${APIBASE}/domains.json")
  if [ "$(echo "$domains" | _egrep_o "\{.*""domains""")" ]; then
    response="$(echo "$domains" | tr -d "\n" | tr '{' "|" | sed 's/|/&{/g' | tr "|" "\n")"
    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
      _debug h "$h"
      if [ -z "$h" ]; then
        #not valid
        return 1
      fi

      hostedzone="$(echo "$response" | _egrep_o "\{.*""unicode_fqdn""[^,]+""$h"".*\}")"
      if [ "$hostedzone" ]; then
        LIMACITY_DOMAINID=$(printf "%s\n" "$hostedzone" | _egrep_o "\"id\":\s*[0-9]+" | _head_n 1 | cut -d : -f 2 | tr -d \ )
        if [ "$LIMACITY_DOMAINID" ]; then
          _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
          _domain=$h
          return 0
        fi
        return 1
      fi
      p=$i
      i=$(_math "$i" + 1)
    done
  fi
  return 1
}
