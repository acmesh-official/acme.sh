#!/usr/bin/env sh

# bug reports to dev@1e.ca

#
#NS1_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#

NS1_Api="https://api.nsone.net/v1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_nsone_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$NS1_Key" ]; then
    NS1_Key=""
    _err "You didn't specify nsone dns api key yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf NS1_Key "$NS1_Key"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _nsone_rest GET "zones/${_domain}"

  if ! _contains "$response" "\"records\":"; then
    _err "Error"
    return 1
  fi

  count=$(printf "%s\n" "$response" | _egrep_o "\"domain\":\"$fulldomain\",[^{]*\"type\":\"TXT\"" | wc -l | tr -d " ")
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Adding record"

    if _nsone_rest PUT "zones/$_domain/$fulldomain/TXT" "{\"answers\":[{\"answer\":[\"$txtvalue\"]}],\"type\":\"TXT\",\"domain\":\"$fulldomain\",\"zone\":\"$_domain\",\"ttl\":0}"; then
      if _contains "$response" "$fulldomain"; then
        _info "Added"
        #todo: check if the record takes effect
        return 0
      else
        _err "Add txt record error."
        return 1
      fi
    fi
    _err "Add txt record error."
  else
    _info "Updating record"
    prev_txt=$(printf "%s\n" "$response" | _egrep_o "\"domain\":\"$fulldomain\",\"short_answers\":\[\"[^,]*\]" | _head_n 1 | cut -d: -f3 | cut -d, -f1)
    _debug "prev_txt" "$prev_txt"

    _nsone_rest POST "zones/$_domain/$fulldomain/TXT" "{\"answers\": [{\"answer\": [\"$txtvalue\"]},{\"answer\": $prev_txt}],\"type\": \"TXT\",\"domain\":\"$fulldomain\",\"zone\": \"$_domain\",\"ttl\":0}"
    if [ "$?" = "0" ] && _contains "$response" "$fulldomain"; then
      _info "Updated!"
      #todo: check if the record takes effect
      return 0
    fi
    _err "Update error"
    return 1
  fi

}

#fulldomain
dns_nsone_rm() {
  fulldomain=$1
  txtvalue=$2
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  _nsone_rest GET "zones/${_domain}/$fulldomain/TXT"

  count=$(printf "%s\n" "$response" | _egrep_o "\"domain\":\"$fulldomain\",.*\"type\":\"TXT\"" | wc -l | tr -d " ")
  _debug count "$count"
  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
  else
    if ! _nsone_rest DELETE "zones/${_domain}/$fulldomain/TXT"; then
      _err "Delete record error."
      return 1
    fi
    _contains "$response" ""
  fi
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=2
  p=1
  if ! _nsone_rest GET "zones"; then
    return 1
  fi
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if _contains "$response" "\"zone\":\"$h\""; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_nsone_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Accept: application/json"
  export _H2="X-NSONE-Key: $NS1_Key"
  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$NS1_Api/$ep" "" "$m")"
  else
    response="$(_get "$NS1_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
