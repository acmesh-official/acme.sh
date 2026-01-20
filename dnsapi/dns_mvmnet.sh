#!/bin/bash
# shellcheck disable=SC2034
dns_mvmnet_info='mvmnet.com
Site: mvmnet.com
Docs: https://api.mvmnet.com/api/1.0/documentation/
Options:
 MVMNET_ID application_id
 MVMNET_KEY application_key
 MVMNET_SEED application_seed
Author: Matteo Gaggiano <github.com/marchrius>
'

if [ "$STAGE" = "1" ]; then ## STAGING
  MVMNET_API_URL="https://api.mvmnet.com/ote/1.0"
else ## LIVE
  MVMNET_API_URL="https://api.mvmnet.com/api/1.0"
fi

########  Public functions #####################

dns_mvmnet_add() {
  fulldomain=$1
  txtvalue=$2

  _retrieve_and_check_variables

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain "$_domain"

  _subdomain=$(echo "$fulldomain" | sed -r "s/.$_domain//")
  _debug _subdomain "$_subdomain"

  _info "Adding TXT record to ${fulldomain}"
  postdata=$(printf '{"domain":"%s","rtype":"TXT","ldata":"%s","rdata":"%s"}' "${_domain}" "${_subdomain}" "${txtvalue}")
  _mvmnet_rest POST "dns/zone/record" "$postdata"

  if ! _contains "${response}" 'error'; then
    return 0
  fi
  _err "Could not create resource record, check logs"
  _err "${response}"
  return 1
}

dns_mvmnet_rm() {
  fulldomain=$1
  txtvalue=$2

  _check_variables

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain "$_domain"

  _subdomain=$(echo "$fulldomain" | sed -r "s/.$_domain//")
  _debug _subdomain "$_subdomain"

  if ! _get_record_id "$_subdomain" "$_domain" "$txtvalue"; then
    _warn "Record id for $_subdomain not found, please remove it manually"
    return 0
  fi

  _debug _sub_domain_record_id "$_sub_domain_record_id"

  _info "Deleting resource record $fulldomain ($_sub_domain_record_id)"
  _mvmnet_rest DELETE "dns/zone/record" "domain=${_domain}&id=${_sub_domain_record_id}"

  if ! _contains "${response}" 'error'; then
    return 0
  fi
  _err "Could not delete resource record, check logs"
  _err "${response}"
  return 1
}

####################  Private functions below ##################################

_check_variables() {
  MVMNET_ID="${MVMNET_ID:-$(_readaccountconf_mutable MVMNET_ID)}"
  MVMNET_KEY="${MVMNET_KEY:-$(_readaccountconf_mutable MVMNET_KEY)}"
  MVMNET_SEED="${MVMNET_SEED:-$(_readaccountconf_mutable MVMNET_SEED)}"
  if [ -z "$MVMNET_ID" ] || [ -z "$MVMNET_KEY" ] || [ -z "$MVMNET_SEED" ]; then
    MVMNET_ID=""
    MVMNET_KEY=""
    MVMNET_SEED=""
    _err "You don't specify application_id, application_key or application_seed."
    return 1
  fi
}

_retrieve_and_check_variables() {
  _check_variables

  _saveaccountconf_mutable MVMNET_ID "$MVMNET_ID"
  _saveaccountconf_mutable MVMNET_KEY "$MVMNET_KEY"
  _saveaccountconf_mutable MVMNET_SEED "$MVMNET_SEED"
}

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=123456789
_get_root() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      _debug "not valid $h"
      return 1
    fi

    if ! _mvmnet_rest GET "domain/info" "domain=$h"; then
      return 1
    fi

    if _contains "$response" "\"domain_idn\":\"$h\""; then
      _domain_id=$(echo "$response" | _egrep_o ".\"id\": *\"[0-9]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \" | tr -d " ")
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
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

# _acme-challenge.www
# domain.com
# value (Optional)
#returns
# _sub_domain_record_id=123456789
_get_record_id() {
  subdomain=$1
  domain=$2
  txtvalue=$3

  _debug3 subdomain "$subdomain"
  _debug3 domain "$domain"
  _debug3 txtvalue "$txtvalue"

  hosttofind="${subdomain}.${domain}"

  if ! _mvmnet_rest GET "dns/zone" "domain=$domain"; then
    return 1
  fi

  objectbody="$(echo "$response" | sed 's/}, *{/}\n{/g; s/\[/\[\n/g; s/\]/\n\]/g' | grep -E "\"host\" *: *\"$hosttofind\.\".*\"type\" *: *\"TXT\"|\"type\" *: *\"TXT\".*\"host\" *: *\"$hosttofind\.\"")"

  _debug3 objectbody "${objectbody}"

  if [ "$txtvalue" != "" ]; then
    _info "A value will be searched: $txtvalue"
    objectbody="$(echo "$objectbody" | grep "\"value\" *: *\"\\\\\"$txtvalue\\\\\"\"")"
    _debug3 objectbody "${objectbody}"
  fi

  _sub_domain_record_id="$(echo "$objectbody" | _egrep_o ".\"id\": *\"[0-9]*\"" | _head_n 1 | cut -d : -f 2 | tr -d \" | tr -d ' ')"

  if [ "${_sub_domain_record_id}x" = "x" ]; then
    _err "error retrieve sub domain record id"
    return 1
  fi
  return 0
}

#returns
# response
_mvmnet_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  MVMNET_ID="${MVMNET_ID:-$(_readaccountconf_mutable MVMNET_ID)}"       ## Case sensitive
  MVMNET_KEY="${MVMNET_KEY:-$(_readaccountconf_mutable MVMNET_KEY)}"    ## Case sensitive
  MVMNET_SEED="${MVMNET_SEED:-$(_readaccountconf_mutable MVMNET_SEED)}" ## Case sensitive

  signature="$(printf "%s" "${MVMNET_ID}+${MVMNET_KEY}+$m+${MVMNET_SEED}" | _digest "sha1" "hex")"

  export _H1="X-Mvm-Application: ${MVMNET_ID}"
  export _H2="X-Mvm-Signature: ${signature}"

  case "$m" in
  POST | PUT)
    _debug data "$data"
    response="$(_post "$data" "$MVMNET_API_URL/$ep" "" "$m" "application/json")"
    ;;
  DELETE)
    response="$(_post "" "$MVMNET_API_URL/$ep?$data" "" "$m")"
    ;;
  GET)
    response="$(_get "$MVMNET_API_URL/$ep?$data")"
    ;;
  esac

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi

  _debug response "${response}"
  return 0
}
