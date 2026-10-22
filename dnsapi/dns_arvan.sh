#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_arvan_info='ArvanCloud.ir
Site: ArvanCloud.ir
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_arvan
Options:
 Arvan_Token API key, with or without the Apikey prefix
Issues: github.com/acmesh-official/acme.sh/issues/2796
Author: Vahid Fardi, Abolfazl Rajabpour (abooraja)
'

ARVAN_API_URL="https://napi.arvancloud.ir/cdn/4.0/domains"

########  Public functions #####################

# Usage: dns_arvan_add _acme-challenge.www.example.com "TXT value"
dns_arvan_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _arvan_init; then
    return 1
  fi
  if ! _saveaccountconf_mutable Arvan_Token "$Arvan_Token"; then
    _err "Unable to save the Arvan API credentials."
    return 1
  fi
  if ! _get_root "$fulldomain" || ! _arvan_find_record; then
    return 1
  fi
  if [ "$_arvan_record_ids" ]; then
    _info "TXT record already exists."
    return 0
  fi

  # Append a separate record: apex and wildcard challenges can share a name.
  if ! _arvan_rest POST "$_domain/dns-records" "{\"type\":\"TXT\",\"name\":\"$_sub_domain\",\"value\":{\"text\":\"$txtvalue\"},\"ttl\":120}"; then
    _arvan_add_code=$_arvan_code
    # Another client may have added the same value since the lookup.
    case "$_arvan_add_code" in
    409 | 422)
      if _arvan_find_record && [ "$_arvan_record_ids" ]; then
        _info "TXT record already exists."
        return 0
      fi
      ;;
    esac
    _err "Unable to add the Arvan TXT record (HTTP $_arvan_add_code)."
    return 1
  fi
  _info "TXT record added."
  return 0
}

# Usage: dns_arvan_rm _acme-challenge.www.example.com "TXT value"
dns_arvan_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _arvan_init || ! _get_root "$fulldomain" || ! _arvan_find_record; then
    return 1
  fi
  if [ -z "$_arvan_record_ids" ]; then
    _info "TXT record is already absent."
    return 0
  fi

  # Record IDs are validated before they are used as path components.
  for _arvan_record_id in $_arvan_record_ids; do
    if ! _arvan_rest DELETE "$_domain/dns-records/$_arvan_record_id"; then
      if [ "$_arvan_code" != "404" ]; then
        _err "Unable to remove the Arvan TXT record (HTTP $_arvan_code)."
        return 1
      fi
    fi
  done
  _info "TXT record removed."
  return 0
}

####################  Private functions below ##################################

_arvan_init() {
  Arvan_Token="${Arvan_Token:-$(_readaccountconf_mutable Arvan_Token)}"
  Arvan_Token=${Arvan_Token#\"}
  Arvan_Token=${Arvan_Token%\"}
  if [ -z "$Arvan_Token" ]; then
    _err "You didn't specify Arvan_Token."
    _err "Get an API key from https://npanel.arvancloud.ir/profile/api-keys"
    return 1
  fi
}

# Find the longest managed suffix, including the full name for DNS alias mode.
_get_root() {
  domain=$(printf "%s" "$1" | _lower_case)
  domain=${domain%.}
  _domain=""
  _sub_domain=""
  case "$domain" in
  "" | *[!a-z0-9_.-]* | .* | *..*)
    _err "Invalid DNS name."
    return 1
    ;;
  esac

  if ! _arvan_list ""; then
    return 1
  fi
  if ! _arvan_zones=$(_arvan_get_data domains); then
    _err "Invalid Arvan domains response."
    return 1
  fi
  h=$domain
  while true; do
    case "
$_arvan_zones
" in
    *"
$h
"*)
      _domain=$h
      _sub_domain=${domain%."$h"}
      if [ "$domain" = "$h" ]; then
        _sub_domain="@"
      fi
      _debug _domain "$_domain"
      _debug _sub_domain "$_sub_domain"
      return 0
      ;;
    esac
    case "$h" in
    *.*) h=${h#*.} ;;
    *) break ;;
    esac
  done
  _err "No matching zone found in the Arvan account."
  return 1
}

_arvan_find_record() {
  _arvan_record_ids=""
  if ! _arvan_list "$_domain/dns-records?type=txt"; then
    return 1
  fi
  if ! _arvan_record_ids=$(_arvan_get_data records); then
    _err "Invalid Arvan DNS records response."
    return 1
  fi
}

# Collect all pages before matching, so a delegated zone on a later page wins.
_arvan_list() {
  _arvan_path=$1
  _arvan_page=1
  _arvan_result=""
  while true; do
    case "$_arvan_path" in
    *\?*) _arvan_page_endpoint="$_arvan_path&page=$_arvan_page" ;;
    *) _arvan_page_endpoint="$_arvan_path?page=$_arvan_page" ;;
    esac
    if ! _arvan_rest GET "$_arvan_page_endpoint"; then
      _err "Unable to list Arvan resources (HTTP $_arvan_code)."
      return 1
    fi
    _arvan_current_page=$(printf "%s" "$response" | _egrep_o '"current_page"[ 	]*:[ 	]*[0-9][0-9]*' | cut -d : -f 2 | tr -d ' \t')
    _arvan_last_page=$(printf "%s" "$response" | _egrep_o '"last_page"[ 	]*:[ 	]*[0-9][0-9]*' | cut -d : -f 2 | tr -d ' \t')
    case "$_arvan_last_page" in
    "" | *[!0-9]*)
      _err "Invalid Arvan pagination."
      return 1
      ;;
    esac
    if [ "$_arvan_current_page" != "$_arvan_page" ] || [ "$_arvan_last_page" -lt "$_arvan_page" ]; then
      _err "Unexpected Arvan page number."
      return 1
    fi
    _arvan_result="$_arvan_result
$response"
    if [ "$_arvan_page" -eq "$_arvan_last_page" ]; then
      response=$_arvan_result
      return 0
    fi
    _arvan_page=$(_math "$_arvan_page" + 1)
  done
}

# Read only fields in data[] objects, independently of JSON field order.
# Tokenize quoted strings first so braces in unrelated TXT values stay intact.
_arvan_get_data() {
  _arvan_mode=$1
  printf "%s\n" "$response" | sed 's/\("[^"\\]*\(\\.[^"\\]*\)*"\)/\
\1\
/g' | sed '/^"/!{
s/[ 	]//g
s/\([][{}:,]\)/\
\1\
/g
}
/^$/d' | (
    _arvan_depth=0
    _arvan_key=""
    _arvan_in_data=""
    _arvan_in_value=""
    _arvan_seen_data=""
    while IFS= read -r _arvan_token; do
      case "$_arvan_token" in
      "{" | "[")
        if [ "$_arvan_depth" = "1" ] && [ "$_arvan_key" = '"data"' ] && [ "$_arvan_token" = "[" ]; then
          _arvan_in_data=1
          _arvan_seen_data=1
        elif [ "$_arvan_in_data" ] && [ "$_arvan_depth" = "2" ]; then
          _arvan_id=""
          _arvan_type=""
          _arvan_name=""
          _arvan_text=""
          _arvan_zone=""
        elif [ "$_arvan_in_data" ] && [ "$_arvan_depth" = "3" ] && [ "$_arvan_key" = '"value"' ] && [ "$_arvan_token" = "{" ]; then
          _arvan_in_value=1
        fi
        _arvan_depth=$(_math "$_arvan_depth" + 1)
        _arvan_key=""
        ;;
      "}" | "]")
        if [ "$_arvan_in_data" ] && [ "$_arvan_depth" = "3" ] && [ "$_arvan_token" = "}" ]; then
          if [ "$_arvan_mode" = "domains" ]; then
            if [ "$_arvan_zone" ]; then
              printf "%s\n" "$_arvan_zone"
            fi
          elif [ "$_arvan_name" = "$_sub_domain" ] && [ "$_arvan_text" = "$txtvalue" ]; then
            case "$_arvan_type" in
            [Tt][Xx][Tt])
              case "$_arvan_id" in
              "" | *[!a-zA-Z0-9-]*) return 1 ;;
              esac
              printf "%s\n" "$_arvan_id"
              ;;
            esac
          fi
        elif [ "$_arvan_depth" = "2" ]; then
          _arvan_in_data=""
        fi
        if [ "$_arvan_depth" = "4" ]; then
          _arvan_in_value=""
        fi
        _arvan_depth=$(_math "$_arvan_depth" - 1)
        _arvan_key=""
        ;;
      "" | ":") ;;
      ",") _arvan_key="" ;;
      *)
        if [ -z "$_arvan_key" ]; then
          _arvan_key=$_arvan_token
        else
          _arvan_value=${_arvan_token#\"}
          _arvan_value=${_arvan_value%\"}
          if [ "$_arvan_in_data" ]; then
            case "$_arvan_depth:$_arvan_key" in
            '3:"domain"') _arvan_zone=$_arvan_value ;;
            '3:"id"') _arvan_id=$_arvan_value ;;
            '3:"type"') _arvan_type=$_arvan_value ;;
            '3:"name"') _arvan_name=$_arvan_value ;;
            '4:"text"')
              if [ "$_arvan_in_value" ]; then
                _arvan_text=$_arvan_value
              fi
              ;;
            esac
          fi
          _arvan_key=""
        fi
        ;;
      esac
    done
    [ "$_arvan_depth" = "0" ] && [ "$_arvan_seen_data" = "1" ]
  )
}

_arvan_rest() {
  _arvan_method=$1
  _arvan_endpoint=$2
  _arvan_data=$3
  _arvan_code=""
  _arvan_auth=$Arvan_Token
  # Preserve existing authorization values; accept a bare UUID API key too.
  case "$_arvan_auth" in
  ????????-????-????-????-????????????) _arvan_auth="Apikey $_arvan_auth" ;;
  esac
  export _H1="Authorization: $_arvan_auth"
  export _H2="Accept: application/json"
  export _H3=""
  export _H4=""
  export _H5=""
  if [ "$_arvan_method" = "POST" ]; then
    export _H3="Content-Type: application/json"
  fi
  case "$_arvan_endpoint" in
  "" | \?*) _arvan_url="$ARVAN_API_URL$_arvan_endpoint" ;;
  *) _arvan_url="$ARVAN_API_URL/$_arvan_endpoint" ;;
  esac

  if [ "$_arvan_method" = "GET" ]; then
    if ! response=$(_get "$_arvan_url"); then
      _err "Arvan API request failed."
      return 1
    fi
  elif ! response=$(_post "$_arvan_data" "$_arvan_url" "" "$_arvan_method"); then
    _err "Arvan API request failed."
    return 1
  fi
  _arvan_code=$(grep '^HTTP/' "$HTTP_HEADER" | _tail_n 1 | cut -d ' ' -f 2 | tr -d '\r\n')
  _debug "Arvan HTTP status" "$_arvan_code"
  _secure_debug2 response "$response"
  response=$(printf "%s" "$response" | _normalizeJson)
  case "$_arvan_code" in
  2[0-9][0-9]) return 0 ;;
  esac
  return 1
}
