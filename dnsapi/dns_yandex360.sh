#!/usr/bin/env sh
# Original author: non7top@gmail.com
# 07 Jul 2017
# report bugs at https://github.com/non7top/acme.sh
# Upgrade to Yandex360: ProKn1fe https://github.com/ProKn1fe

# Values to export:
# export Yandex360_Token="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
# export Yandex360_OrgID="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Sometimes cloudflare / google doesn't pick new dns records fast enough.
# You can add --dnssleep XX to params as workaround.
# I recommend at least dnssleep 900 because yandex update records too slow sometimes.

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_yandex360_add() {
  fulldomain="${1}"
  txtvalue="${2}"
  _debug "Calling: dns_yandex360_add() '${fulldomain}' '${txtvalue}'"

  _yandex360_credentials || return 1

  _yandex360_get_domain || return 1
  _debug "Found suitable domain: $domain"

  _yandex360_get_record_ids || return 1
  _debug "Record_ids: $record_ids"

  if [ -n "$record_ids" ]; then
    _info "All existing $subdomain records from $domain will be removed at the very end."
  fi

  data="{'type': 'TXT', 'name': '${subdomain}', 'ttl': 60, 'text': '${txtvalue}'}"
  uri="https://api360.yandex.net/directory/v1/org/$Yandex360_OrgID/domains/$domain/dns"
  result="$(_post "${data}" "${uri}" | _normalizeJson)"
  
  _debug "Data: $data"
  _debug "Result: $result"

  if ! _contains "$result" "$txtvalue"; then
    _err "Can't add $subdomain to $domain."
    return 1
  fi
}

#Usage: dns_myapi_rm   _acme-challenge.www.domain.com
dns_yandex360_rm() {
  fulldomain="${1}"
  _debug "Calling: dns_yandex360_rm() '${fulldomain}'"

  _yandex360_credentials || return 1

  _yandex360_get_domain "$fulldomain" || return 1
  _debug "Found suitable domain: $domain"

  _yandex360_get_record_ids "${domain}" "${subdomain}" || return 1
  _debug "Record_ids: $record_ids"

  for record_id in $record_ids; do
    uri="https://api360.yandex.net/directory/v1/org/$Yandex360_OrgID/domains/$domain/dns/$record_id"
    result="$(_post "" "${uri}" "" "DELETE" | _normalizeJson)"
    _debug "Result: $result"

    if ! _contains "$result" '{}'; then
      _info "Can't remove $subdomain from $domain."
    fi
  done
}

####################  Private functions below ##################################

_yandex360_get_domain() {
  subdomain_start=1
  while true; do
    domain_start=$(_math $subdomain_start + 1)
    domain=$(echo "$fulldomain" | cut -d . -f "$domain_start"-)
    subdomain=$(echo "$fulldomain" | cut -d . -f -"$subdomain_start")

    _debug "Checking domain $domain"
    if [ -z "$domain" ]; then
      return 1
    fi

    uri="https://api360.yandex.net/directory/v1/org/$Yandex360_OrgID/domains/$domain/dns?page=1&perPage=1000"
    result="$(_get "${uri}" | _normalizeJson)"
    _debug "Result: $result"

    if _contains "$result" '"perPage":1000'; then
      return 0
    fi
    subdomain_start=$(_math $subdomain_start + 1)
  done
}

_yandex360_credentials() {
  if [ -z "${Yandex360_Token}" ]; then
    Yandex360_Token=""
    _err "You need to export Yandex360_Token=xxxxxxxxxxxxxxxxx."
    _err "How obtain token: https://yandex.ru/dev/api360/doc/concepts/access.html."
    return 1
  else
    _saveaccountconf Yandex360_Token "${Yandex360_Token}"
  fi
  if [ -z "${Yandex360_OrgID}" ]; then
    Yandex360_Token=""
    _err "You need to export Yandex360_OrgID=xxxxxxxxxxxxxxxxx."
    _err "You can get organization id in organization page (bottom left)."
    return 1
  else
    _saveaccountconf Yandex360_OrgID "${Yandex360_OrgID}"
  fi
  export _H1="Authorization: OAuth $Yandex360_Token"
}

_yandex360_get_record_ids() {
  _debug "Check existing records for $subdomain"

  uri="https://api360.yandex.net/directory/v1/org/$Yandex360_OrgID/domains/$domain/dns?page=1&perPage=1000"
  result="$(_get "${uri}" | _normalizeJson)"
  _debug "Result: $result"

  if ! _contains "$result" '"perPage":1000'; then
    return 1
  fi

  record_ids=$(echo "$result" | _egrep_o "{[^{]*\"name\":\"${subdomain}\"[^}]*}" | sed -n -e 's#.*"recordId":\([0-9]*\).*#\1#p')
}