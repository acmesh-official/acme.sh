#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_doapi_info='Domain-Offensive do.de
 Official LetsEncrypt API for do.de / Domain-Offensive.
 This API is also available to private customers/individuals.
Site: do.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_doapi
Options:
 DO_LETOKEN LetsEncrypt Token
Issues: github.com/acmesh-official/acme.sh/issues/2057
'

DO_API="https://my.do.de/api/letsencrypt"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_doapi_add() {
  fulldomain=$1
  txtvalue=$2

  DO_LETOKEN="${DO_LETOKEN:-$(_readaccountconf_mutable DO_LETOKEN)}"
  if [ -z "$DO_LETOKEN" ]; then
    DO_LETOKEN=""
    _err "You didn't configure a do.de API token yet."
    _err "Please set DO_LETOKEN and try again."
    return 1
  fi
  _saveaccountconf_mutable DO_LETOKEN "$DO_LETOKEN"

  _info "Adding TXT record to ${fulldomain}"
  response="$(_get "$DO_API?token=$DO_LETOKEN&domain=${fulldomain}&value=${txtvalue}")"
  if _contains "${response}" 'success'; then
    return 0
  fi
  _err "Could not create resource record, check logs"
  _err "${response}"
  return 1
}

dns_doapi_rm() {
  fulldomain=$1

  DO_LETOKEN="${DO_LETOKEN:-$(_readaccountconf_mutable DO_LETOKEN)}"
  if [ -z "$DO_LETOKEN" ]; then
    DO_LETOKEN=""
    _err "You didn't configure a do.de API token yet."
    _err "Please set DO_LETOKEN and try again."
    return 1
  fi
  _saveaccountconf_mutable DO_LETOKEN "$DO_LETOKEN"

  _info "Deleting resource record $fulldomain"
  response="$(_get "$DO_API?token=$DO_LETOKEN&domain=${fulldomain}&action=delete")"
  if _contains "${response}" 'success'; then
    return 0
  fi
  _err "Could not delete resource record, check logs"
  _err "${response}"
  return 1
}
