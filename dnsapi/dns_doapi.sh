#!/usr/bin/env sh

# Official Let's Encrypt API for do.de / Domain-Offensive
# 
# This is different from the dns_do adapter, because dns_do is only usable for enterprise customers
# This API is also available to private customers/individuals
# 
# Provide the required LetsEncrypt token like this: 
# DO_LETOKEN="FmD408PdqT1E269gUK57"

DO_API="https://www.do.de/api/letsencrypt"

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
