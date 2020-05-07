#!/usr/bin/env sh

#
#NJALLA_Token="sdfsdfsdfljlbjkljlkjsdfoiwje"

NJALLA_Api="https://njal.la/api/1/"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_njalla_add() {
  fulldomain=$1
  txtvalue=$2

  NJALLA_Token="${NJALLA_Token:-$(_readaccountconf_mutable NJALLA_Token)}"

  if [ "$NJALLA_Token" ]; then
    _saveaccountconf_mutable NJALLA_Token "$NJALLA_Token"
  else
    NJALLA_Token=""
    _err "You didn't specify a Njalla api token yet."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  # For wildcard cert, the main root domain and the wildcard domain have the same txt subdomain name, so
  # we can not use updating anymore.
  #  count=$(printf "%s\n" "$response" | _egrep_o "\"count\":[^,]*" | cut -d : -f 2)
  #  _debug count "$count"
  #  if [ "$count" = "0" ]; then
  _info "Adding record"
  if _njalla_rest "{\"method\":\"add-record\",\"params\":{\"domain\":\"$_domain\",\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"content\":\"$txtvalue\",\"ttl\":120}}"; then
    if _contains "$response" "$txtvalue"; then
      _info "Added, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1

}

#fulldomain txtvalue
dns_njalla_rm() {
  fulldomain=$1
  txtvalue=$2

  NJALLA_Token="${NJALLA_Token:-$(_readaccountconf_mutable NJALLA_Token)}"

  if [ "$NJALLA_Token" ]; then
    _saveaccountconf_mutable NJALLA_Token "$NJALLA_Token"
  else
    NJALLA_Token=""
    _err "You didn't specify a Njalla api token yet."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting records for domain"
  if ! _njalla_rest "{\"method\":\"list-records\",\"params\":{\"domain\":\"${_domain}\"}}"; then
    return 1
  fi

  if ! echo "$response" | tr -d " " | grep "\"id\":" >/dev/null; then
    _err "Error: $response"
    return 1
  fi

  records=$(echo "$response" | _egrep_o "\"records\":\s?\[(.*)\]\}" | _egrep_o "\[.*\]" | _egrep_o "\{[^\{\}]*\"id\":[^\{\}]*\}")
  count=$(echo "$records" | wc -l)
  _debug count "$count"

  if [ "$count" = "0" ]; then
    _info "Don't need to remove."
  else
    echo "$records" | while read -r record; do
      record_name=$(echo "$record" | _egrep_o "\"name\":\s?\"[^\"]*\"" | cut -d : -f 2 | tr -d " " | tr -d \")
      record_content=$(echo "$record" | _egrep_o "\"content\":\s?\"[^\"]*\"" | cut -d : -f 2 | tr -d " " | tr -d \")
      record_id=$(echo "$record" | _egrep_o "\"id\":\s?[0-9]+" | cut -d : -f 2 | tr -d " " | tr -d \")
      if [ "$_sub_domain" = "$record_name" ]; then
        if [ "$txtvalue" = "$record_content" ]; then
          _debug "record_id" "$record_id"
          if ! _njalla_rest "{\"method\":\"remove-record\",\"params\":{\"domain\":\"${_domain}\",\"id\":${record_id}}}"; then
            _err "Delete record error."
            return 1
          fi
          echo "$response" | tr -d " " | grep "\"result\"" >/dev/null
        fi
      fi
    done
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
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    if ! _njalla_rest "{\"method\":\"get-domain\",\"params\":{\"domain\":\"${h}\"}}"; then
      return 1
    fi

    if _contains "$response" "\"$h\""; then
      _domain_returned=$(echo "$response" | _egrep_o "\{\"name\": *\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \" | tr -d " ")
      if [ "$_domain_returned" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_njalla_rest() {
  data="$1"

  token_trimmed=$(echo "$NJALLA_Token" | tr -d '"')

  export _H1="Content-Type: application/json"
  export _H2="Accept: application/json"
  export _H3="Authorization: Njalla $token_trimmed"

  _debug data "$data"
  response="$(_post "$data" "$NJALLA_Api" "" "POST")"

  if [ "$?" != "0" ]; then
    _err "error $data"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
