#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_zoneedit_info='ZoneEdit.com
Site: ZoneEdit.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_zoneedit
Options:
 ZONEEDIT_ID ID
 ZONEEDIT_Token API Token
Issues: github.com/acmesh-official/acme.sh/issues/6135
'

# https://github.com/blueslow/sslcertzoneedit

########  Public functions #####################

# Usage: dns_zoneedit_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_zoneedit_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using ZoneEdit"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  # Load the credentials from the account conf file
  ZONEEDIT_ID="${ZONEEDIT_ID:-$(_readaccountconf_mutable ZONEEDIT_ID)}"
  ZONEEDIT_Token="${ZONEEDIT_Token:-$(_readaccountconf_mutable ZONEEDIT_Token)}"
  if [ -z "$ZONEEDIT_ID" ] || [ -z "$ZONEEDIT_Token" ]; then
    ZONEEDIT_ID=""
    ZONEEDIT_Token=""
    _err "Please specify ZONEEDIT_ID and _Token."
    _err "Please export as ZONEEDIT_ID and ZONEEDIT_Token then try again."
    return 1
  fi

  # Save the credentials to the account conf file
  _saveaccountconf_mutable ZONEEDIT_ID "$ZONEEDIT_ID"
  _saveaccountconf_mutable ZONEEDIT_Token "$ZONEEDIT_Token"

  if _zoneedit_api "CREATE" "$fulldomain" "$txtvalue"; then
    _info "Added, OK"
    return 0
  else
    _err "Add txt record error."
    return 1
  fi
}

# Usage: dns_zoneedit_rm   fulldomain   txtvalue
dns_zoneedit_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using ZoneEdit"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  # Load the credentials from the account conf file
  ZONEEDIT_ID="${ZONEEDIT_ID:-$(_readaccountconf_mutable ZONEEDIT_ID)}"
  ZONEEDIT_Token="${ZONEEDIT_Token:-$(_readaccountconf_mutable ZONEEDIT_Token)}"
  if [ -z "$ZONEEDIT_ID" ] || [ -z "$ZONEEDIT_Token" ]; then
    ZONEEDIT_ID=""
    ZONEEDIT_Token=""
    _err "Please specify ZONEEDIT_ID and _Token."
    _err "Please export as ZONEEDIT_ID and ZONEEDIT_Token then try again."
    return 1
  fi

  if _zoneedit_api "DELETE" "$fulldomain" "$txtvalue"; then
    _info "Deleted, OK"
    return 0
  else
    _err "Delete txt record error."
    return 1
  fi
}

####################  Private functions below ##################################

#Usage: _zoneedit_api   <CREATE|DELETE>   fulldomain   txtvalue
_zoneedit_api() {
  cmd=$1
  fulldomain=$2
  txtvalue=$3

  # Construct basic authorization header
  credentials=$(printf "%s:%s" "$ZONEEDIT_ID" "$ZONEEDIT_Token" | _base64)
  export _H1="Authorization: Basic ${credentials}"

  # Generate request URL
  case "$cmd" in
  "CREATE")
    # https://dynamic.zoneedit.com/txt-create.php?host=_acme-challenge.example.com&rdata=depE1VF_xshMm1IVY1Y56Kk9Zb_7jA2VFkP65WuNgu8W
    geturl="https://dynamic.zoneedit.com/txt-create.php?host=${fulldomain}&rdata=${txtvalue}"
    ;;
  "DELETE")
    # https://dynamic.zoneedit.com/txt-delete.php?host=_acme-challenge.example.com&rdata=depE1VF_xshMm1IVY1Y56Kk9Zb_7jA2VFkP65WuNgu8W
    geturl="https://dynamic.zoneedit.com/txt-delete.php?host=${fulldomain}&rdata=${txtvalue}"
    ze_sleep=2
    ;;
  *)
    _err "Unknown parameter : $cmd"
    return 1
    ;;
  esac

  # Execute request
  i=3 # Tries
  while [ "$i" -gt 0 ]; do
    i=$(_math "$i" - 1)

    if ! response=$(_get "$geturl"); then
      _err "_get() failed ($response)"
      return 1
    fi
    _debug2 response "$response"
    if _contains "$response" "SUCCESS.*200"; then
      # Sleep (when needed) to work around a Zonedit API bug
      # https://forum.zoneedit.com/threads/automating-changes-of-txt-records-in-dns.7394/page-2#post-23855
      if [ "$ze_sleep" ]; then _sleep "$ze_sleep"; fi
      return 0
    elif _contains "$response" "ERROR.*Minimum.*seconds"; then
      _info "ZoneEdit responded with a rate limit of..."
      ze_ratelimit=$(echo "$response" | sed -n 's/.*Minimum \([0-9]\+\) seconds.*/\1/p')
      if [ "$ze_ratelimit" ] && [ ! "$(echo "$ze_ratelimit" | tr -d '0-9')" ]; then
        _info "$ze_ratelimit seconds."
      else
        _err "$response"
        _err "not a number, or blank ($ze_ratelimit), API change?"
        unset ze_ratelimit
      fi
    else
      _err "$response"
      _err "Unknown response, API change?"
    fi

    # Retry
    if [ "$i" -lt 1 ]; then
      _err "Tries exceeded, giving up."
      return 1
    fi
    if [ "$ze_ratelimit" ]; then
      _info "Waiting $ze_ratelimit seconds..."
      _sleep "$ze_ratelimit"
    else
      _err "Going to retry after 10 seconds..."
      _sleep 10
    fi
  done
  return 1
}
