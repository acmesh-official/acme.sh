#!/usr/bin/env sh

#
#HETZNER_Token="sdfsdfsdfljlbjkljlkjsdfoiwje"
#

HETZNER_Api="https://dns.hetzner.com/api/v1"

########  Public functions #####################

# Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
# Ref: https://dns.hetzner.com/api-docs/
dns_hetzner_add() {
  full_domain=$1
  txt_value=$2

  HETZNER_Token="${HETZNER_Token:-$(_readaccountconf_mutable HETZNER_Token)}"

  if [ -z "$HETZNER_Token" ]; then
    HETZNER_Token=""
    _err "You didn't specify a Hetzner api token."
    _err "You can get yours from here https://dns.hetzner.com/settings/api-token."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf_mutable HETZNER_Token "$HETZNER_Token"

  _debug "First detect the root zone"

  if ! _get_root "$full_domain"; then
    _err "Invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting TXT records"
  if ! _find_record "$_sub_domain" "$txt_value"; then
    return 1
  fi

  if [ -z "$_record_id" ]; then
    _info "Adding record"
    if _hetzner_rest POST "records" "{\"zone_id\":\"${HETZNER_Zone_ID}\",\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"value\":\"$txt_value\",\"ttl\":120}"; then
      if _contains "$response" "$txt_value"; then
        _info "Record added, OK"
        _sleep 2
        return 0
      fi
    fi
    _err "Add txt record error${_response_error}"
    return 1
  else
    _info "Found record id: $_record_id."
    _info "Record found, do nothing."
    return 0
    # we could modify a record, if the names for txt records for *.example.com and example.com would be not the same
    #if _hetzner_rest PUT "records/${_record_id}" "{\"zone_id\":\"${HETZNER_Zone_ID}\",\"type\":\"TXT\",\"name\":\"$full_domain\",\"value\":\"$txt_value\",\"ttl\":120}"; then
    #  if _contains "$response" "$txt_value"; then
    #    _info "Modified, OK"
    #    return 0
    #  fi
    #fi
    #_err "Add txt record error (modify)."
    #return 1
  fi
}

# Usage: full_domain txt_value
# Used to remove the txt record after validation
dns_hetzner_rm() {
  full_domain=$1
  txt_value=$2

  HETZNER_Token="${HETZNER_Token:-$(_readaccountconf_mutable HETZNER_Token)}"

  _debug "First detect the root zone"
  if ! _get_root "$full_domain"; then
    _err "Invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting TXT records"
  if ! _find_record "$_sub_domain" "$txt_value"; then
    return 1
  fi

  if [ -z "$_record_id" ]; then
    _info "Remove not needed. Record not found."
  else
    if ! _hetzner_rest DELETE "records/$_record_id"; then
      _err "Delete record error${_response_error}"
      return 1
    fi
    _sleep 2
    _info "Record deleted"
  fi
}

####################  Private functions below ##################################
#returns
# _record_id=a8d58f22d6931bf830eaa0ec6464bf81  if found; or 1 if error
_find_record() {
  unset _record_id
  _record_name=$1
  _record_value=$2

  if [ -z "$_record_value" ]; then
    _record_value='[^"]*'
  fi

  _debug "Getting all records"
  _hetzner_rest GET "records?zone_id=${_domain_id}"

  if _response_has_error; then
    _err "Error${_response_error}"
    return 1
  else
    _record_id=$(
      echo "$response" |
        grep -o "{[^\{\}]*\"name\":\"$_record_name\"[^\}]*}" |
        grep "\"value\":\"$_record_value\"" |
        while read -r record; do
          # test for type and
          if [ -n "$(echo "$record" | _egrep_o '"type":"TXT"')" ]; then
            echo "$record" | _egrep_o '"id":"[^"]*"' | cut -d : -f 2 | tr -d \"
            break
          fi
        done
    )
  fi
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=1
  p=1

  domain_without_acme=$(echo "$domain" | cut -d . -f 2-)
  domain_param_name=$(echo "HETZNER_Zone_ID_for_${domain_without_acme}" | sed 's/[\.\-]/_/g')

  _debug "Reading zone_id for '$domain_without_acme' from config..."
  HETZNER_Zone_ID=$(_readdomainconf "$domain_param_name")
  if [ "$HETZNER_Zone_ID" ]; then
    _debug "Found, using: $HETZNER_Zone_ID"
    if ! _hetzner_rest GET "zones/${HETZNER_Zone_ID}"; then
      _debug "Zone with id '$HETZNER_Zone_ID' does not exist."
      _cleardomainconf "$domain_param_name"
      unset HETZNER_Zone_ID
    else
      if _contains "$response" "\"id\":\"$HETZNER_Zone_ID\""; then
        _domain=$(printf "%s\n" "$response" | _egrep_o '"name":"[^"]*"' | cut -d : -f 2 | tr -d \" | head -n 1)
        if [ "$_domain" ]; then
          _cut_length=$((${#domain} - ${#_domain} - 1))
          _sub_domain=$(printf "%s" "$domain" | cut -c "1-$_cut_length")
          _domain_id="$HETZNER_Zone_ID"
          return 0
        else
          return 1
        fi
      else
        return 1
      fi
    fi
  fi

  _debug "Trying to get zone id by domain name for '$domain_without_acme'."
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi
    _debug h "$h"

    _hetzner_rest GET "zones?name=$h"

    if _contains "$response" "\"name\":\"$h\"" || _contains "$response" '"total_entries":1'; then
      _domain_id=$(echo "$response" | _egrep_o "\[.\"id\":\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \")
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
        _domain=$h
        HETZNER_Zone_ID=$_domain_id
        _savedomainconf "$domain_param_name" "$HETZNER_Zone_ID"
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

#returns
# _response_error
_response_has_error() {
  unset _response_error

  err_part="$(echo "$response" | _egrep_o '"error":{[^}]*}')"

  if [ -n "$err_part" ]; then
    err_code=$(echo "$err_part" | _egrep_o '"code":[0-9]+' | cut -d : -f 2)
    err_message=$(echo "$err_part" | _egrep_o '"message":"[^"]+"' | cut -d : -f 2 | tr -d \")

    if [ -n "$err_code" ] && [ -n "$err_message" ]; then
      _response_error=" - message: ${err_message}, code: ${err_code}"
      return 0
    fi
  fi

  return 1
}

#returns
# response
_hetzner_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  key_trimmed=$(echo "$HETZNER_Token" | tr -d \")

  export _H1="Content-TType: application/json"
  export _H2="Auth-API-Token: $key_trimmed"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$HETZNER_Api/$ep" "" "$m")"
  else
    response="$(_get "$HETZNER_Api/$ep")"
  fi

  if [ "$?" != "0" ] || _response_has_error; then
    _debug "Error$_response_error"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
