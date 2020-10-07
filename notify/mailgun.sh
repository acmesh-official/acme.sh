#!/usr/bin/env sh

#Support mailgun.com api

#MAILGUN_API_KEY="xxxx"
#MAILGUN_TO="yyyy@gmail.com"

#MAILGUN_REGION="us|eu"          #optional, use "us" as default
#MAILGUN_API_DOMAIN="xxxxxx.com"  #optional, use the default sandbox domain
#MAILGUN_FROM="xxx@xxxxx.com"    #optional, use the default sandbox account

_MAILGUN_BASE_US="https://api.mailgun.net/v3"
_MAILGUN_BASE_EU="https://api.eu.mailgun.net/v3"

_MAILGUN_BASE="$_MAILGUN_BASE_US"

# subject  content statusCode
mailgun_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  MAILGUN_API_KEY="${MAILGUN_API_KEY:-$(_readaccountconf_mutable MAILGUN_API_KEY)}"
  if [ -z "$MAILGUN_API_KEY" ]; then
    MAILGUN_API_KEY=""
    _err "You didn't specify a mailgun api key MAILGUN_API_KEY yet ."
    _err "You can get yours from here https://mailgun.com"
    return 1
  fi
  _saveaccountconf_mutable MAILGUN_API_KEY "$MAILGUN_API_KEY"

  MAILGUN_REGION="${MAILGUN_REGION:-$(_readaccountconf_mutable MAILGUN_REGION)}"
  if [ -z "$MAILGUN_REGION" ]; then
    MAILGUN_REGION=""
    _debug "The MAILGUN_REGION is not set, so use the default us region."
    _MAILGUN_BASE="$_MAILGUN_BASE_US"
  else
    MAILGUN_REGION="$(echo "$MAILGUN_REGION" | _lower_case)"
    _saveaccountconf_mutable MAILGUN_REGION "$MAILGUN_REGION"
    if [ "$MAILGUN_REGION" = "us" ]; then
      _MAILGUN_BASE="$_MAILGUN_BASE_US"
    else
      _MAILGUN_BASE="$_MAILGUN_BASE_EU"
    fi
  fi
  _debug _MAILGUN_BASE "$_MAILGUN_BASE"
  MAILGUN_TO="${MAILGUN_TO:-$(_readaccountconf_mutable MAILGUN_TO)}"
  if [ -z "$MAILGUN_TO" ]; then
    MAILGUN_TO=""
    _err "You didn't specify an email to MAILGUN_TO receive messages."
    return 1
  fi
  _saveaccountconf_mutable MAILGUN_TO "$MAILGUN_TO"

  MAILGUN_API_DOMAIN="${MAILGUN_API_DOMAIN:-$(_readaccountconf_mutable MAILGUN_API_DOMAIN)}"
  if [ -z "$MAILGUN_API_DOMAIN" ]; then
    _info "The MAILGUN_API_DOMAIN is not set, try to get the default sending sandbox domain for you."
    if ! _mailgun_rest GET "/domains"; then
      _err "Can not get sandbox domain."
      return 1
    fi
    _sendboxDomain="$(echo "$response" | _egrep_o '"name": *"sandbox.*.mailgun.org"' | cut -d : -f 2 | tr -d '" ')"
    _debug _sendboxDomain "$_sendboxDomain"
    MAILGUN_API_DOMAIN="$_sendboxDomain"
    if [ -z "$MAILGUN_API_DOMAIN" ]; then
      _err "Can not get sandbox domain for MAILGUN_API_DOMAIN"
      return 1
    fi

    _info "$(__green "When using sandbox domain, you must verify your email first.")"
    #todo: add recepient
  fi
  if [ -z "$MAILGUN_API_DOMAIN" ]; then
    _err "Can not get MAILGUN_API_DOMAIN"
    return 1
  fi
  _saveaccountconf_mutable MAILGUN_API_DOMAIN "$MAILGUN_API_DOMAIN"

  MAILGUN_FROM="${MAILGUN_FROM:-$(_readaccountconf_mutable MAILGUN_FROM)}"
  if [ -z "$MAILGUN_FROM" ]; then
    MAILGUN_FROM="$PROJECT_NAME@$MAILGUN_API_DOMAIN"
    _info "The MAILGUN_FROM is not set, so use the default value: $MAILGUN_FROM"
  else
    _debug MAILGUN_FROM "$MAILGUN_FROM"
    _saveaccountconf_mutable MAILGUN_FROM "$MAILGUN_FROM"
  fi

  #send from url
  _msg="/$MAILGUN_API_DOMAIN/messages?from=$(printf "%s" "$MAILGUN_FROM" | _url_encode)&to=$(printf "%s" "$MAILGUN_TO" | _url_encode)&subject=$(printf "%s" "$_subject" | _url_encode)&text=$(printf "%s" "$_content" | _url_encode)"
  _debug "_msg" "$_msg"
  _mailgun_rest POST "$_msg"
  if _contains "$response" "Queued. Thank you."; then
    _debug "mailgun send success."
    return 0
  else
    _err "mailgun send error"
    _err "$response"
    return 1
  fi

}

# method uri  data
_mailgun_rest() {
  _method="$1"
  _mguri="$2"
  _mgdata="$3"
  _debug _mguri "$_mguri"
  _mgurl="$_MAILGUN_BASE$_mguri"
  _debug _mgurl "$_mgurl"

  _auth="$(printf "%s" "api:$MAILGUN_API_KEY" | _base64)"
  export _H1="Authorization: Basic $_auth"
  export _H2="Content-Type: application/json"

  if [ "$_method" = "GET" ]; then
    response="$(_get "$_mgurl")"
  else
    _debug _mgdata "$_mgdata"
    response="$(_post "$_mgdata" "$_mgurl" "" "$_method")"
  fi
  if [ "$?" != "0" ]; then
    _err "Error: $_mguri"
    _err "$response"
    return 1
  fi
  _debug2 response "$response"
  return 0

}
