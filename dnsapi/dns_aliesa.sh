#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_aliesa_info='AlibabaCloud.com ESA
Domains: Aliyun.com
Site: AlibabaCloud.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_aliesa
Options:
 AliESA_Key API Key
 AliESA_Secret API Secret
 AliESA_Endpoint API Endpoint. Default "https://esa.ap-southeast-1.aliyuncs.com/". Optional.
Issues: github.com/acmesh-official/acme.sh/issues/7357
Author: @caikun233
'

Ali_ESA_API_DEFAULT="https://esa.ap-southeast-1.aliyuncs.com/"

#Usage: dns_aliesa_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_aliesa_add() {
  #the API only accepts punycode for IDN domains, and a raw UTF-8 domain
  #also breaks the request signature.
  #the record name must be lower case, and DNS names are case-insensitive.
  fulldomain="$(_idn "$1" | _lower_case)"
  txtvalue="$2"

  if [ -z "$fulldomain" ]; then
    _err "Cannot convert the domain to punycode: $1"
    return 1
  fi

  _aliesa_prepare_credentials || return 1

  _debug "First detect the site"
  if ! _aliesa_get_site "$fulldomain"; then
    _err "Site not found for $fulldomain"
    return 1
  fi

  _debug "Add record"
  _aliesa_add_record_query "$_site_id" "$fulldomain" "$txtvalue" && _aliesa_rest "Add record" "" "POST"
}

dns_aliesa_rm() {
  fulldomain="$(_idn "$1" | _lower_case)"

  if [ -z "$fulldomain" ]; then
    _err "Cannot convert the domain to punycode: $1"
    return 1
  fi
  txtvalue="$2"

  _debug "Calling dns_aliesa_rm for domain: $fulldomain"

  _aliesa_prepare_credentials || return 1

  _debug "First detect the site"
  if ! _aliesa_get_site "$fulldomain"; then
    _err "Site not found for $fulldomain"
    return 1
  fi

  _aliesa_clean_record
}

####################  Alibaba Cloud common functions below  ####################

_aliesa_prepare_credentials() {
  AliESA_Key="${AliESA_Key:-$(_readaccountconf_mutable AliESA_Key)}"
  AliESA_Secret="${AliESA_Secret:-$(_readaccountconf_mutable AliESA_Secret)}"
  AliESA_Endpoint="${AliESA_Endpoint:-$(_readaccountconf_mutable AliESA_Endpoint)}"
  if [ -z "$AliESA_Key" ] || [ -z "$AliESA_Secret" ]; then
    AliESA_Key=""
    AliESA_Secret=""
    _err "You don't specify aliyun ESA api key and secret yet."
    return 1
  fi

  if [ -z "$AliESA_Endpoint" ]; then
    AliESA_Endpoint="$Ali_ESA_API_DEFAULT"
  fi
  #the endpoint is used as "$endpoint?Signature=...", so it must end with "/"
  case "$AliESA_Endpoint" in
  */) ;;
  *) AliESA_Endpoint="$AliESA_Endpoint/" ;;
  esac
  Ali_ESA_API="$AliESA_Endpoint"

  #save the api key and secret to the account conf file.
  _saveaccountconf_mutable AliESA_Key "$AliESA_Key"
  _saveaccountconf_mutable AliESA_Secret "$AliESA_Secret"
  _saveaccountconf_mutable AliESA_Endpoint "$AliESA_Endpoint"
  return 0
}

# act ign mtd
_aliesa_rest() {
  act="$1"
  ign="$2"
  mtd="${3:-GET}"

  signature=$(printf "%s" "$mtd&%2F&$(printf "%s" "$query" | _url_encode upper-hex)" | _hmac "sha1" "$(printf "%s" "$AliESA_Secret&" | _hex_dump | tr -d " ")" | _base64)
  signature=$(printf "%s" "$signature" | _url_encode upper-hex)
  url="$endpoint?Signature=$signature"

  _debug "Requesting $act..."

  if [ "$mtd" = "GET" ]; then
    url="$url&$query"
    response="$(_get "$url")"
  else
    response="$(_post "$query" "$url" "" "$mtd" "application/x-www-form-urlencoded")"
  fi

  _ret="$?"
  _debug2 response "$response"

  if [ "$_ret" != "0" ]; then
    _err "Error <$act>"
    return 1
  fi

  if [ -z "$ign" ]; then
    # ESA error structure might overlap with ALI DNS, checking for "Message" or "Code"
    message="$(echo "$response" | _egrep_o "\"Message\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")"
    if [ "$message" ]; then
      _err "$message"
      return 1
    fi
  fi
}

# SignatureNonce must be unique for every request. Derive it from core helpers
# only: time, pid, a per-process counter and a per-request hint.
_aliesa_nonce() {
  _aliesa_nonce_seq=$(_math "${_aliesa_nonce_seq:-0}" + 1)
  _aliesa_nonce_value="$(printf "%s" "$(_time)${_aliesa_nonce_seq}$$$1" | _digest sha256 hex | cut -c 1-32)"
}

_aliesa_timestamp() {
  date -u +"%Y-%m-%dT%H%%3A%M%%3A%SZ"
}

####################  Private functions below  ####################

_aliesa_get_site() {
  domain=$1
  i=1
  while true; do
    h="$(printf "%s" "$domain" | cut -d . -f "$i"-100)"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    _aliesa_list_sites_query "$h"
    if ! _aliesa_rest "Get site" "ignore"; then
      return 1
    fi

    if _contains "$response" "\"TotalCount\""; then
      count="$(printf "%s" "$response" | _egrep_o "\"TotalCount\":[0-9]+" | cut -d : -f 2)"
      if [ "$count" ] && [ "$count" -gt 0 ]; then
        #extract the SiteId
        _site_id="$(printf "%s" "$response" | _egrep_o "\"SiteId\":[0-9]+" | _head_n 1 | cut -d : -f 2)"
        _debug _site_id "$_site_id"
        return 0
      fi
    fi
    i=$(_math "$i" + 1)
  done
  return 1
}

# Sorted alphabetically by parameter name:
# AccessKeyId, Action, Format, SignatureMethod, SignatureNonce, SignatureVersion, SiteName, SiteSearchType, Timestamp, Version
_aliesa_list_sites_query() {
  endpoint=$Ali_ESA_API
  query=''
  query=$query'AccessKeyId='$AliESA_Key
  query=$query'&Action=ListSites'
  query=$query'&Format=json'
  query=$query'&SignatureMethod=HMAC-SHA1'
  _aliesa_nonce "ListSites:$1"
  query=$query"&SignatureNonce=$_aliesa_nonce_value"
  query=$query'&SignatureVersion=1.0'
  query=$query'&SiteName='$1
  query=$query'&SiteSearchType=exact'
  query=$query'&Timestamp='$(_aliesa_timestamp)
  query=$query'&Version=2024-09-10'
}

# Sorted alphabetically by parameter name:
# AccessKeyId, Action, Data, Format, RecordName, SignatureMethod, SignatureNonce, SignatureVersion, SiteId, Timestamp, Ttl, Type, Version
_aliesa_add_record_query() {
  endpoint=$Ali_ESA_API
  query=''
  query=$query'AccessKeyId='$AliESA_Key
  query=$query'&Action=CreateRecord'

  # Data needs to be URL encoded if it contains special chars
  # We construct it locally then encode
  data_val="{\"value\":\"$3\"}"
  data_enc=$(printf "%s" "$data_val" | _url_encode upper-hex)

  query=$query'&Data='$data_enc
  query=$query'&Format=json'
  query=$query'&RecordName='$2
  query=$query'&SignatureMethod=HMAC-SHA1'
  _aliesa_nonce "CreateRecord:$1:$2:$3"
  query=$query"&SignatureNonce=$_aliesa_nonce_value"
  query=$query'&SignatureVersion=1.0'
  query=$query'&SiteId='$1
  query=$query'&Timestamp='$(_aliesa_timestamp)
  query=$query'&Ttl=30'
  query=$query'&Type=TXT'
  query=$query'&Version=2024-09-10'
}

# Sorted alphabetically by parameter name:
# AccessKeyId, Action, Format, RecordId, SignatureMethod, SignatureNonce, SignatureVersion, Timestamp, Version
_aliesa_delete_record_query() {
  endpoint=$Ali_ESA_API
  query=''
  query=$query'AccessKeyId='$AliESA_Key
  query=$query'&Action=DeleteRecord'
  query=$query'&Format=json'
  query=$query'&RecordId='$1
  query=$query'&SignatureMethod=HMAC-SHA1'
  _aliesa_nonce "DeleteRecord:$1"
  query=$query"&SignatureNonce=$_aliesa_nonce_value"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_aliesa_timestamp)
  query=$query'&Version=2024-09-10'
}

# Sorted alphabetically by parameter name:
# AccessKeyId, Action, Format, RecordName, SignatureMethod, SignatureNonce, SignatureVersion, SiteId, Timestamp, Type, Version
_aliesa_list_records_query() {
  endpoint=$Ali_ESA_API
  query=''
  query=$query'AccessKeyId='$AliESA_Key
  query=$query'&Action=ListRecords'
  query=$query'&Format=json'
  query=$query'&RecordName='$2
  query=$query'&SignatureMethod=HMAC-SHA1'
  _aliesa_nonce "ListRecords:$1:$2"
  query=$query"&SignatureNonce=$_aliesa_nonce_value"
  query=$query'&SignatureVersion=1.0'
  query=$query'&SiteId='$1
  query=$query'&Timestamp='$(_aliesa_timestamp)
  query=$query'&Type=TXT'
  query=$query'&Version=2024-09-10'
}

_aliesa_clean_record() {
  _debug "Starting record cleanup for TXT value: $txtvalue"
  # Retry loop to handle syncing delay
  i=1
  while [ "$i" -le 3 ]; do
    _debug "Clean check iteration $i"
    _aliesa_list_records_query "$_site_id" "$fulldomain"
    if _aliesa_rest "List records" "ignore"; then
      # 1. Drop the line breaks and the spaces around ":" so every record fits
      #    on one line and the value can be matched literally.
      clean_json="$(printf "%s" "$response" | _normalizeJson)"

      # 2. Split the Records array: the separator between two objects is
      #    "},{" (or "}, {" before _normalizeJson ran), so each RecordId stays
      #    next to its Value.
      #    A "\n" in a sed replacement is a GNU extension that BSD and busybox
      #    sed print literally, so use an escaped newline instead.
      #    echo terminates the last line, which Oracle Solaris sed would drop.
      records_list="$(echo "$clean_json" | sed 's/},[ ]*{/},\
{/g')"

      # 3. Find the record whose value matches ours. Solaris /usr/bin/grep has
      #    no -F, so match the value with a quoted case pattern instead.
      _debug "Searching for value in record list..."
      # ESA returns "Data":{"Value":"..."} in list responses, even if we sent lowercase.
      _aliesa_target=''
      while IFS= read -r _aliesa_line; do
        case "$_aliesa_line" in
        *"\"Value\":\"$txtvalue\""* | *"\"value\":\"$txtvalue\""*)
          _aliesa_target="$_aliesa_line"
          break
          ;;
        esac
      done <<EOF
$records_list
EOF

      if [ "$_aliesa_target" ]; then
        _debug "Record found: $_aliesa_target"
        # 4. Extract RecordId from that specific line
        rec_id="$(printf "%s" "$_aliesa_target" | _egrep_o "\"RecordId\": *[0-9]+" | cut -d : -f 2 | tr -d ' \"')"

        if [ "$rec_id" ]; then
          _debug "Found existing record ID to delete: $rec_id"
          _aliesa_delete_record_query "$rec_id"
          if ! _aliesa_rest "Delete record $rec_id" "" "POST"; then
            _err "Failed to delete the TXT record: $rec_id"
            return 1
          fi
          _debug "Deleted record $rec_id"
          return 0
        else
          _debug "Parsing RecordId failed from line."
        fi
      else
        _debug "Target value not found in current record list."
      fi
    fi
    i=$(_math "$i" + 1)
    if [ "$i" -le 3 ]; then
      _debug "Record not found yet, retrying in 3s..."
      _sleep 3
    fi
  done

  #the record may already be gone, which is not an error for the rm hook
  _debug "Record not found, nothing to clean."
  return 0
}
