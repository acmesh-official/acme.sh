#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_simply_info='Simply.com
Site: Simply.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_simply
Options:
 SIMPLY_AccountName Account name
 SIMPLY_ApiKey API Key
'

SIMPLY_Api="https://api.simply.com/2"

########  Public functions #####################
#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_simply_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _simply_load_config; then
    return 1
  fi

  _simply_save_config

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Adding record"

  if ! _simply_add_record "$_domain" "$_sub_domain" "$txtvalue"; then
    _err "Could not add DNS record"
    return 1
  fi
  return 0
}

dns_simply_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _simply_load_config; then
    return 1
  fi

  _simply_save_config

  _debug "Find the DNS zone"

  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _debug txtvalue "$txtvalue"

  _info "Getting all existing records"

  if ! _simply_get_all_records "$_domain"; then
    _err "invalid domain"
    return 1
  fi

  records=$(echo "$response" | tr '{' "\n" | grep 'record_id\|type\|data\|name' | sed 's/\"record_id/;\"record_id/' | tr "\n" ' ' | tr -d ' ' | tr ';' ' ')

  nr_of_deleted_records=0
  _info "Fetching txt record"

  for record in $records; do
    _debug record "$record"

    record_data=$(echo "$record" | sed -n "s/.*\"data\":\"\([^\"]*\)\".*/\1/p")
    record_type=$(echo "$record" | sed -n "s/.*\"type\":\"\([^\"]*\)\".*/\1/p")

    _debug2 record_data "$record_data"
    _debug2 record_type "$record_type"

    if [ "$record_data" = "$txtvalue" ] && [ "$record_type" = "TXT" ]; then

      record_id=$(echo "$record" | cut -d "," -f 1 | grep "record_id" | cut -d ":" -f 2)

      _info "Deleting record $record"
      _debug2 record_id "$record_id"

      if [ "$record_id" -gt 0 ]; then

        if ! _simply_delete_record "$_domain" "$record_id"; then
          _err "Record with id $record_id could not be deleted"
          return 1
        fi

        nr_of_deleted_records=1
        break
      else
        _err "Fetching record_id could not be done, this should not happen, exiting function. Failing record is $record"
        break
      fi
    fi

  done

  if [ "$nr_of_deleted_records" -eq 0 ]; then
    _err "No record deleted, the DNS record needs to be removed manually."
  else
    _info "Deleted $nr_of_deleted_records record"
  fi

  return 0
}

####################  Private functions below ##################################

_simply_load_config() {
  SIMPLY_AccountName="${SIMPLY_AccountName:-$(_readaccountconf_mutable SIMPLY_AccountName)}"
  SIMPLY_ApiKey="${SIMPLY_ApiKey:-$(_readaccountconf_mutable SIMPLY_ApiKey)}"

  if [ -z "$SIMPLY_AccountName" ] || [ -z "$SIMPLY_ApiKey" ]; then
    SIMPLY_AccountName=""
    SIMPLY_ApiKey=""

    _err "A valid Simply API account and apikey not provided."
    _err "Please provide a valid API user and try again."

    return 1
  fi

  return 0
}

_simply_save_config() {
  _saveaccountconf_mutable SIMPLY_AccountName "$SIMPLY_AccountName"
  _saveaccountconf_mutable SIMPLY_ApiKey "$SIMPLY_ApiKey"
}

_simply_get_all_records() {
  domain=$1

  if ! _simply_rest GET "my/products/$domain/dns/records/"; then
    return 1
  fi

  return 0
}

_get_root() {
  domain=$1

  if ! _simply_rest GET "my/products/"; then
    return 1
  fi

  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      return 1
    fi

    _domain=$(printf "%s" "$response" | tr '}' '\n' |
      grep "\"object\":\"$h\"\|\"name\":\"$h\"\|\"name_idn\":\"$h\"" |
      sed -n 's/.*"object":"\([^"]*\)".*/\1/p' |
      head -1)

    if [ -n "$_domain" ]; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      return 0
    fi

    _debug "No Simply.com product found for $h"
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

_simply_add_record() {
  domain=$1
  sub_domain=$2
  txtval=$3

  data="{\"name\": \"$sub_domain\", \"type\":\"TXT\", \"data\": \"$txtval\", \"priority\":0, \"ttl\": 3600}"

  if ! _simply_rest POST "my/products/$domain/dns/records/" "$data"; then
    _err "Adding record not successful!"
    return 1
  fi

  case "$_code" in
  2*) ;;
  *)
    _err "Call to API not successful (HTTP $_code), see below message for more details"
    _err "$response"
    return 1
    ;;
  esac

  return 0
}

_simply_delete_record() {
  domain=$1
  record_id=$2

  _debug record_id "Delete record with id $record_id"

  if ! _simply_rest DELETE "my/products/$domain/dns/records/$record_id/"; then
    _err "Deleting record not successful!"
    return 1
  fi

  case "$_code" in
  2*) ;;
  *)
    _err "Call to API not successful (HTTP $_code), see below message for more details"
    _err "$response"
    return 1
    ;;
  esac

  return 0
}

_simply_rest() {
  m=$1
  ep="$2"
  data="$3"

  _debug2 data "$data"
  _debug2 ep "$ep"
  _debug2 m "$m"

  basicauth=$(printf "%s:%s" "$SIMPLY_AccountName" "$SIMPLY_ApiKey" | _base64)

  if [ "$basicauth" ]; then
    export _H1="Authorization: Basic $basicauth"
  fi

  export _H2="Content-Type: application/json"

  if [ "$m" != "GET" ]; then
    response="$(_post "$data" "$SIMPLY_Api/$ep" "" "$m")"
  else
    response="$(_get "$SIMPLY_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi

  _code="$(grep -i '^HTTP/' "$HTTP_HEADER" | tail -1 | cut -d' ' -f2)"

  response="$(echo "$response" | _normalizeJson)"

  _debug2 response "$response"

  if _contains "$response" "Invalid account authorization"; then
    _err "It seems that your api key or accountnumber is not correct."
    return 1
  fi

  return 0
}
