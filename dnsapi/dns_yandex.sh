#!/usr/bin/env sh
# Author: non7top@gmail.com
# 07 Jul 2017
# report bugs at https://github.com/non7top/acme.sh

# Values to export:
# export PDD_Token="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_yandex_add() {
  fulldomain="${1}"
  txtvalue="${2}"
  _debug "Calling: dns_yandex_add() '${fulldomain}' '${txtvalue}'"
  _PDD_credentials || return 1
  export _H1="PddToken: $PDD_Token"

  _PDD_get_domain "$fulldomain" || return 1
  _debug "Found suitable domain in pdd: $curDomain"
  curData="domain=${curDomain}&type=TXT&subdomain=${curSubdomain}&ttl=360&content=${txtvalue}"
  curUri="https://pddimp.yandex.ru/api2/admin/dns/add"
  curResult="$(_post "${curData}" "${curUri}")"
  _debug "Result: $curResult"
}

#Usage: dns_myapi_rm   _acme-challenge.www.domain.com
dns_yandex_rm() {
  fulldomain="${1}"
  _debug "Calling: dns_yandex_rm() '${fulldomain}'"
  _PDD_credentials || return 1
  export _H1="PddToken: $PDD_Token"

  _PDD_get_domain "$fulldomain" || return 1
  _debug "Found suitable domain in pdd: $curDomain"

  record_id=$(pdd_get_record_id "${fulldomain}")
  _debug "Result: $record_id"

  for rec_i in $record_id; do
    curUri="https://pddimp.yandex.ru/api2/admin/dns/del"
    curData="domain=${curDomain}&record_id=${rec_i}"
    curResult="$(_post "${curData}" "${curUri}")"
    _debug "Result: $curResult"
  done
}

####################  Private functions below ##################################

_PDD_get_domain() {
  fulldomain="${1}"
  __page=1
  __last=0
  while [ $__last -eq 0 ]; do
    uri1="https://pddimp.yandex.ru/api2/admin/domain/domains?page=${__page}&on_page=20"
    res1="$(_get "$uri1" | _normalizeJson)"
    _debug2 "res1" "$res1"
    __found="$(echo "$res1" | sed -n -e 's#.* "found": \([^,]*\),.*#\1#p')"
    _debug "found: $__found results on page"
    if [ "0$__found" -lt 20 ]; then
      _debug "last page: $__page"
      __last=1
    fi

    __all_domains="$__all_domains $(echo "$res1" | tr "," "\n" | grep '"name"' | cut -d: -f2 | sed -e 's@"@@g')"

    __page=$(_math $__page + 1)
  done

  k=2
  while [ $k -lt 10 ]; do
    __t=$(echo "$fulldomain" | cut -d . -f $k-100)
    _debug "finding zone for domain $__t"
    for d in $__all_domains; do
      if [ "$d" = "$__t" ]; then
        p=$(_math $k - 1)
        curSubdomain="$(echo "$fulldomain" | cut -d . -f "1-$p")"
        curDomain="$__t"
        return 0
      fi
    done
    k=$(_math $k + 1)
  done
  _err "No suitable domain found in your account"
  return 1
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
}

pdd_get_record_id() {
  fulldomain="${1}"

  _PDD_get_domain "$fulldomain"
  _debug "Found suitable domain in pdd: $curDomain"

  curUri="https://pddimp.yandex.ru/api2/admin/dns/list?domain=${curDomain}"
  curResult="$(_get "${curUri}" | _normalizeJson)"
  _debug "Result: $curResult"
  echo "$curResult" | _egrep_o "{[^{]*\"content\":[^{]*\"subdomain\":\"${curSubdomain}\"" | sed -n -e 's#.* "record_id": \(.*\),[^,]*#\1#p'
}
