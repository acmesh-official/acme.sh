#!/usr/bin/env sh

#Original Author: Philipp Grosswiler <philipp.grosswiler@swiss-design.net>
#v4 Update Author: Aaron W. Swenson <aaron@grandmasfridge.org>

LINODE_V4_API_URL="https://api.linode.com/v4/domains"

########  Public functions #####################

#Usage: dns_linode_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_linode_v4_add() {
  fulldomain="${1}"
  txtvalue="${2}"

  if ! _Linode_API; then
    return 1
  fi

  _info "Using Linode"
  _debug "Calling: dns_linode_add() '${fulldomain}' '${txtvalue}'"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Domain does not exist."
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _payload="{
              \"type\": \"TXT\",
              \"name\": \"$_sub_domain\",
              \"target\": \"$txtvalue\",
              \"ttl_sec\": 300
            }"

  if _rest POST "/$_domain_id/records" "$_payload" && [ -n "$response" ]; then
    _resource_id=$(printf "%s\n" "$response" | _egrep_o "\"id\": *[0-9]+" | cut -d : -f 2 | tr -d " " | _head_n 1)
    _debug _resource_id "$_resource_id"

    if [ -z "$_resource_id" ]; then
      _err "Error adding the domain resource."
      return 1
    fi

    _info "Domain resource successfully added."
    return 0
  fi

  return 1
}

#Usage: dns_linode_rm   _acme-challenge.www.domain.com
dns_linode_v4_rm() {
  fulldomain="${1}"

  if ! _Linode_API; then
    return 1
  fi

  _info "Using Linode"
  _debug "Calling: dns_linode_rm() '${fulldomain}'"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "Domain does not exist."
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  if _rest GET "/$_domain_id/records" && [ -n "$response" ]; then
    response="$(echo "$response" | tr -d "\n" | tr '{' "|" | sed 's/|/&{/g' | tr "|" "\n")"

    resource="$(echo "$response" | _egrep_o "\{.*\"name\": *\"$_sub_domain\".*}")"
    if [ "$resource" ]; then
      _resource_id=$(printf "%s\n" "$resource" | _egrep_o "\"id\": *[0-9]+" | _head_n 1 | cut -d : -f 2 | tr -d \ )
      if [ "$_resource_id" ]; then
        _debug _resource_id "$_resource_id"

        if _rest DELETE "/$_domain_id/records/$_resource_id" && [ -n "$response" ]; then
          # On 200/OK, empty set is returned. Check for error, if any.
          _error_response=$(printf "%s\n" "$response" | _egrep_o "\"errors\"" | cut -d : -f 2 | tr -d " " | _head_n 1)

          if [ -n "$_error_response" ]; then
            _err "Error deleting the domain resource: $_error_response"
            return 1
          fi

          _info "Domain resource successfully deleted."
          return 0
        fi
      fi

      return 1
    fi

    return 0
  fi

  return 1
}

####################  Private functions below ##################################

_Linode_API() {
  LINODE_V4_API_KEY="${LINODE_V4_API_KEY:-$(_readaccountconf_mutable LINODE_V4_API_KEY)}"
  if [ -z "$LINODE_V4_API_KEY" ]; then
    LINODE_V4_API_KEY=""

    _err "You didn't specify the Linode v4 API key yet."
    _err "Please create your key and try again."

    return 1
  fi

  _saveaccountconf_mutable LINODE_V4_API_KEY "$LINODE_V4_API_KEY"
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=12345
_get_root() {
  domain=$1
  i=2
  p=1

  if _rest GET; then
    response="$(echo "$response" | tr -d "\n" | tr '{' "|" | sed 's/|/&{/g' | tr "|" "\n")"
    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f $i-100)
      _debug h "$h"
      if [ -z "$h" ]; then
        #not valid
        return 1
      fi

      hostedzone="$(echo "$response" | _egrep_o "\{.*\"domain\": *\"$h\".*}")"
      if [ "$hostedzone" ]; then
        _domain_id=$(printf "%s\n" "$hostedzone" | _egrep_o "\"id\": *[0-9]+" | _head_n 1 | cut -d : -f 2 | tr -d \ )
        if [ "$_domain_id" ]; then
          _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
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

#method method action data
_rest() {
  mtd="$1"
  ep="$2"
  data="$3"

  _debug mtd "$mtd"
  _debug ep "$ep"

  export _H1="Accept: application/json"
  export _H2="Content-Type: application/json"
  export _H3="Authorization: Bearer $LINODE_V4_API_KEY"

  if [ "$mtd" != "GET" ]; then
    # both POST and DELETE.
    _debug data "$data"
    response="$(_post "$data" "$LINODE_V4_API_URL$ep" "" "$mtd")"
  else
    response="$(_get "$LINODE_V4_API_URL$ep$data")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
