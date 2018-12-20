#!/usr/bin/env sh

#Author: Philipp Grosswiler <philipp.grosswiler@swiss-design.net>

LINODE_API_URL="https://api.linode.com/?api_key=$LINODE_API_KEY&api_action="

########  Public functions #####################

#Usage: dns_linode_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_linode_add() {
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

  _parameters="&DomainID=$_domain_id&Type=TXT&Name=$_sub_domain&Target=$txtvalue"

  if _rest GET "domain.resource.create" "$_parameters" && [ -n "$response" ]; then
    _resource_id=$(printf "%s\n" "$response" | _egrep_o "\"ResourceID\":\s*[0-9]+" | cut -d : -f 2 | tr -d " " | _head_n 1)
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
dns_linode_rm() {
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

  _parameters="&DomainID=$_domain_id"

  if _rest GET "domain.resource.list" "$_parameters" && [ -n "$response" ]; then
    response="$(echo "$response" | tr -d "\n" | tr '{' "|" | sed 's/|/&{/g' | tr "|" "\n")"

    resource="$(echo "$response" | _egrep_o "{.*\"NAME\":\s*\"$_sub_domain\".*}")"
    if [ "$resource" ]; then
      _resource_id=$(printf "%s\n" "$resource" | _egrep_o "\"RESOURCEID\":\s*[0-9]+" | _head_n 1 | cut -d : -f 2 | tr -d \ )
      if [ "$_resource_id" ]; then
        _debug _resource_id "$_resource_id"

        _parameters="&DomainID=$_domain_id&ResourceID=$_resource_id"

        if _rest GET "domain.resource.delete" "$_parameters" && [ -n "$response" ]; then
          _resource_id=$(printf "%s\n" "$response" | _egrep_o "\"ResourceID\":\s*[0-9]+" | cut -d : -f 2 | tr -d " " | _head_n 1)
          _debug _resource_id "$_resource_id"

          if [ -z "$_resource_id" ]; then
            _err "Error deleting the domain resource."
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
  if [ -z "$LINODE_API_KEY" ]; then
    LINODE_API_KEY=""

    _err "You didn't specify the Linode API key yet."
    _err "Please create your key and try again."

    return 1
  fi

  _saveaccountconf LINODE_API_KEY "$LINODE_API_KEY"
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

  if _rest GET "domain.list"; then
    response="$(echo "$response" | tr -d "\n" | tr '{' "|" | sed 's/|/&{/g' | tr "|" "\n")"
    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f $i-100)
      _debug h "$h"
      if [ -z "$h" ]; then
        #not valid
        return 1
      fi

      hostedzone="$(echo "$response" | _egrep_o "{.*\"DOMAIN\":\s*\"$h\".*}")"
      if [ "$hostedzone" ]; then
        _domain_id=$(printf "%s\n" "$hostedzone" | _egrep_o "\"DOMAINID\":\s*[0-9]+" | _head_n 1 | cut -d : -f 2 | tr -d \ )
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

  if [ "$mtd" != "GET" ]; then
    # both POST and DELETE.
    _debug data "$data"
    response="$(_post "$data" "$LINODE_API_URL$ep" "" "$mtd")"
  else
    response="$(_get "$LINODE_API_URL$ep$data")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
