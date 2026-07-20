#!/usr/bin/env sh

#Support OpsGenie API integration

#OPSGENIE_API_KEY="" Required, opsgenie api key
#OPSGENIE_REGION="" Optional, opsgenie region, can be EU or US (default: US)
#OPSGENIE_PRIORITY_SUCCESS="" Optional, opsgenie priority for success (default: P5)
#OPSGENIE_PRIORITY_ERROR="" Optional, opsgenie priority for error (default: P2)
#OPSGENIE_PRIORITY_SKIP="" Optional, opsgenie priority for renew skipped (default: P5)

_OPSGENIE_AVAIL_REGION="US,EU"
_OPSGENIE_AVAIL_PRIORITIES="P1,P2,P3,P4,P5"

opsgenie_send() {
  _subject="$1"
  _content="$2"
  _status_code="$3" #0: success, 1: error, 2($RENEW_SKIP): skipped

  OPSGENIE_API_KEY="${OPSGENIE_API_KEY:-$(_readaccountconf_mutable OPSGENIE_API_KEY)}"
  if [ -z "$OPSGENIE_API_KEY" ]; then
    OPSGENIE_API_KEY=""
    _err "You didn't specify an OpsGenie API key OPSGENIE_API_KEY yet."
    return 1
  fi
  _saveaccountconf_mutable OPSGENIE_API_KEY "$OPSGENIE_API_KEY"
  export _H1="Authorization: GenieKey $OPSGENIE_API_KEY"

  OPSGENIE_REGION="${OPSGENIE_REGION:-$(_readaccountconf_mutable OPSGENIE_REGION)}"
  if [ -z "$OPSGENIE_REGION" ]; then
    OPSGENIE_REGION="US"
    _info "The OPSGENIE_REGION is not set, so use the default US as regeion."
  elif ! _hasfield "$_OPSGENIE_AVAIL_REGION" "$OPSGENIE_REGION"; then
    _err "The OPSGENIE_REGION \"$OPSGENIE_REGION\" is not available, should be one of $_OPSGENIE_AVAIL_REGION"
    OPSGENIE_REGION=""
    return 1
  else
    _saveaccountconf_mutable OPSGENIE_REGION "$OPSGENIE_REGION"
  fi

  OPSGENIE_PRIORITY_SUCCESS="${OPSGENIE_PRIORITY_SUCCESS:-$(_readaccountconf_mutable OPSGENIE_PRIORITY_SUCCESS)}"
  if [ -z "$OPSGENIE_PRIORITY_SUCCESS" ]; then
    OPSGENIE_PRIORITY_SUCCESS="P5"
    _info "The OPSGENIE_PRIORITY_SUCCESS is not set, so use the default P5 as priority."
  elif ! _hasfield "$_OPSGENIE_AVAIL_PRIORITIES" "$OPSGENIE_PRIORITY_SUCCESS"; then
    _err "The OPSGENIE_PRIORITY_SUCCESS \"$OPSGENIE_PRIORITY_SUCCESS\" is not available, should be one of $_OPSGENIE_AVAIL_PRIORITIES"
    OPSGENIE_PRIORITY_SUCCESS=""
    return 1
  else
    _saveaccountconf_mutable OPSGENIE_PRIORITY_SUCCESS "$OPSGENIE_PRIORITY_SUCCESS"
  fi

  OPSGENIE_PRIORITY_ERROR="${OPSGENIE_PRIORITY_ERROR:-$(_readaccountconf_mutable OPSGENIE_PRIORITY_ERROR)}"
  if [ -z "$OPSGENIE_PRIORITY_ERROR" ]; then
    OPSGENIE_PRIORITY_ERROR="P2"
    _info "The OPSGENIE_PRIORITY_ERROR is not set, so use the default P2 as priority."
  elif ! _hasfield "$_OPSGENIE_AVAIL_PRIORITIES" "$OPSGENIE_PRIORITY_ERROR"; then
    _err "The OPSGENIE_PRIORITY_ERROR \"$OPSGENIE_PRIORITY_ERROR\" is not available, should be one of $_OPSGENIE_AVAIL_PRIORITIES"
    OPSGENIE_PRIORITY_ERROR=""
    return 1
  else
    _saveaccountconf_mutable OPSGENIE_PRIORITY_ERROR "$OPSGENIE_PRIORITY_ERROR"
  fi

  OPSGENIE_PRIORITY_SKIP="${OPSGENIE_PRIORITY_SKIP:-$(_readaccountconf_mutable OPSGENIE_PRIORITY_SKIP)}"
  if [ -z "$OPSGENIE_PRIORITY_SKIP" ]; then
    OPSGENIE_PRIORITY_SKIP="P5"
    _info "The OPSGENIE_PRIORITY_SKIP is not set, so use the default P5 as priority."
  elif ! _hasfield "$_OPSGENIE_AVAIL_PRIORITIES" "$OPSGENIE_PRIORITY_SKIP"; then
    _err "The OPSGENIE_PRIORITY_SKIP \"$OPSGENIE_PRIORITY_SKIP\" is not available, should be one of $_OPSGENIE_AVAIL_PRIORITIES"
    OPSGENIE_PRIORITY_SKIP=""
    return 1
  else
    _saveaccountconf_mutable OPSGENIE_PRIORITY_SKIP "$OPSGENIE_PRIORITY_SKIP"
  fi

  case "$OPSGENIE_REGION" in
  "US")
    _opsgenie_url="https://api.opsgenie.com/v2/alerts"
    ;;
  "EU")
    _opsgenie_url="https://api.eu.opsgenie.com/v2/alerts"
    ;;
  *)
    _err "opsgenie region error."
    return 1
    ;;
  esac

  case $_status_code in
  0)
    _priority=$OPSGENIE_PRIORITY_SUCCESS
    ;;
  1)
    _priority=$OPSGENIE_PRIORITY_ERROR
    ;;
  2)
    _priority=$OPSGENIE_PRIORITY_SKIP
    ;;
  *)
    _priority=$OPSGENIE_PRIORITY_ERROR
    ;;
  esac

  _subject_json=$(echo "$_subject" | _json_encode)
  _content_json=$(echo "$_content" | _json_encode)
  _subject_underscore=$(echo "$_subject" | sed 's/ /_/g')
  _alias_json=$(echo "acme.sh-$(hostname)-$_subject_underscore-$(date +%Y%m%d)" | base64 --wrap=0 | _json_encode)

  _data="{
    \"message\": \"$_subject_json\",
    \"alias\": \"$_alias_json\",
    \"description\": \"$_content_json\",
    \"tags\": [
        \"acme.sh\",
        \"host:$(hostname)\"
    ],
    \"entity\": \"$(hostname -f)\",
    \"priority\": \"$_priority\"
}"

  if response=$(_post "$_data" "$_opsgenie_url" "" "" "application/json"); then
    if ! _contains "$response" error; then
      _info "opsgenie send success."
      return 0
    fi
  fi
  _err "opsgenie send error."
  _err "$response"
  return 1
}
