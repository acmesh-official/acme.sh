#!/usr/bin/env sh
# Author: non7top@gmail.com
# 07 Jul 2017
# report bugs at https://github.com/non7top/acme.sh

# Values to export:
# export PDD_Token="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

# Sometimes cloudflare / google doesn't pick new dns recods fast enough.
# You can add --dnssleep XX to params as workaround.

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_yandex_add() {
  local fulldomain="${1}"
  local txtvalue="${2}"
  _debug "Calling: dns_yandex_add() '${fulldomain}' '$txtvalue'"

  _PDD_credentials || return 1

  _PDD_get_domain "$fulldomain" || return 1
  _debug "Found suitable domain: $domain"

  _PDD_get_record_ids "${domain}" "${subdomain}" || return 1
  _debug "Record_ids: $record_ids"

  if [ ! -z "$record_ids" ]; then
      _err "Remove all existing $subdomain records from $domain"
      return 1
  fi

  local data="domain=${domain}&type=TXT&subdomain=${subdomain}&ttl=300&content=${txtvalue}"
  local uri="https://pddimp.yandex.ru/api2/admin/dns/add"
  local result="$(_post "${data}" "${uri}" | _normalizeJson)"
  _debug "Result: $result"

  if ! _contains "$result" '"success":"ok"'; then
      _err "Can't add $subdomain to $domain"
      return 1
  fi
}

#Usage: dns_myapi_rm   _acme-challenge.www.domain.com
dns_yandex_rm() {
  local fulldomain="${1}"
  _debug "Calling: dns_yandex_rm() '${fulldomain}'"

  _PDD_credentials || return 1

  _PDD_get_domain "$fulldomain" || return 1
  _debug "Found suitable domain: $domain"

  _PDD_get_record_ids "${domain}" "${subdomain}" || return 1
  _debug "Record_ids: $record_ids"

  for record_id in $record_ids; do
    local data="domain=${domain}&record_id=${record_id}"
    local uri="https://pddimp.yandex.ru/api2/admin/dns/del"
    local result="$(_post "${data}" "${uri}" | _normalizeJson)"
    _debug "Result: $result"

    if ! _contains "$result" '"success":"ok"'; then
      _info "Can't remove $subdomain from $domain"
    fi
  done
}

####################  Private functions below ##################################

_PDD_get_domain() {
  local fulldomain=${1}

  local subdomain_start=1
  while true; do
    local domain_start=$(_math $subdomain_start + 1)
    domain=$(echo "$fulldomain" | cut -d . -f $domain_start-)
    subdomain=$(echo "$fulldomain" | cut -d . -f -$subdomain_start)

    _debug "Checking domain $domain"
    if [ -z "$domain" ]; then
      return 1
    fi

    local uri="https://pddimp.yandex.ru/api2/admin/dns/list?domain=$domain"
    local result="$(_get "${uri}" | _normalizeJson)"
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
    _err "You need to export PDD_Token=xxxxxxxxxxxxxxxxx"
    _err "You can get it at https://pddimp.yandex.ru/api2/admin/get_token"
    return 1
  else
    _saveaccountconf PDD_Token "${PDD_Token}"
  fi
  export _H1="PddToken: $PDD_Token"
}

_PDD_get_record_ids() {
  local domain="${1}"
  local subdomain="${2}"

  _debug "Check existing records for $subdomain"

  local uri="https://pddimp.yandex.ru/api2/admin/dns/list?domain=${domain}"
  local result="$(_get "${uri}" | _normalizeJson)"
  _debug "Result: $result"

  if ! _contains "$result" '"success":"ok"'; then
      return 1
  fi

  record_ids=$(echo "$result" | _egrep_o "{[^{]*\"subdomain\":\"${subdomain}\"[^}]*}" | sed -n -e 's#.*"record_id": \([0-9]*\).*#\1#p')
}
