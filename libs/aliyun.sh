#!/usr/bin/env sh
# Some useful functions for aliyun

Ali_Key="${Ali_Key:-$(_readaccountconf_mutable Ali_Key)}"
Ali_Secret="${Ali_Secret:-$(_readaccountconf_mutable Ali_Secret)}"

if [ -z "$Ali_Key" ] || [ -z "$Ali_Secret" ]; then
  Ali_Key=""
  Ali_Secret=""
  _err "You don't specify aliyun api key and secret yet."
  return 1
fi

#save the api key and secret to the account conf file.
_saveaccountconf_mutable Ali_Key "$Ali_Key"
_saveaccountconf_mutable Ali_Secret "$Ali_Secret"

# common query for every api request
common_query="Format=json&AccessKeyId=${Ali_Key}&SignatureMethod=HMAC-SHA1&SignatureVersion=1.0"

_ali_urlencode() {
  _str="$1"
  _str_len=${#_str}
  _u_i=1
  while [ "$_u_i" -le "$_str_len" ]; do
    _str_c="$(printf "%s" "$_str" | cut -c "$_u_i")"
    case $_str_c in [a-zA-Z0-9.~_-])
      printf "%s" "$_str_c"
      ;;
    *)
      printf "%%%02X" "'$_str_c"
      ;;
    esac
    _u_i="$(_math "$_u_i" + 1)"
  done
}

_ali_nonce() {
  #_head_n 1 </dev/urandom | _digest "sha256" hex | cut -c 1-31
  #Not so good...
  date +"%s%N"
}

_ali_signature() {
  local sorted_query=$(printf "%s" "${query}" | tr '&' '\n' | sort | paste -s -d '&')
  string_to_sign=$(printf "%s" "GET&%2F&$(_ali_urlencode "${sorted_query}")")
  _debug2 ali_string_to_sign "${string_to_sign}"
  signature=$(printf "%s" "${string_to_sign}" | \
    _hmac "sha1" "$(printf "%s" "${Ali_Secret}&" | _hex_dump | tr -d ' ')" | \
    _base64)

  _debug2 ali_signature ${signature}
  _ali_urlencode "${signature}"
}

_timestamp() {
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}

# Generate aliyun sorted query string like Version=2015-01-01&region=cn-hangzhou&...
# Usage: _ali_query k1=v1 [k2=v2 [k3=v3] ...]
ali_query_builder() {
  query="${common_query}"
  query="${common_query}&SignatureNonce=$(_ali_nonce)&Timestamp=$(_timestamp)"

  for q in "$@"; do
    query="${query}&${q}"
  done

  query="${query}&Signature=$(_ali_signature ${query})"
}

ali_rest() {
  endpoint="${1}"
  url="${endpoint}?${query}"

  if ! response="$(_get "$url")"; then
    _err "Error <$2>"
    return 1
  fi

  _debug2 response "$response"
  if [ -z "$3" ]; then
    message="$(echo "$response" | _egrep_o "\"Message\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")"
    if [ "$message" ]; then
      _err "$message"
      return 1
    fi
  fi
}