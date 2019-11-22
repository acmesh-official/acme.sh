#!/usr/bin/env sh

#
# REGRU_API_Username="test"
#
# REGRU_API_Password="test"
#
_domain=$_domain

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

  _info "Adding TXT record to ${fulldomain}"
  response="$(_get "$REGRU_API_URL/zone/add_txt?input_data={%22username%22:%22${REGRU_API_Username}%22,%22password%22:%22${REGRU_API_Password}%22,%22domains%22:[{%22dname%22:%22${_domain}%22}],%22subdomain%22:%22_acme-challenge%22,%22text%22:%22${txtvalue}%22,%22output_content_type%22:%22plain%22}&input_format=json")"

  if _contains "${response}" 'success'; then
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

  _info "Deleting resource record $fulldomain"
  response="$(_get "$REGRU_API_URL/zone/remove_record?input_data={%22username%22:%22${REGRU_API_Username}%22,%22password%22:%22${REGRU_API_Password}%22,%22domains%22:[{%22dname%22:%22${_domain}%22}],%22subdomain%22:%22_acme-challenge%22,%22content%22:%22${txtvalue}%22,%22record_type%22:%22TXT%22,%22output_content_type%22:%22plain%22}&input_format=json")"

  if _contains "${response}" 'success'; then
    return 0
  fi
  _err "Could not delete resource record, check logs"
  _err "${response}"
  return 1
}
