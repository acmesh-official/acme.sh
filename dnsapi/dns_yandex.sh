#!/usr/bin/env sh
# Author: non7top@gmail.com
# 07 Jul 2017
# report bugs at https://github.com/non7top/acme.sh

# Values to export:
# export PDD_Token="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Sometimes cloudflare / google doesn't pick new dns records fast enough.
# You can add --dnssleep XX to params as workaround.

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_yandex_add() {
  fulldomain="${1}"
  txtvalue="${2}"
  _debug "Calling: dns_yandex_add() '${fulldomain}' '${txtvalue}'"

  _PDD_credentials || return 1

  _PDD_get_domain || return 1
  _debug "Found suitable domain: $domain"

  _PDD_get_record_ids || return 1
  _debug "Record_ids: $record_ids"

  if [ -n "$record_ids" ]; then
    _info "All existing $subdomain records from $domain will be removed at the very end."
  fi

  data="domain=${domain}&type=TXT&subdomain=${subdomain}&ttl=300&content=${txtvalue}"
  uri="https://pddimp.yandex.ru/api2/admin/dns/add"
  result="$(_post "${data}" "${uri}" | _normalizeJson)"
  _debug "Result: $result"

  if ! _contains "$result" '"success":"ok"'; then
    if _contains "$result" '"success":"error"' && _contains "$result" '"error":"record_exists"'; then
      _info "Record already exists."
    else
      _err "Can't add $subdomain to $domain."
      return 1
    fi
  fi
}

#Usage: dns_myapi_rm   _acme-challenge.www.domain.com
dns_yandex_rm() {
  fulldomain="${1}"
  _debug "Calling: dns_yandex_rm() '${fulldomain}'"

  _PDD_credentials || return 1

  _PDD_get_domain "$fulldomain" || return 1
  _debug "Found suitable domain: $domain"

  _PDD_get_record_ids "${domain}" "${subdomain}" || return 1
  _debug "Record_ids: $record_ids"

  for record_id in $record_ids; do
    data="domain=${domain}&record_id=${record_id}"
    uri="https://pddimp.yandex.ru/api2/admin/dns/del"
    result="$(_post "${data}" "${uri}" | _normalizeJson)"
    _debug "Result: $result"

    if ! _contains "$result" '"success":"ok"'; then
      _info "Can't remove $subdomain from $domain."
    fi
  done
}

####################  Private functions below ##################################

_PDD_get_domain() {
  subdomain_start=1
  while true; do
    domain_start=$(_math $subdomain_start + 1)
    domain=$(echo "$fulldomain" | cut -d . -f "$domain_start"-)
    subdomain=$(echo "$fulldomain" | cut -d . -f -"$subdomain_start")

    _debug "Checking domain $domain"
    if [ -z "$domain" ]; then
      return 1
    fi

    uri="https://pddimp.yandex.ru/api2/admin/dns/list?domain=$domain"
    result="$(_get "${uri}" | _normalizeJson)"
    _debug "Result: $result"

    if _contains "$result" '"success":"ok"'; then
      return 0
    fi
    subdomain_start=$(_math $subdomain_start + 1)
  done
}

_PDD_credentials() {
  if [ -z "${PDD_Token}" ]; then
    PDD_Token=""
    _err "You need to export PDD_Token=xxxxxxxxxxxxxxxxx."
    _err "You can get it at https://pddimp.yandex.ru/api2/admin/get_token."
    return 1
  else
    _saveaccountconf PDD_Token "${PDD_Token}"
  fi
  export _H1="PddToken: $PDD_Token"
}

_PDD_get_record_ids() {
  _debug "Check existing records for $subdomain"

  uri="https://pddimp.yandex.ru/api2/admin/dns/list?domain=${domain}"
  result="$(_get "${uri}" | _normalizeJson)"
  _debug "Result: $result"

  if ! _contains "$result" '"success":"ok"'; then
    return 1
  fi

  record_ids=$(echo "$result" | _egrep_o "{[^{]*\"subdomain\":\"${subdomain}\"[^}]*}" | sed -n -e 's#.*"record_id": \([0-9]*\).*#\1#p')
}
