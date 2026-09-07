#!/usr/bin/env sh
# shellcheck disable=SC2034

# Global variables for returning results (avoid stdout pollution from logging)
_BAIDU_FIND_RESULT=""
_BAIDU_BCE_AUTH_RESULT=""

: "${BAIDU_LOG_LEVEL:=2}"

_baidu_log_ts() {
  date
}

_baidu_log_ge() {
  _want="$1"
  [ "${BAIDU_LOG_LEVEL:-0}" -ge "$_want" ]
}

_baidu_log() {
  _lvl="$1"
  _tag="$2"
  _msg="$3"
  if [ "$_lvl" = "0" ] || _baidu_log_ge "$_lvl"; then
    printf -- "[%s] %s %s\n" "$(_baidu_log_ts)" "$_tag" "$_msg"
  fi
}

_baidu_err() {
  _baidu_log 0 "baidu_bcd.err" "$1"
  return 1
}

_baidu_info() {
  _baidu_log 1 "baidu_bcd.info" "$1"
  return 0
}

_baidu_debug() {
  _baidu_log 2 "$1" "$2"
  return 0
}

dns_baidu_info='Baidu Cloud BCD DNS
Site: cloud.baidu.com
Docs: https://cloud.baidu.com/doc/BCD/
Signature: https://cloud.baidu.com/doc/Reference/s/njwvz1yfu
Options:
 Baidu_AK AccessKeyId
 Baidu_SK SecretAccessKey
OptionsAlt:
 Baidu_BCD_Host API host, default: bcd.baidubce.com
 Baidu_DNS_Host New DNS API host, default: dns.baidubce.com
 Baidu_API_Preference Engine preference, default: auto
 Baidu_BCD_Version API version number, default: 1
 Baidu_BCD_Expire Signature expiration seconds, default: 3600
 Baidu_View Resolve view, default: DEFAULT
 Baidu_Line New DNS line, default: default
 Baidu_TTL Resolve ttl seconds, default: 300
 Baidu_RM_Max Max records to delete in one run, default: 20
'

BAIDU_BCD_DEFAULT_HOST="bcd.baidubce.com"
BAIDU_DNS_DEFAULT_HOST="dns.baidubce.com"

# --- Public API ---
dns_baidu_add() {
  fulldomain=$(_idn "$1")
  txtvalue=$2

  if ! _baidu_run_with_fallback "add" "$fulldomain" "$txtvalue"; then
    _baidu_err "all baidu api engines failed for add: $fulldomain"
    return 1
  fi

  return 0
}

dns_baidu_rm() {
  fulldomain=$(_idn "$1")
  txtvalue=$2

  if ! _baidu_run_with_fallback "rm" "$fulldomain" "$txtvalue"; then
    _baidu_err "all baidu api engines failed for delete: $fulldomain"
    return 1
  fi

  return 0
}

_baidu_run_with_fallback() {
  _action="$1"
  _fulldomain="$2"
  _txtvalue="$3"

  if ! _baidu_load_credentials; then
    _baidu_err "baidu_load_credentials failed"
    return 1
  fi

  for _baidu_api_engine in $(_baidu_engine_order); do
    if ! _baidu_prepare_record "$_fulldomain"; then
      _baidu_info "prepare failed for engine: $_baidu_api_engine"
      continue
    fi

    if [ "$_action" = "add" ]; then
      if _baidu_add_record "$_txtvalue"; then
        return 0
      fi
    else
      if _baidu_rm_record "$_txtvalue"; then
        return 0
      fi
    fi

    _baidu_info "engine failed, try next if available: $_baidu_api_engine"
  done

  return 1
}

_baidu_engine_order() {
  _pref="$(_lower_case "$(_baidu_trim_ws "${Baidu_API_Preference:-auto}")")"
  case "$_pref" in
  legacy)
    printf "%s" "legacy new"
    ;;
  new)
    printf "%s" "new legacy"
    ;;
  *)
    printf "%s" "new legacy"
    ;;
  esac
}

_baidu_add_record() {
  _txtvalue="$1"

  if ! _baidu_find_record_ids_current "$_zone_name" "$_record_domain" "TXT" "$_txtvalue"; then
    _baidu_err "baidu_find_record_ids failed for add: $_record_domain.$_zone_name"
    return 1
  fi
  _existing_ids="$_BAIDU_FIND_RESULT"
  if [ "$_existing_ids" ]; then
    _baidu_info "txt exists, skip add: $_record_domain.$_zone_name"
    return 0
  fi

  _ttl="${Baidu_TTL:-300}"
  _ttl="$(_baidu_trim_ws "$_ttl")"
  case "$_ttl" in
  "" | *[!0-9]*)
    _ttl="300"
    ;;
  esac

  txtvalue="$(_baidu_trim_ws "$_txtvalue")"
  _record_domain="$(_baidu_trim_ws "$_record_domain")"
  _zone_name="$(_baidu_trim_ws "$_zone_name")"

  if [ "$_baidu_api_engine" = "new" ]; then
    _line="$(_baidu_trim_ws "${Baidu_Line:-default}")"
    if [ -z "$_line" ]; then
      _line="default"
    fi
    _body="$(_baidu_payload_add_txt_dns "$_record_domain" "$txtvalue" "$_ttl" "$_line")"
    if ! _baidu_dns_call "POST" "/v1/dns/zone/${_zone_name}/record" "$_body"; then
      _baidu_err "baidu_dns_call failed: add record"
      return 1
    fi
  else
    _view="$(_baidu_trim_ws "${Baidu_View:-DEFAULT}")"
    _body="$(_baidu_payload_add_txt "$_zone_name" "$_record_domain" "$txtvalue" "$_ttl" "$_view")"
    if ! _baidu_bcd_post "/domain/resolve/add" "$_body"; then
      _baidu_err "baidu_bcd_post failed: add record"
      return 1
    fi
  fi

  if _baidu_is_api_error "$response"; then
    _baidu_err "$response"
    return 1
  fi

  return 0
}

_baidu_rm_record() {
  _txtvalue="$1"

  if ! _baidu_find_record_ids_current "$_zone_name" "$_record_domain" "TXT" "$_txtvalue"; then
    _baidu_err "baidu_find_record_ids failed for delete: $_record_domain.$_zone_name"
    return 1
  fi
  _ids="$_BAIDU_FIND_RESULT"
  if [ -z "$_ids" ]; then
    _baidu_info "no matching txt to delete: $_record_domain.$_zone_name"
    return 0
  fi

  _rm_max="${Baidu_RM_Max:-20}"
  _rm_max="$(_baidu_trim_ws "$_rm_max")"
  case "$_rm_max" in
  "" | *[!0-9]*)
    _rm_max="20"
    ;;
  esac
  _rm_cnt="$(printf "%s\n" "$_ids" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [ "$_rm_cnt" ] && [ "$_rm_cnt" -gt "$_rm_max" ]; then
    _baidu_err "Refusing to delete $_rm_cnt records (limit: $_rm_max)"
    return 1
  fi

  for _rid in $_ids; do
    if [ "$_baidu_api_engine" = "new" ]; then
      if ! _baidu_dns_call "DELETE" "/v1/dns/zone/${_zone_name}/record/${_rid}" ""; then
        _baidu_err "baidu_dns_call failed: delete recordId=$_rid"
        return 1
      fi
    else
      _body="$(_baidu_payload_delete "$_zone_name" "$_rid")"
      if ! _baidu_bcd_post "/domain/resolve/delete" "$_body"; then
        _baidu_err "baidu_bcd_post failed: delete recordId=$_rid"
        return 1
      fi
      if _baidu_is_api_error "$response"; then
        _baidu_err "$response"
        return 1
      fi
    fi
  done

  if [ "$_baidu_api_engine" = "legacy" ]; then
    if ! _baidu_find_record_ids "$_zone_name" "$_record_domain" "TXT" "$_txtvalue"; then
      _baidu_err "baidu_find_record_ids failed for delete verify: $_record_domain.$_zone_name"
      return 1
    fi
    _left_ids="$_BAIDU_FIND_RESULT"
    if [ -z "$_left_ids" ]; then
      return 0
    fi
    if [ -n "$_left_ids" ]; then
      _baidu_err "delete verification failed: $_record_domain.$_zone_name still has TXT records"
      return 1
    fi
  fi

  return 0
}

# --- Config / Record Context ---
_baidu_load_credentials() {
  Baidu_AK="${Baidu_AK:-$(_readaccountconf_mutable Baidu_AK)}"
  Baidu_SK="${Baidu_SK:-$(_readaccountconf_mutable Baidu_SK)}"

  Baidu_AK="$(_baidu_trim_ws "$Baidu_AK")"
  Baidu_SK="$(_baidu_trim_ws "$Baidu_SK")"

  if [ -z "$Baidu_AK" ] || [ -z "$Baidu_SK" ]; then
    _baidu_err "Baidu_AK and Baidu_SK are required"
    return 1
  fi

  _saveaccountconf_mutable Baidu_AK "$Baidu_AK"
  _saveaccountconf_mutable Baidu_SK "$Baidu_SK"

  BAIDU_BCD_HOST="${Baidu_BCD_Host:-$BAIDU_BCD_DEFAULT_HOST}"
  BAIDU_DNS_HOST="${Baidu_DNS_Host:-$BAIDU_DNS_DEFAULT_HOST}"
  BAIDU_BCD_VERSION="${Baidu_BCD_Version:-1}"

  return 0
}

_baidu_prepare_record() {
  _fulldomain="$1"
  if [ "$_baidu_api_engine" = "new" ]; then
    if ! _baidu_get_root_dns "$_fulldomain"; then
      _baidu_err "Could not find zone by new dns api for $_fulldomain"
      return 1
    fi
  else
    if ! _baidu_get_root "$_fulldomain"; then
      _baidu_err "Could not find zone by legacy bcd api for $_fulldomain"
      return 1
    fi
  fi
  _record_domain="$_sub_domain"
  _zone_name="$_domain"
  return 0
}

# --- Zone / Records ---
_baidu_get_root() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      _baidu_err "invalid domain: $domain"
      return 1
    fi

    if ! _baidu_bcd_post "/domain/resolve/list" "$(_baidu_payload_list "$h" 1 1)"; then
      _baidu_err "baidu_bcd_post failed: list zones"
      return 1
    fi
    if ! _baidu_is_api_error "$response" && (_contains "$response" "\"totalCount\"" || _contains "$response" "\"result\""); then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain=$h
      if [ "$_sub_domain" = "$_domain" ]; then
        _sub_domain="@"
      fi
      _baidu_info "zone matched: $_domain (host: $_sub_domain)"
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done
}

_baidu_get_root_dns() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    if [ -z "$h" ]; then
      _baidu_err "invalid domain: $domain"
      return 1
    fi

    if ! _baidu_dns_call "GET" "/v1/dns/zone/${h}/record" ""; then
      _baidu_info "baidu_dns_call failed: list zones"
    elif ! _baidu_is_api_error "$response" && (_contains "$response" "\"records\"" || _contains "$response" "\"maxKeys\""); then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain=$h
      if [ "$_sub_domain" = "$_domain" ]; then
        _sub_domain="@"
      fi
      _baidu_info "zone matched by dns api: $_domain (host: $_sub_domain)"
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done
}

_baidu_find_record_ids_current() {
  if [ "$_baidu_api_engine" = "new" ]; then
    _baidu_find_record_ids_dns "$@"
  else
    _baidu_find_record_ids "$@"
  fi
}

_baidu_find_record_ids() {
  _zone_name="$1"
  _record_domain="$2"
  _rdtype="$3"
  _rdata="$4"

  # Reset global result variable
  _BAIDU_FIND_RESULT=""

  _zone_name_e="$(_baidu_json_escape "$_zone_name")"
  _record_domain_e="$(_baidu_json_escape "$_record_domain")"
  _rdtype_e="$(_baidu_json_escape "$_rdtype")"
  _rdata_e="$(_baidu_json_escape "$_rdata")"

  _page=1
  _page_size=100
  _ids=""

  _max_page=""
  while true; do
    if ! _baidu_bcd_post "/domain/resolve/list" "$(_baidu_payload_list "$_zone_name" "$_page" "$_page_size")"; then
      _baidu_err "baidu_bcd_post failed: list records"
      return 1
    fi

    if _baidu_is_api_error "$response"; then
      _baidu_err "baidu_bcd error: $(_baidu_json_get_str "$response" "code") $(_baidu_json_get_str "$response" "message")"
      return 1
    fi

    _normalized="$(
      printf "%s" "$response" | _normalizeJson
    )"

    if [ -z "$_max_page" ]; then
      _total="$(_baidu_parse_totalcount "$_normalized")"
      _max_page="$(_baidu_calc_max_page "$_total" "$_page_size")"
    fi

    _records=$(printf "%s" "$_normalized" | sed 's/},{/}\n{/g')
    while IFS= read -r _line; do
      _id="$(_baidu_match_record_id "$_line" "$_record_domain_e" "$_rdtype_e" "$_rdata_e")"
      if [ "$_id" ]; then
        _ids="$_ids $_id"
      fi
    done <<EOF
$_records
EOF

    if [ "$_page" -ge "$_max_page" ]; then
      break
    fi
    _page=$(_math "$_page" + 1)
  done

  # Store result in global variable instead of stdout
  _BAIDU_FIND_RESULT="$_ids"
}

_baidu_find_record_ids_dns() {
  _zone_name="$1"
  _record_domain="$2"
  _rdtype="$3"
  _rdata="$4"
  _BAIDU_FIND_RESULT=""

  if ! _baidu_dns_call "GET" "/v1/dns/zone/${_zone_name}/record" ""; then
    _baidu_err "baidu_dns_call failed: list records"
    return 1
  fi

  if _baidu_is_api_error "$response"; then
    _baidu_err "baidu_dns error: $(_baidu_json_get_str "$response" "code") $(_baidu_json_get_str "$response" "message")"
    return 1
  fi

  _normalized="$(printf "%s" "$response" | _normalizeJson)"
  _records=$(printf "%s" "$_normalized" | sed 's/},{/}\n{/g')
  _ids=""

  while IFS= read -r _line; do
    _id="$(_baidu_match_record_id_dns "$_line" "$_record_domain" "$_rdtype" "$_rdata")"
    if [ "$_id" ]; then
      _ids="$_ids $_id"
    fi
  done <<EOF
$_records
EOF

  _BAIDU_FIND_RESULT="$_ids"
}

# --- HTTP ---
_baidu_bcd_post() {
  _api_path="$1"
  _payload="$2"

  # BCD API requires JSON payload. Some call sites build fragments; normalize defensively.
  _payload="$(_baidu_normalize_payload "$_payload")"

  _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  _expire="${Baidu_BCD_Expire:-3600}"
  _content_type="application/json; charset=utf-8"
  _payload_hash="$(printf "%s" "$_payload" | _digest sha256 hex)"

  _uri="/v${BAIDU_BCD_VERSION}${_api_path}"
  if ! _baidu_bce_auth "POST" "$_uri" "" "$BAIDU_BCD_HOST" "$_ts" "$_expire" "$_content_type" "$_payload_hash"; then
    _baidu_err "baidu_bcd auth failed"
    return 1
  fi
  _auth="$_BAIDU_BCE_AUTH_RESULT"
  if [ -z "$_auth" ]; then
    _baidu_err "baidu_bcd auth failed"
    return 1
  fi

  _url="https://${BAIDU_BCD_HOST}${_uri}"
  _signed_headers_dbg="$(printf "%s" "$_auth" | cut -d / -f 5)"
  _baidu_info "POST ${_uri}"
  _baidu_info "signedHeaders: $_signed_headers_dbg"
  _baidu_info "payload_sha256: $_payload_hash"
  _baidu_debug "baidu_bcd.http.payload" "$(_baidu_dbg_trim "$(_baidu_redact_txt "$_payload")")"
  _H1="Authorization: $_auth"
  _H2="x-bce-date: $_ts"
  _H3="x-bce-content-sha256: $_payload_hash"
  _H4="Host: $BAIDU_BCD_HOST"
  _H5=""
  response="$(_post "$_payload" "$_url" "" "POST" "$_content_type")"
  _ret="$?"
  _baidu_info "ret: $_ret"
  _req_id="$(_baidu_json_get_str "$response" "requestId")"
  _code="$(_baidu_json_get_str "$response" "code")"
  _msg="$(_baidu_json_get_str "$response" "message")"
  _baidu_info "response: requestId=${_req_id:-"-"} code=${_code:-"-"} message=$(_baidu_dbg_trim "${_msg:-"-"}")"
  if [ "$_ret" != "0" ]; then
    _baidu_err "baidu_bcd_post failed: $_uri"
    return 1
  fi

  return 0
}

_baidu_dns_call() {
  _method="$1"
  _uri="$2"
  _payload="$3"
  _content_type="application/json"
  _attempt=1
  _max_attempts=3

  while [ "$_attempt" -le "$_max_attempts" ]; do
    _ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    _payload_hash="$(printf "%s" "$_payload" | _digest sha256 hex)"

    if ! _baidu_bce_auth "$_method" "$_uri" "" "$BAIDU_DNS_HOST" "$_ts" "${Baidu_BCD_Expire:-3600}" "$_content_type" "$_payload_hash"; then
      _baidu_err "baidu_dns auth failed"
      return 1
    fi
    _auth="$_BAIDU_BCE_AUTH_RESULT"
    _url="https://${BAIDU_DNS_HOST}${_uri}"

    # Route through acme.sh's _get/_post (they honor _H1.._H5); no raw curl.
    _H1="Authorization: $_auth"
    _H2="x-bce-date: $_ts"
    _H3="x-bce-content-sha256: $_payload_hash"
    _H4="Host: $BAIDU_DNS_HOST"
    _H5="Content-Type: $_content_type"

    if [ "$_method" = "GET" ]; then
      response="$(_get "$_url")"
    elif [ "$_method" = "DELETE" ]; then
      response="$(_post "" "$_url" "" "DELETE")"
    else
      response="$(_post "$_payload" "$_url")"
    fi
    _ret="$?"
    _baidu_info "${_method} ${_uri} ret=${_ret}"

    # Baidu may return a business error (Exception / 平台服务繁忙) inside HTTP 200.
    if [ "$_ret" = "0" ] && ! _contains "$response" "\"code\":\"Exception\"" && ! _contains "$response" "平台服务繁忙"; then
      return 0
    fi

    if [ "$_attempt" -lt "$_max_attempts" ]; then
      sleep 2
    fi
    _attempt=$(_math "$_attempt" + 1)
  done

  return 1
}

# --- Auth / Signing ---
_baidu_bce_auth() {
  # Signing algorithm (bce-auth-v1):
  # - SigningKey = HMAC-SHA256-HEX(sk, authStringPrefix)
  # - Signature  = HMAC-SHA256-HEX(SigningKey, CanonicalRequest)
  # Reference: https://cloud.baidu.com/doc/Reference/s/njwvz1yfu
  _method="$1"
  _uri="$2"
  _query="$3"
  _host="$4"
  _ts="$5"
  _expire="$6"
  _ct="$7"
  _payload_hash="$8"

  _BAIDU_BCE_AUTH_RESULT=""

  _auth_prefix="bce-auth-v1/${Baidu_AK}/${_ts}/${_expire}"

  _signed_headers="content-type;host;x-bce-content-sha256;x-bce-date"
  _canonical_uri="$(_baidu_bce_encode_path "$_uri")"
  _canonical_query=""

  _host_v="$(_baidu_trim_ws "$_host")"
  _date_v="$(_baidu_trim_ws "$_ts")"
  _ct_v="$(_baidu_trim_ws "$_ct")"
  _host_e="$(printf "%s" "$_host_v" | _url_encode upper-hex)"
  _date_e="$(printf "%s" "$_date_v" | _url_encode upper-hex)"
  _ct_e="$(printf "%s" "$_ct_v" | _url_encode upper-hex)"
  _hash_e="$(printf "%s" "$_payload_hash" | _url_encode upper-hex)"

  _canonical_headers="content-type:${_ct_e}
host:${_host_e}
x-bce-content-sha256:${_hash_e}
x-bce-date:${_date_e}"

  _canonical_request="${_method}
${_canonical_uri}
${_canonical_query}
${_canonical_headers}"

  _sk_hex="$(printf "%s" "$Baidu_SK" | _hex_dump | tr -d " ")"
  _signing_key="$(_baidu_hmac_sha256_hexkey "$_sk_hex" "$_auth_prefix")"
  _signing_key_hex="$(printf "%s" "$_signing_key" | _hex_dump | tr -d " ")"
  _signature="$(_baidu_hmac_sha256_hexkey "$_signing_key_hex" "$_canonical_request")"

  _baidu_debug "baidu_bcd.auth" "bce_auth"
  _baidu_debug "baidu_bcd.auth.auth_prefix" "bce-auth-v1/[ak]/${_ts}/${_expire}/$_signed_headers/[signature]"
  _baidu_debug "baidu_bcd.auth.canonical_request_l" "$(printf "%s" "$_canonical_request" | sed -n 'l')"
  _baidu_debug "baidu_bcd.auth.signature" "$(printf "%s" "$_signature" | cut -c 1-16)..."
  _BAIDU_BCE_AUTH_RESULT="${_auth_prefix}/${_signed_headers}/${_signature}"
  return 0
}

_baidu_bce_encode_path() {
  _p="$1"
  _out=""
  if [ "${_p#"/"}" != "$_p" ]; then
    _out="/"
  fi

  _rest="${_p#/}"
  while [ -n "$_rest" ]; do
    _seg="${_rest%%/*}"
    if [ "$_seg" ]; then
      if [ -z "$_out" ] || [ "$_out" = "/" ]; then
        _out="${_out}$(printf "%s" "$_seg" | _url_encode upper-hex)"
      else
        _out="${_out}/$(printf "%s" "$_seg" | _url_encode upper-hex)"
      fi
    fi
    if [ "${_rest#*/}" = "$_rest" ]; then
      break
    fi
    _rest="${_rest#*/}"
  done

  if [ -z "$_out" ]; then
    _out="/"
  fi
  printf "%s" "$_out"
}

# --- Utils ---
_baidu_trim() {
  printf "%s" "$1" | sed 's/^ *//;s/ *$//'
}

_baidu_trim_ws() {
  printf "%s" "$1" | tr '\r\n\t' '   ' | tr -s ' ' | sed 's/^ *//;s/ *$//'
}

_baidu_dbg_trim() {
  printf "%s" "$1" | tr '\r\n' ' ' | cut -c 1-800
}

_baidu_is_api_error() {
  _contains "$1" "\"code\"" && _contains "$1" "\"message\""
}

_baidu_normalize_payload() {
  _p="$(_baidu_trim "$(printf "%s" "$1" | tr -d '\r')")"
  if [ -z "$_p" ]; then
    printf "%s" ""
    return 0
  fi
  case "$_p" in
  \{* | \[*)
    printf "%s" "$_p"
    ;;
  *)
    printf "%s" "{$_p}"
    ;;
  esac
}

_baidu_redact_txt() {
  printf "%s" "$1" | sed 's/"rdata" *: *"[^"]*"/"rdata":"[redacted]"/g'
}

_baidu_json_get_str() {
  _json="$1"
  _key="$2"
  printf "%s" "$_json" | _normalizeJson | sed -n "s/.*\"${_key}\" *: *\"\\([^\"]*\\)\".*/\\1/p" | _head_n 1
}

_baidu_json_escape() {
  _s="$1"
  _s="$(printf "%s" "$_s" | tr -d '\r\n')"
  printf "%s" "$_s" |
    sed 's/\\/\\\\/g; s/	/\\t/g' |
    _baidu_json_encode
}

_baidu_json_encode() {
  _j_str="$(sed 's/"/\\"/g' | sed "s/\r/\\r/g")"
  printf "%s" "$_j_str" | _hex_dump | _lower_case | sed 's/0a/5c 6e/g' | tr -d ' ' | _h2b | tr -d "\r\n"
}

_baidu_payload_list() {
  _domain="$(_baidu_json_escape "$1")"
  _pageNo="$2"
  _pageSize="$3"
  printf "%s" "{\"domain\":\"${_domain}\",\"pageNo\":${_pageNo},\"pageSize\":${_pageSize}}"
}

_baidu_payload_add_txt() {
  _zoneName="$(_baidu_json_escape "$1")"
  _domain="$(_baidu_json_escape "$2")"
  _rdata="$(_baidu_json_escape "$3")"
  _ttl="$4"
  _view="$(_baidu_json_escape "$5")"
  printf "%s" "{\"domain\":\"${_domain}\",\"view\":\"${_view}\",\"rdType\":\"TXT\",\"ttl\":${_ttl},\"rdata\":\"${_rdata}\",\"zoneName\":\"${_zoneName}\"}"
}

_baidu_payload_add_txt_dns() {
  _rr="$(printf "%s" "$1" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  _value="$(printf "%s" "$2" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  _ttl="$3"
  _line="$(printf "%s" "$4" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  printf "%s" "{\"rr\":\"${_rr}\",\"type\":\"TXT\",\"value\":\"${_value}\",\"ttl\":${_ttl},\"line\":\"${_line}\",\"description\":\"acme.sh\"}"
}

_baidu_payload_delete() {
  _zoneName="$(_baidu_json_escape "$1")"
  _recordId="$2"
  printf "%s" "{\"zoneName\":\"${_zoneName}\",\"recordId\":${_recordId}}"
}

_baidu_parse_totalcount() {
  _json="$1"
  printf "%s" "$_json" | _egrep_o "\"totalCount\": *[0-9]*" | _head_n 1 | cut -d : -f 2 | tr -d " "
}

_baidu_calc_max_page() {
  _total="$1"
  _page_size="$2"
  if [ -z "$_total" ]; then
    printf "%s" "1"
    return 0
  fi
  _max=$(((_total + _page_size - 1) / _page_size))
  if [ "$_max" -lt 1 ]; then
    _max=1
  fi
  printf "%s" "$_max"
}

_baidu_match_record_id() {
  _line="$1"
  _domain_e="$2"
  _rdtype_e="$3"
  _rdata_e="$4"
  if ! _contains "$_line" "\"recordId\"" || (! _contains "$_line" "\"domain\":\"$_domain_e\"" && ! _contains "$_line" "\"domain\":\"${_domain_e}.\""); then
    return 0
  fi
  if ! _contains "$_line" "\"rdtype\":\"$_rdtype_e\"" && ! _contains "$_line" "\"rdType\":\"$_rdtype_e\""; then
    return 0
  fi
  if [ "$_rdata_e" ] && ! _contains "$_line" "\"rdata\":\"$_rdata_e\""; then
    return 0
  fi
  printf "%s" "$_line" | _egrep_o "\"recordId\": *[0-9]*" | _head_n 1 | cut -d : -f 2 | tr -d " "
}

_baidu_match_record_id_dns() {
  _line="$1"
  _rr="$(printf "%s" "$2" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  _type="$(printf "%s" "$3" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  _value="$(printf "%s" "$4" | tr -d '\r\n' | sed 's/\\/\\\\/g; s/"/\\"/g')"
  case "$_line" in
  *"\"rr\":\"${_rr}\""*"\"type\":\"${_type}\""*"\"value\":\"${_value}\""*)
    printf "%s" "$_line" | sed -n 's/.*"id":"\{0,1\}\([^",}]*\)"\{0,1\}.*/\1/p' | _head_n 1
    ;;
  esac
}

_baidu_hmac_sha256_hexkey() {
  _key_hex="$1"
  _msg="$2"
  printf "%s" "$_msg" | _hmac sha256 "$_key_hex" hex
}
