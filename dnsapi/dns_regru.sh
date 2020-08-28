#!/usr/bin/env sh

#
# REGRU_API_Username="test"
#
# REGRU_API_Password="test"
#

REGRU_API_URL="https://api.reg.ru/api/regru2"

########  Public functions #####################

dns_regru_add() {
  fulldomain=$1
  txtvalue=$2

  REGRU_API_Username="${REGRU_API_Username:-$(_readaccountconf_mutable REGRU_API_Username)}"
  REGRU_API_Password="${REGRU_API_Password:-$(_readaccountconf_mutable REGRU_API_Password)}"
  if [ -z "$REGRU_API_Username" ] || [ -z "$REGRU_API_Password" ]; then
    REGRU_API_Username=""
    REGRU_API_Password=""
    _err "You don't specify regru password or username."
    return 1
  fi

  _saveaccountconf_mutable REGRU_API_Username "$REGRU_API_Username"
  _saveaccountconf_mutable REGRU_API_Password "$REGRU_API_Password"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain "$_domain"

  _subdomain=$(echo "$fulldomain" | sed -r "s/.$_domain//")
  _debug _subdomain "$_subdomain"

  _info "Adding TXT record to ${fulldomain}"
  _regru_rest POST "zone/add_txt" "input_data={%22username%22:%22${REGRU_API_Username}%22,%22password%22:%22${REGRU_API_Password}%22,%22domains%22:[{%22dname%22:%22${_domain}%22}],%22subdomain%22:%22${_subdomain}%22,%22text%22:%22${txtvalue}%22,%22output_content_type%22:%22plain%22}&input_format=json"

  if ! _contains "${response}" 'error'; then
    return 0
  fi
  _err "Could not create resource record, check logs"
  _err "${response}"
  return 1
}

dns_regru_rm() {
  fulldomain=$1
  txtvalue=$2

  REGRU_API_Username="${REGRU_API_Username:-$(_readaccountconf_mutable REGRU_API_Username)}"
  REGRU_API_Password="${REGRU_API_Password:-$(_readaccountconf_mutable REGRU_API_Password)}"
  if [ -z "$REGRU_API_Username" ] || [ -z "$REGRU_API_Password" ]; then
    REGRU_API_Username=""
    REGRU_API_Password=""
    _err "You don't specify regru password or username."
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain "$_domain"

  _subdomain=$(echo "$fulldomain" | sed -r "s/.$_domain//")
  _debug _subdomain "$_subdomain"

  _info "Deleting resource record $fulldomain"
  _regru_rest POST "zone/remove_record" "input_data={%22username%22:%22${REGRU_API_Username}%22,%22password%22:%22${REGRU_API_Password}%22,%22domains%22:[{%22dname%22:%22${_domain}%22}],%22subdomain%22:%22${_subdomain}%22,%22content%22:%22${txtvalue}%22,%22record_type%22:%22TXT%22,%22output_content_type%22:%22plain%22}&input_format=json"

  if ! _contains "${response}" 'error'; then
    return 0
  fi
  _err "Could not delete resource record, check logs"
  _err "${response}"
  return 1
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _domain=domain.com
_get_root() {
  domain=$1

  _regru_rest POST "service/get_list" "username=${REGRU_API_Username}&password=${REGRU_API_Password}&output_format=xml&servtype=domain"
  domains_list=$(echo "${response}" | grep dname | sed -r "s/.*dname=\"([^\"]+)\".*/\\1/g")

  for ITEM in ${domains_list}; do
    case "${domain}" in
    *${ITEM}*)
      _domain=${ITEM}
      _debug _domain "${_domain}"
      return 0
      ;;
    esac
  done

  return 1
}

#returns
# response
_regru_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Content-Type: application/x-www-form-urlencoded"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$REGRU_API_URL/$ep" "" "$m")"
  else
    response="$(_get "$REGRU_API_URL/$ep?$data")"
  fi

  _debug response "${response}"
  return 0
}
