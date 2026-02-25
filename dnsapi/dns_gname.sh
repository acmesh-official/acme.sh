#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_gname_info='GNAME
Site: gname.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_gname
Options:
 GNAME_APPID Your APPID
 GNAME_APPKEY Your APPKEY
OptionsAlt:
'

GNAME_TLD_Api="https://gname.com/request/tlds?lx=all"
GNAME_Api="https://api.gname.com"
GNAME_TLDS_CACHE=""

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "T1rxqRBosdIK90xWCG3KLZNf6q_0HG9i01zxXp5CASc"
dns_gname_add() {
  fulldomain=$1
  txtvalue=$(printf "%s" "$2" | _url_encode)

  GNAME_APPID="${GNAME_APPID:-$(_readaccountconf_mutable GNAME_APPID)}"
  GNAME_APPKEY="${GNAME_APPKEY:-$(_readaccountconf_mutable GNAME_APPKEY)}"

  if [ -z "$GNAME_APPID" ] || [ -z "$GNAME_APPKEY" ]; then
    GNAME_APPID=""
    GNAME_APPKEY=""
    _err "You have not configured the APPID and APPKEY for the GNAME API."
    _err "You can get yours from here http://gname.com/domain/api."
    return 1
  fi

  _saveaccountconf_mutable GNAME_APPID "$GNAME_APPID"
  _saveaccountconf_mutable GNAME_APPKEY "$GNAME_APPKEY"

  if ! _extract_domain "$fulldomain"; then
    _err "Failed to extract domain. Please check your network or API response."
    return 1
  fi

  gntime=$(date +%s)

  #If the hostname is empty, you need to replace it with @.
  final_hostname=$(printf "%s" "${ext_hostname:-@}" | _url_encode)

  # Parameters need to be sorted by key
  body="appid=$GNAME_APPID&gntime=$gntime&jlz=$txtvalue&lang=us&lx=TXT&mx=0&ttl=600&xl=0&ym=$ext_domain&zj=$final_hostname"

  _info "Adding TXT record for $ext_domain, host: $final_hostname"

  if _post_to_api "/api/resolution/add" "$body"; then
    _info "Successfully added DNS record."
    return 0
  else
    if _contains "$post_response" "the same host records and record values"; then
       _info "Successfully DNS record already exists."
       return 0
    fi
    _err "Failed to add DNS record via Gname API."
    return 1
  fi
}

#Usage: remove  _acme-challenge.www.domain.com   "T1rxqRBosdIK90xWCG3KLZNf6q_0HG9i01zxXp5CASc"
dns_gname_rm() {
  fulldomain=$1
  txtvalue=$2

  GNAME_APPID="${GNAME_APPID:-$(_readaccountconf_mutable GNAME_APPID)}"
  GNAME_APPKEY="${GNAME_APPKEY:-$(_readaccountconf_mutable GNAME_APPKEY)}"

  if [ -z "$GNAME_APPID" ] || [ -z "$GNAME_APPKEY" ]; then
    GNAME_APPID=""
    GNAME_APPKEY=""
    _err "You have not configured the APPID and APPKEY for the GNAME API."
    _err "You can get yours from here http://gname.com/domain/api."
    return 1
  fi

  _saveaccountconf_mutable GNAME_APPID "$GNAME_APPID"
  _saveaccountconf_mutable GNAME_APPKEY "$GNAME_APPKEY"

  if ! _extract_domain "$fulldomain"; then
    _err "Failed to extract domain. Please check your network or API response."
    return 1
  fi

  final_hostname="${ext_hostname:-@}"

  _debug "Query DNS record ID $ext_domain $final_hostname $txtvalue"

  record_id=$(_get_record_id $ext_domain $final_hostname $txtvalue)

  if [ -z "$record_id" ]; then
    _err "No DNS record found"
    return 1
  fi

  _debug "DNS record ID:$record_id";
  gntime=$(date +%s)
  body="appid=$GNAME_APPID&gntime=$gntime&jxid=$record_id&lang=us&ym=$ext_domain"

  if ! _post_to_api "/api/resolution/delete" "$body"; then
    _info "DNS record deletion failed"
    return 1
  fi

  _info "DNS record deletion successful"
  return 0
}

# Find the DNS record ID by hostname, record type, and record value.
_get_record_id() {
  target_ym="$1"
  target_zjt="$2"
  target_jxz="$3"
  target_lx="TXT"

  GNAME_APPID="${GNAME_APPID:-$(_readaccountconf_mutable GNAME_APPID)}"
  GNAME_APPKEY="${GNAME_APPKEY:-$(_readaccountconf_mutable GNAME_APPKEY)}"
  gntime=$(date +%s)
  body="appid=$GNAME_APPID&gntime=$gntime&limit=1000&lx=$target_lx&page=1&ym=$target_ym"

  if ! _post_to_api "/api/resolution/list" "$body"; then
    _err "Query and parsing records failed"
    return 1
  fi

  clean_response=$(echo "$post_response" | tr -d '\r')
  records=$(echo "$clean_response" | sed 's/.*"data":\[//; s/\],"count".*//; s/},/}\n/g')

  _debug "Cleaned Formatted Records:\n$records"

  jxz_feature=$(printf "%s" "$target_jxz" | cut -c 1-10)

  _debug "Searching with host: $target_zjt and feature: $jxz_feature"

  matched_row=$(echo "$records" | grep "\"zjt\":\"$target_zjt\"" | grep "\"jxz\":\"$jxz_feature")

  _debug "Final Matched Row: $matched_row"

  if [ -z "$matched_row" ]; then
    _err "Still can not find record row. Please check if host $target_zjt is correct."
    return 1
  fi

  dns_record_id=$(echo "$matched_row" | _egrep_o "\"id\":\"[^\"]*\"" | head -n 1 | cut -d : -f 2 | tr -d '"')

  if [ -n "$dns_record_id" ]; then
    _debug "Successfully found record ID: $dns_record_id"
    printf "%s" "$dns_record_id"
    return 0
  fi

  return 1
}

# Request GNAME API,post_response: Response content
_post_to_api() {
  uri=$1
  body=$2
  url="$GNAME_Api$uri"
  gntoken=$(_gntoken $body)
  body="$body&gntoken=$gntoken"
  post_response="$(_post "$body" "$url" "" "POST" "application/x-www-form-urlencoded")"

  curl_err_code=$?
  if [ "$curl_err_code" != "0" ]; then
     _err "POST API $url curl error:$curl_err_code"
     return 1
  fi

  ret_code=$(echo "$post_response" | sed 's/.*"code":\([-0-9]*\).*/\1/')
  if [ "$ret_code" = "1" ]; then
    return 0
  else
    ret_msg=$(echo "$post_response" | sed 's/.*"msg":"\([^"]*\)".*/\1/')
    _err "POST API $url error: [$ret_code] $ret_msg"
    _debug "Full response: $post_response"
    return 1
  fi
}

# Split the complete domain into a host and a main domain.
# example, www.gname.com can be split into ext_hostname=www,ext_domain=gname.com
_extract_domain() {

  host="$1"

  # Prioritize reading from the cache and reduce network caching
  if [ -z "$GNAME_TLDS_CACHE" ]; then
    GNAME_TLDS_CACHE=$(_get_suffixes_json)
  fi

  if [ -z "$GNAME_TLDS_CACHE" ]; then
    _err "The list of domain suffixes is empty 02"
    return 1
  fi

  main_part=$(echo "$GNAME_TLDS_CACHE" | sed 's/.*"main":\[\([^]]*\)\].*/\1/' | tr -d '"' | tr ',' ' ')
  sub_part=$(echo "$GNAME_TLDS_CACHE" | sed 's/.*"sub":\[\([^]]*\)\].*/\1/' | tr -d '"' | tr ',' ' ')
  suffix_list=$(echo "$main_part $sub_part" | tr -s ' ' | sed 's/^[ ]//;s/[ ]$//')

  dot_count=$(echo "$host" | grep -o "\." | wc -l)

  if [ "$dot_count" -eq 1 ]; then
    ext_hostname=""
    ext_domain="$host"

    elif [ "$dot_count" -gt 1 ]; then
      matched_suffix=""
      for suffix in $suffix_list; do
        case "$host" in
          *".$suffix")
            if [ -z "$matched_suffix" ] || [ "${#suffix}" -gt "${#matched_suffix}" ]; then
              matched_suffix="$suffix"
            fi
            ;;
        esac
        done

        if [ -n "$matched_suffix" ]; then
          prefix="${host%.$matched_suffix}"
          main_name="${prefix##*.}"

          ext_domain="$main_name.$matched_suffix"

          if [ "$host" = "$ext_domain" ]; then
            ext_hostname=""
          else
            ext_hostname="${host%.$ext_domain}"
          fi

          else
            ext_domain=$(echo "$host" | awk -F. '{print $(NF-1)"."$NF}')
            ext_hostname=$(echo "$host" | rev | cut -d. -f3- | rev)
        fi
    fi
    _debug "ext_hostname:$ext_hostname"
    _debug "ext_domain:$ext_domain"
}

# Obtain the list of domain suffixes via API
_get_suffixes_json() {
  _debug "GET request URL: $GNAME_TLD_Api Retrieves a list of domain suffixes."

  response="$(_get "$GNAME_TLD_Api")"

  if [ "$?" != "0" ]; then
    _err "Failed to retrieve list of domain suffixes"
    return 1
  fi

  if [ -z "$response" ]; then
    _err "The list of domain suffixes is empty"
    return 1
  fi

  if ! _contains "$response" "\"code\":1"; then
    _err "Failed to retrieve list of domain name suffixes; code is not 1"
    return 1
  fi

  echo "$response"
  return 0
}

# Generate API authentication signature
_gntoken() {
  _debug "String to be signed:$1"
  data_to_sign="$1"
  full_data="${data_to_sign}${GNAME_APPKEY}"
  hash=$(printf "%s" "$full_data" | _digest md5 hex | tr -d ' ')
  hash_upper=$(printf "%s" "$hash" | tr 'a-z' 'A-Z')
  _debug "Signature value: $hash_upper"
  printf "%s" "$hash_upper"
}