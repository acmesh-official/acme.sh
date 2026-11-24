#!/usr/bin/env sh

# shellcheck disable=SC2034
dns_comlaude_info='comlaude.com
Site: comlaude.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_comlaude
Options:
 COMLAUDE_USERNAME User account
 COMLAUDE_PASSWORD User password
 COMLAUDE_API_KEY generated API key
 COMLAUDE_GROUP_ID Group ID in comlaude user profile
 Get it from the https://www.comlaude.com
Issues: github.com/acmesh-official/acme.sh/issues/7112
'
# ===== CONFIG =====
COMLAUDE_API="https://api.comlaude.com"

########## AUTH ##########

_comlaude_auth() {
  _debug "Checking cached ComLaude token"

  # Try to get token from account.conf
  if [ -z "$COMLAUDE_ACCESS_TOKEN" ]; then
    COMLAUDE_ACCESS_TOKEN="$(_readaccountconf_mutable COMLAUDE_ACCESS_TOKEN)"
    COMLAUDE_TOKEN_EXPIRY="$(_readaccountconf_mutable COMLAUDE_TOKEN_EXPIRY)"
  fi

  _now=$(_time)
  if [ -n "$COMLAUDE_ACCESS_TOKEN" ] && [ -n "$COMLAUDE_TOKEN_EXPIRY" ] && [ "$_now" -lt "$COMLAUDE_TOKEN_EXPIRY" ]; then
    _debug "Using cached ComLaude token (valid ${COMLAUDE_TOKEN_EXPIRY} > ${_now})"
    return 0
  fi

  _info "ComLaude auth..."
  _comlaude_body="{\"username\":\"$COMLAUDE_USERNAME\",\"password\":\"$COMLAUDE_PASSWORD\",\"api_key\":\"$COMLAUDE_API_KEY\"}"
  _comlaude_response="$(_post "$_comlaude_body" "$COMLAUDE_API/api_login" "" "POST" "application/json")"

  if ! _contains "$_comlaude_response" "access_token"; then
    _err "Auth failed: $_comlaude_response"
    return 1
  fi

  COMLAUDE_ACCESS_TOKEN=$(echo "$_comlaude_response" | _egrep_o '"access_token":"[^"]*"' | cut -d'"' -f4)
  # store expiracy from api reply l'API ("expires_in" in seconds)
  _comlaude_expires_in=$(echo "$_comlaude_response" | _egrep_o '"expires_in":[0-9]*' | cut -d: -f2)
  [ -z "$_comlaude_expires_in" ] && _comlaude_expires_in=3000 # fallback if no info

  COMLAUDE_TOKEN_EXPIRY=$(($(_time) + _comlaude_expires_in - 60)) # margin of 60s to secure renew

  _saveaccountconf_mutable COMLAUDE_ACCESS_TOKEN "$COMLAUDE_ACCESS_TOKEN"
  _saveaccountconf_mutable COMLAUDE_TOKEN_EXPIRY "$COMLAUDE_TOKEN_EXPIRY"

  return 0
}

########## DOMAIN RESOLUTION ##########

_comlaude_get_root() {
  COMLAUDE_GROUP_ID="${COMLAUDE_GROUP_ID:-$(_readaccountconf_mutable COMLAUDE_GROUP_ID)}"
  if [ -z "$COMLAUDE_GROUP_ID" ]; then
    _err "Missing COMLAUDE_GROUP_ID"
    return 1
  fi

  _comlaude_input_domain="$1"
  _comlaude_input_domain="${_comlaude_input_domain#_acme-challenge.}"
  case "$_comlaude_input_domain" in
  \*.*) _comlaude_input_domain="${_comlaude_input_domain#*.}" ;;
  esac

  _debug "Normalized domain: $_comlaude_input_domain"

  _comlaude_i=1
  while true; do
    _comlaude_d=$(printf "%s" "$_comlaude_input_domain" | cut -d . -f "$_comlaude_i-")
    [ -z "$_comlaude_d" ] && {
      _debug "No matching domain found for $_comlaude_input_domain"
      return 1
    }

    # don't test unnecessary levels
    # registered domain : TLD only (no dot after cut).
    case "$_comlaude_d" in
    *.*) : ;;
    *)
      _debug "Skipping bare TLD candidate: $_comlaude_d"
      _comlaude_i=$((_comlaude_i + 1))
      continue
      ;;
    esac

    _debug "Checking domain: $_comlaude_d"

    _comlaude_retry=0
    _comlaude_max_retry=3 # to avoid network errors
    _comlaude_DOM_ID=""
    _comlaude_Z_ID=""

    while [ "$_comlaude_retry" -lt "$_comlaude_max_retry" ]; do
      export _H1="Authorization: Bearer $COMLAUDE_ACCESS_TOKEN"
      _debug "Full URL: $COMLAUDE_API/groups/$COMLAUDE_GROUP_ID/domains?filter[name]=$_comlaude_d&fields=id,name,active_zone"
      _comlaude_response="$(_get "$COMLAUDE_API/groups/$COMLAUDE_GROUP_ID/domains?filter[name]=$_comlaude_d&fields=id,name,active_zone")"
      _H1=""

      _debug "RAW response for $_comlaude_d (try $((_comlaude_retry + 1))): $_comlaude_response"

      # If empty -> true network issue, we retry
      if [ -z "$_comlaude_response" ]; then
        _comlaude_retry=$((_comlaude_retry + 1))
        [ "$_comlaude_retry" -lt "$_comlaude_max_retry" ] && sleep 2
        continue
      fi

      # 404 -> domain not found in that level. no retry : continue
      if echo "$_comlaude_response" | grep -q '"status_code":404'; then
        _debug "404 for $_comlaude_d, moving to next level (not retrying)"
        break
      fi

      # Domain missing (200 reply, data empty) -> continue
      if echo "$_comlaude_response" | grep -q '"data":\[\]'; then
        _debug "Empty data for $_comlaude_d, moving to next level"
        break
      fi

      # Extraction via _egrep_o
      _comlaude_DOM_ID="$(echo "$_comlaude_response" | _egrep_o '"id":"[^"]*"' | head -n1 | cut -d':' -f2 | tr -d '"')"
      _comlaude_Z_ID="$(echo "$_comlaude_response" | _egrep_o '"active_zone":\{"id":"[^"]*"' | _egrep_o '"id":"[^"]*"$' | cut -d':' -f2 | tr -d '"')"

      if [ -n "$_comlaude_DOM_ID" ] && [ -n "$_comlaude_Z_ID" ]; then
        break
      fi

      # 200 reply but malformed data /  noid -> retry transport
      _comlaude_retry=$((_comlaude_retry + 1))
      [ "$_comlaude_retry" -lt "$_comlaude_max_retry" ] && sleep 2
    done

    _debug "_comlaude_DOM_ID=$_comlaude_DOM_ID"
    _debug "_comlaude_Z_ID=$_comlaude_Z_ID"

    if [ -n "$_comlaude_DOM_ID" ] && [ -n "$_comlaude_Z_ID" ]; then
      _comlaude_domain="$_comlaude_d"
      _comlaude_domain_id="$_comlaude_DOM_ID"
      _comlaude_zone_id="$_comlaude_Z_ID"
      return 0
    fi

    _comlaude_i=$((_comlaude_i + 1))
  done
}
########## ADD TXT ##########

dns_comlaude_add() {
  fulldomain="$1"
  txtvalue="$2"

  COMLAUDE_USERNAME="${COMLAUDE_USERNAME:-$(_readaccountconf_mutable COMLAUDE_USERNAME)}"
  COMLAUDE_PASSWORD="${COMLAUDE_PASSWORD:-$(_readaccountconf_mutable COMLAUDE_PASSWORD)}"
  COMLAUDE_API_KEY="${COMLAUDE_API_KEY:-$(_readaccountconf_mutable COMLAUDE_API_KEY)}"
  COMLAUDE_GROUP_ID="${COMLAUDE_GROUP_ID:-$(_readaccountconf_mutable COMLAUDE_GROUP_ID)}"

  if [ -z "$COMLAUDE_USERNAME" ] || [ -z "$COMLAUDE_PASSWORD" ] || [ -z "$COMLAUDE_API_KEY" ]; then
    _err "You didn't specify ComLaude credentials (COMLAUDE_USERNAME, COMLAUDE_PASSWORD, COMLAUDE_API_KEY)."
    return 1
  fi

  # Backup variable after validation
  _saveaccountconf_mutable COMLAUDE_USERNAME "$COMLAUDE_USERNAME"
  _saveaccountconf_mutable COMLAUDE_PASSWORD "$COMLAUDE_PASSWORD"
  _saveaccountconf_mutable COMLAUDE_API_KEY "$COMLAUDE_API_KEY"
  _saveaccountconf_mutable COMLAUDE_GROUP_ID "$COMLAUDE_GROUP_ID"

  _info "Adding TXT: $fulldomain"
  _comlaude_auth || return 1
  _comlaude_get_root "$fulldomain" || return 1

  _debug "Root: $_comlaude_domain"

  _comlaude_data="{\"type\":\"TXT\",\"name\":\"$fulldomain\",\"value\":\"$txtvalue\",\"ttl\":60}"

  export _H1="Authorization: Bearer $COMLAUDE_ACCESS_TOKEN"
  export _H2="Content-Type: application/json"

  _comlaude_response="$(_post "$_comlaude_data" "$COMLAUDE_API/groups/$COMLAUDE_GROUP_ID/zones/$_comlaude_zone_id/records")"

  _H1=""
  _H2=""
  if ! echo "$_comlaude_response" | grep -q '"id"'; then
    _err "Failed to create TXT"
    _debug "$_comlaude_response"
    return 1
  fi

  return 0
}

########## REMOVE TXT ##########

dns_comlaude_rm() {
  fulldomain="$1"
  txtvalue="$2"

  COMLAUDE_USERNAME="${COMLAUDE_USERNAME:-$(_readaccountconf_mutable COMLAUDE_USERNAME)}"
  COMLAUDE_PASSWORD="${COMLAUDE_PASSWORD:-$(_readaccountconf_mutable COMLAUDE_PASSWORD)}"
  COMLAUDE_API_KEY="${COMLAUDE_API_KEY:-$(_readaccountconf_mutable COMLAUDE_API_KEY)}"
  COMLAUDE_GROUP_ID="${COMLAUDE_GROUP_ID:-$(_readaccountconf_mutable COMLAUDE_GROUP_ID)}"

  _info "Removing TXT: $fulldomain"

  _comlaude_auth || return 1
  _comlaude_get_root "$fulldomain" || return 1

  export _H1="Authorization: Bearer $COMLAUDE_ACCESS_TOKEN"
  _comlaude_encoded_name="$(printf '%s' "$fulldomain" | _url_encode)"
  _comlaude_encoded_value="$(printf '%s' "$txtvalue" | _url_encode)"
  _comlaude_url="$COMLAUDE_API/groups/$COMLAUDE_GROUP_ID/zones/$_comlaude_zone_id/records?filter[type]=TXT&filter[name]=$_comlaude_encoded_name&filter[value]=$_comlaude_encoded_value"
  _comlaude_response="$(_get "$_comlaude_url")"
  _H1=""

  _debug "Filtered records response: $_comlaude_response"

  # first "id" top-level of reply (record itself,
  # always on first position of each data[] object)
  _comlaude_record_id="$(echo "$_comlaude_response" | _egrep_o '"data":\[\{"id":"[^"]*"' | _egrep_o '"[^"]*"$' | tr -d '"')"

  if [ -z "$_comlaude_record_id" ]; then
    _info "No matching TXT record found to delete for $fulldomain / $txtvalue"
    return 0
  fi

  _debug "Deleting record $_comlaude_record_id"

  export _H1="Authorization: Bearer $COMLAUDE_ACCESS_TOKEN"
  _comlaude_del_url="$COMLAUDE_API/groups/$COMLAUDE_GROUP_ID/zones/$_comlaude_zone_id/records/$_comlaude_record_id"
  _comlaude_del_resp="$(_post "" "$_comlaude_del_url" "" "DELETE")"
  _H1=""

  if echo "$_comlaude_del_resp" | grep -q '"error"'; then
    _err "Delete failed for $_comlaude_record_id"
    _debug "$_comlaude_del_resp"
    return 1
  fi

  _info "Deleted record $_comlaude_record_id"
  return 0
}
