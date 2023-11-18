#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_nanelo_info='Nanelo.com
Site: Nanelo.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_nanelo
Options:
 NANELO_TOKEN API Token
Issues: github.com/acmesh-official/acme.sh/issues/4519
'

NANELO_API="https://api.nanelo.com/v1/"

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nanelo_add() {
  fulldomain=$1
  txtvalue=$2

  NANELO_TOKEN="${NANELO_TOKEN:-$(_readaccountconf_mutable NANELO_TOKEN)}"
  if [ -z "$NANELO_TOKEN" ]; then
    NANELO_TOKEN=""
    _err "You didn't configure a Nanelo API Key yet."
    _err "Please set NANELO_TOKEN and try again."
    _err "Login to Nanelo.com and go to Settings > API Keys to get a Key"
    return 1
  fi
  _saveaccountconf_mutable NANELO_TOKEN "$NANELO_TOKEN"

  _info "Adding TXT record to ${fulldomain}"
  response="$(_get "$NANELO_API$NANELO_TOKEN/dns/addrecord?type=TXT&ttl=60&name=${fulldomain}&value=${txtvalue}")"
  if _contains "${response}" 'success'; then
    return 0
  fi
  _err "Could not create resource record, please check the logs"
  _err "${response}"
  return 1
}

dns_nanelo_rm() {
  fulldomain=$1
  txtvalue=$2

  NANELO_TOKEN="${NANELO_TOKEN:-$(_readaccountconf_mutable NANELO_TOKEN)}"
  if [ -z "$NANELO_TOKEN" ]; then
    NANELO_TOKEN=""
    _err "You didn't configure a Nanelo API Key yet."
    _err "Please set NANELO_TOKEN and try again."
    _err "Login to Nanelo.com and go to Settings > API Keys to get a Key"
    return 1
  fi
  _saveaccountconf_mutable NANELO_TOKEN "$NANELO_TOKEN"

  _info "Deleting resource record $fulldomain"
  response="$(_get "$NANELO_API$NANELO_TOKEN/dns/deleterecord?type=TXT&ttl=60&name=${fulldomain}&value=${txtvalue}")"
  if _contains "${response}" 'success'; then
    return 0
  fi
  _err "Could not delete resource record, please check the logs"
  _err "${response}"
  return 1
}
