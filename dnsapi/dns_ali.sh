#!/usr/bin/env sh
# shellcheck disable=SC2034,SC2086
dns_ali_info='AlibabaCloud.com
Domains: Aliyun.com
Site: AlibabaCloud.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_ali
Options:
 Ali_Key API Key
 Ali_Secret API Secret
 Ali_Token Optional STS SecurityToken
'

# NOTICE:
# This file is referenced by Alibaba Cloud Services deploy hooks
# https://github.com/acmesh-official/acme.sh/pull/5205#issuecomment-2357867276
# Be careful when modifying this file, especially when making breaking changes for common functions

Ali_DNS_API="https://alidns.aliyuncs.com/"
Ali_DNS_HOST="alidns.aliyuncs.com"
Ali_DNS_VERSION="2015-01-09"
Ali_SIGN_ALGORITHM="ACS3-HMAC-SHA256"

#Usage: dns_ali_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_ali_add() {
  fulldomain=$1
  txtvalue=$2

  _prepare_ali_credentials || return 1

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    return 1
  fi

  _debug "Add record"
  _add_record_query "$_domain" "$_sub_domain" "$txtvalue" && _ali_rest "Add record"
}

dns_ali_rm() {
  fulldomain=$1
  txtvalue=$2
  Ali_Key="${Ali_Key:-$(_readaccountconf_mutable Ali_Key)}"
  Ali_Secret="${Ali_Secret:-$(_readaccountconf_mutable Ali_Secret)}"
  Ali_Token="${Ali_Token:-$(_readaccountconf_mutable Ali_Token)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    return 1
  fi

  _clean
}

####################  Alibaba Cloud common functions below  ####################

_prepare_ali_credentials() {
  Ali_Key="${Ali_Key:-$(_readaccountconf_mutable Ali_Key)}"
  Ali_Secret="${Ali_Secret:-$(_readaccountconf_mutable Ali_Secret)}"
  Ali_Token="${Ali_Token:-$(_readaccountconf_mutable Ali_Token)}"
  if [ -z "$Ali_Key" ] || [ -z "$Ali_Secret" ]; then
    Ali_Key=""
    Ali_Secret=""
    _err "You don't specify aliyun api key and secret yet."
    return 1
  fi

  #save the api key and secret to the account conf file.
  _saveaccountconf_mutable Ali_Key "$Ali_Key"
  _saveaccountconf_mutable Ali_Secret "$Ali_Secret"
  if [ "$Ali_Token" ]; then
    _saveaccountconf_mutable Ali_Token "$Ali_Token"
  fi
}

_ali_query_pair() {
  printf "%s=%s" "$(printf "%s" "$1" | _url_encode upper-hex)" "$(printf "%s" "$2" | _url_encode upper-hex)"
}

_ali_sha256_hex() {
  printf "%s" "${1:-}" | _digest sha256 hex
}

_ali_hmac_sha256() {
  printf "%s" "$2" | _hmac sha256 "$(printf "%s" "$1" | _hex_dump | tr -d " ")" hex
}

_ali_http() {
  mtd="$1"
  url="$2"

  _inithttp

  if [ "$_ACME_CURL" ] && [ "${ACME_USE_WGET:-0}" = "0" ]; then
    _curl="$_ACME_CURL"
    if [ "$HTTPS_INSECURE" ]; then
      _curl="$_curl --insecure"
    fi
    if [ "$Ali_Token" ] && [ "$mtd" = "POST" ]; then
      $_curl --user-agent "$USER_AGENT" -X "$mtd" \
        -H "Authorization:${_ali_authorization}" \
        -H "host:${Ali_DNS_HOST}" \
        -H "x-acs-action:${_ali_action}" \
        -H "x-acs-content-sha256:${_ali_payload_hash}" \
        -H "x-acs-date:${_ali_date}" \
        -H "x-acs-security-token:${Ali_Token}" \
        -H "x-acs-signature-nonce:${_ali_nonce}" \
        -H "x-acs-version:${Ali_DNS_VERSION}" \
        --data "$_ali_body" \
        "$url"
    elif [ "$Ali_Token" ]; then
      $_curl --user-agent "$USER_AGENT" -X "$mtd" \
        -H "Authorization:${_ali_authorization}" \
        -H "host:${Ali_DNS_HOST}" \
        -H "x-acs-action:${_ali_action}" \
        -H "x-acs-content-sha256:${_ali_payload_hash}" \
        -H "x-acs-date:${_ali_date}" \
        -H "x-acs-security-token:${Ali_Token}" \
        -H "x-acs-signature-nonce:${_ali_nonce}" \
        -H "x-acs-version:${Ali_DNS_VERSION}" \
        "$url"
    elif [ "$mtd" = "POST" ]; then
      $_curl --user-agent "$USER_AGENT" -X "$mtd" \
        -H "Authorization:${_ali_authorization}" \
        -H "host:${Ali_DNS_HOST}" \
        -H "x-acs-action:${_ali_action}" \
        -H "x-acs-content-sha256:${_ali_payload_hash}" \
        -H "x-acs-date:${_ali_date}" \
        -H "x-acs-signature-nonce:${_ali_nonce}" \
        -H "x-acs-version:${Ali_DNS_VERSION}" \
        --data "$_ali_body" \
        "$url"
    else
      $_curl --user-agent "$USER_AGENT" -X "$mtd" \
        -H "Authorization:${_ali_authorization}" \
        -H "host:${Ali_DNS_HOST}" \
        -H "x-acs-action:${_ali_action}" \
        -H "x-acs-content-sha256:${_ali_payload_hash}" \
        -H "x-acs-date:${_ali_date}" \
        -H "x-acs-signature-nonce:${_ali_nonce}" \
        -H "x-acs-version:${Ali_DNS_VERSION}" \
        "$url"
    fi
  elif [ "$_ACME_WGET" ]; then
    _wget="$_ACME_WGET"
    if [ "$HTTPS_INSECURE" ]; then
      _wget="$_wget --no-check-certificate"
    fi
    if [ "$Ali_Token" ] && [ "$mtd" = "POST" ]; then
      $_wget -S -O - --user-agent="$USER_AGENT" \
        --header "Authorization:${_ali_authorization}" \
        --header "host:${Ali_DNS_HOST}" \
        --header "x-acs-action:${_ali_action}" \
        --header "x-acs-content-sha256:${_ali_payload_hash}" \
        --header "x-acs-date:${_ali_date}" \
        --header "x-acs-security-token:${Ali_Token}" \
        --header "x-acs-signature-nonce:${_ali_nonce}" \
        --header "x-acs-version:${Ali_DNS_VERSION}" \
        --post-data="$_ali_body" \
        "$url"
    elif [ "$Ali_Token" ]; then
      $_wget -S -O - --user-agent="$USER_AGENT" \
        --header "Authorization:${_ali_authorization}" \
        --header "host:${Ali_DNS_HOST}" \
        --header "x-acs-action:${_ali_action}" \
        --header "x-acs-content-sha256:${_ali_payload_hash}" \
        --header "x-acs-date:${_ali_date}" \
        --header "x-acs-security-token:${Ali_Token}" \
        --header "x-acs-signature-nonce:${_ali_nonce}" \
        --header "x-acs-version:${Ali_DNS_VERSION}" \
        --method "$mtd" --body-data="$_ali_body" \
        "$url"
    elif [ "$mtd" = "POST" ]; then
      $_wget -S -O - --user-agent="$USER_AGENT" \
        --header "Authorization:${_ali_authorization}" \
        --header "host:${Ali_DNS_HOST}" \
        --header "x-acs-action:${_ali_action}" \
        --header "x-acs-content-sha256:${_ali_payload_hash}" \
        --header "x-acs-date:${_ali_date}" \
        --header "x-acs-signature-nonce:${_ali_nonce}" \
        --header "x-acs-version:${Ali_DNS_VERSION}" \
        --post-data="$_ali_body" \
        "$url"
    else
      $_wget -S -O - --user-agent="$USER_AGENT" \
        --header "Authorization:${_ali_authorization}" \
        --header "host:${Ali_DNS_HOST}" \
        --header "x-acs-action:${_ali_action}" \
        --header "x-acs-content-sha256:${_ali_payload_hash}" \
        --header "x-acs-date:${_ali_date}" \
        --header "x-acs-signature-nonce:${_ali_nonce}" \
        --header "x-acs-version:${Ali_DNS_VERSION}" \
        --method "$mtd" --body-data="$_ali_body" \
        "$url"
    fi
  else
    _err "Neither curl nor wget have been found, cannot make $mtd request."
    return 1
  fi
}

# act ign mtd
_ali_rest() {
  act="$1"
  ign="$2"
  mtd="${3:-POST}"

  _ali_date="$(_ali_timestamp)"
  _ali_nonce="$(_ali_nonce)"
  _ali_body=""
  _ali_payload_hash="$(_ali_sha256_hex "$_ali_body")"

  if [ "$Ali_Token" ]; then
    _ali_canonical_headers="host:${Ali_DNS_HOST}
x-acs-action:${_ali_action}
x-acs-content-sha256:${_ali_payload_hash}
x-acs-date:${_ali_date}
x-acs-security-token:${Ali_Token}
x-acs-signature-nonce:${_ali_nonce}
x-acs-version:${Ali_DNS_VERSION}"
    _ali_signed_headers="host;x-acs-action;x-acs-content-sha256;x-acs-date;x-acs-security-token;x-acs-signature-nonce;x-acs-version"
  else
    _ali_canonical_headers="host:${Ali_DNS_HOST}
x-acs-action:${_ali_action}
x-acs-content-sha256:${_ali_payload_hash}
x-acs-date:${_ali_date}
x-acs-signature-nonce:${_ali_nonce}
x-acs-version:${Ali_DNS_VERSION}"
    _ali_signed_headers="host;x-acs-action;x-acs-content-sha256;x-acs-date;x-acs-signature-nonce;x-acs-version"
  fi

  _ali_canonical_request="$(printf "%s\n/\n%s\n%s\n\n%s\n%s" \
    "$mtd" \
    "$_ali_canonical_query" \
    "$_ali_canonical_headers" \
    "$_ali_signed_headers" \
    "$_ali_payload_hash")"
  _debug2 canonical_request "$_ali_canonical_request"

  _ali_hashed_canonical="$(_ali_sha256_hex "$_ali_canonical_request")"
  _ali_string_to_sign="$(printf "%s\n%s" "$Ali_SIGN_ALGORITHM" "$_ali_hashed_canonical")"
  _debug2 string_to_sign "$_ali_string_to_sign"

  _ali_signature="$(_ali_hmac_sha256 "$Ali_Secret" "$_ali_string_to_sign")"
  _ali_authorization="${Ali_SIGN_ALGORITHM} Credential=${Ali_Key},SignedHeaders=${_ali_signed_headers},Signature=${_ali_signature}"

  url="$Ali_DNS_API"
  if [ "$_ali_canonical_query" ]; then
    url="$url?$_ali_canonical_query"
  fi

  response="$(_ali_http "$mtd" "$url")"

  _ret="$?"
  _debug2 response "$response"
  if [ "$_ret" != "0" ]; then
    _err "Error <$act>"
    return 1
  fi

  if [ -z "$ign" ]; then
    message="$(echo "$response" | _egrep_o "\"Message\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")"
    if [ "$message" ]; then
      _err "$message"
      return 1
    fi
  fi
}

_ali_nonce() {
  if [ "$ACME_OPENSSL_BIN" ]; then
    "$ACME_OPENSSL_BIN" rand -hex 16 2>/dev/null && return 0
  fi
  printf "%s" "$(date +%s)$$$(date +%N)" | _digest sha256 hex | cut -c 1-32
}

_ali_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

####################  Private functions below  ####################

_get_root() {
  domain=$1
  i=1
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _describe_records_query "$h"
    if ! _ali_rest "Get root" "ignore"; then
      return 1
    fi

    if _contains "$response" "PageNumber"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _debug _sub_domain "$_sub_domain"
      _domain="$h"
      _debug _domain "$_domain"
      return 0
    fi
    p="$i"
    i=$(_math "$i" + 1)
  done
  return 1
}

_check_exist_query() {
  _qdomain="$1"
  _qsubdomain="$2"
  _ali_action="DescribeDomainRecords"
  _ali_canonical_query="$(_ali_query_pair DomainName "$_qdomain")&$(_ali_query_pair Format json)&$(_ali_query_pair RRKeyWord "$_qsubdomain")&$(_ali_query_pair TypeKeyWord TXT)"
}

_add_record_query() {
  _ali_action="AddDomainRecord"
  _ali_canonical_query="$(_ali_query_pair DomainName "$1")&$(_ali_query_pair Format json)&$(_ali_query_pair RR "$2")&$(_ali_query_pair Type TXT)&$(_ali_query_pair Value "$3")"
}

_delete_record_query() {
  _ali_action="DeleteDomainRecord"
  _ali_canonical_query="$(_ali_query_pair Format json)&$(_ali_query_pair RecordId "$1")"
}

_describe_records_query() {
  _ali_action="DescribeDomainRecords"
  _ali_canonical_query="$(_ali_query_pair DomainName "$1")&$(_ali_query_pair Format json)"
}

_clean() {
  _check_exist_query "$_domain" "$_sub_domain"
  # do not correct grammar here
  if ! _ali_rest "Check exist records" "ignore"; then
    return 1
  fi

  record_id="$(echo "$response" | tr '{' "\n" | grep "$_sub_domain" | grep -- "$txtvalue" | tr "," "\n" | grep RecordId | cut -d '"' -f 4)"
  _debug2 record_id "$record_id"

  if [ -z "$record_id" ]; then
    _debug "record not found, skip"
  else
    _delete_record_query "$record_id"
    _ali_rest "Delete record $record_id" "ignore"
  fi

}
