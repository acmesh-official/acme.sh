#!/usr/bin/env sh
# shellcheck disable=SC2034

dns_yc_info='Yandex Cloud DNS
Site: Cloud.Yandex.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_yc
Options:
 YC_Zone_ID DNS Zone ID
 YC_Folder_ID YC Folder ID
 YC_SA_ID Service Account ID
 YC_SA_Key_ID Service Account IAM Key ID
 YC_SA_Key_File_Path Private key file path. Optional.
 YC_SA_Key_File_PEM_b64 Base64 content of private key file. Use instead of Path to private key file. Optional.
Issues: github.com/acmesh-official/acme.sh/issues/4210
'

YC_Api="https://dns.api.cloud.yandex.net/dns/v1"

########  Public functions #####################

# Usage: dns_yc_add _acme-challenge.www.example.com "txt-value"
dns_yc_add() {
  fulldomain="$(_yc_fqdn "$1")"
  txtvalue="$2"

  _yc_prepare_key_file
  trap _yc_cleanup_key_file 0

  YC_Zone_ID="${YC_Zone_ID:-$(_readaccountconf_mutable YC_Zone_ID)}"
  YC_Folder_ID="${YC_Folder_ID:-$(_readaccountconf_mutable YC_Folder_ID)}"
  YC_SA_ID="${YC_SA_ID:-$(_readaccountconf_mutable YC_SA_ID)}"
  YC_SA_Key_ID="${YC_SA_Key_ID:-$(_readaccountconf_mutable YC_SA_Key_ID)}"

  if ! _yc_validate_creds; then
    return 1
  fi

  # Save settings
  if [ "${YC_Zone_ID:-}" ]; then
    _savedomainconf YC_Zone_ID "$YC_Zone_ID"
  elif [ "${YC_Folder_ID:-}" ]; then
    _savedomainconf YC_Folder_ID "$YC_Folder_ID"
  fi
  _saveaccountconf_mutable YC_SA_ID "$YC_SA_ID"
  _saveaccountconf_mutable YC_SA_Key_ID "$YC_SA_Key_ID"
  if [ "${YC_SA_Key_File_PEM_b64:-}" ]; then
    _saveaccountconf_mutable YC_SA_Key_File_PEM_b64 "$YC_SA_Key_File_PEM_b64"
    _clearaccountconf_mutable YC_SA_Key_File_Path
  else
    _saveaccountconf_mutable YC_SA_Key_File_Path "$YC_SA_Key_File_Path"
    _clearaccountconf_mutable YC_SA_Key_File_PEM_b64
  fi

  _debug "Detecting root zone for: $fulldomain"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting existing TXT recordset"
  if ! _yc_rest GET "zones/${_domain_id}:getRecordSet?type=TXT&name=$(_url_encode "$_sub_domain")"; then
    # Yandex returns 404 if recordset absent — that’s fine for add
    _debug "getRecordSet failed (likely absent), will create new recordset"
    response=""
  fi

  _existing="$(_yc_extract_txt_data_array)"
  _debug existing_data "$_existing"

  # Build merged data array: existing + txtvalue (if not already present)
  _newdata="$(_yc_data_array_add_one "$_existing" "$txtvalue")"
  _debug new_data "$_newdata"

  _info "Adding TXT record value (merge)"
  if _yc_rest POST "zones/$_domain_id:upsertRecordSets" \
    "{\"merges\": [{\"name\":\"$(_yc_json_escape "$_sub_domain")\",\"type\":\"TXT\",\"ttl\":120,\"data\":$_newdata}]}"; then
    if _contains "$response" "\"done\": true"; then
      _info "Added, OK"
      return 0
    fi
  fi

  _err "Add TXT record error."
  return 1
}

# Usage: dns_yc_rm _acme-challenge.www.example.com "txt-value"
dns_yc_rm() {
  fulldomain="$(_yc_fqdn "$1")"
  txtvalue="$2"

  _yc_prepare_key_file
  trap _yc_cleanup_key_file 0

  YC_Zone_ID="${YC_Zone_ID:-$(_readaccountconf_mutable YC_Zone_ID)}"
  YC_Folder_ID="${YC_Folder_ID:-$(_readaccountconf_mutable YC_Folder_ID)}"
  YC_SA_ID="${YC_SA_ID:-$(_readaccountconf_mutable YC_SA_ID)}"
  YC_SA_Key_ID="${YC_SA_Key_ID:-$(_readaccountconf_mutable YC_SA_Key_ID)}"

  if ! _yc_validate_creds; then
    return 1
  fi

  _debug "Detecting root zone for: $fulldomain"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting existing TXT recordset"
  if ! _yc_rest GET "zones/${_domain_id}:getRecordSet?type=TXT&name=$(_url_encode "$_sub_domain")"; then
    _info "No TXT recordset found, skip."
    return 0
  fi

  _existing="$(_yc_extract_txt_data_array)"
  _debug existing_data "$_existing"

  if [ -z "$_existing" ]; then
    _info "No TXT recordset found, skip."
    return 0
  fi

  _newdata="$(_yc_data_array_rm_one "$_existing" "$txtvalue")"
  _debug new_data "$_newdata"

  if [ "$_newdata" = "$_existing" ]; then
    _info "TXT value not found, skip."
    return 0
  fi

  if [ "$_newdata" = "[]" ]; then
    _info "Deleting whole TXT recordset (last value removed)"
    if _yc_rest POST "zones/$_domain_id:updateRecordSets" \
      "{\"deletions\": [{\"name\":\"$(_yc_json_escape "$_sub_domain")\",\"type\":\"TXT\",\"ttl\":120,\"data\":$_existing}]}"; then
      if _contains "$response" "\"done\": true"; then
        _info "Delete, OK"
        return 0
      fi
    fi
  else
    _info "Updating TXT recordset (keeping remaining values)"
    if _yc_rest POST "zones/$_domain_id:upsertRecordSets" \
      "{\"merges\": [{\"name\":\"$(_yc_json_escape "$_sub_domain")\",\"type\":\"TXT\",\"ttl\":120,\"data\":$_newdata}]}"; then
      if _contains "$response" "\"done\": true"; then
        _info "Delete, OK"
        return 0
      fi
    fi
  fi

  _err "Delete record error."
  return 1
}

####################  Private functions below ##################################

# Normalize to fqdn with exactly one trailing dot, lowercase
_yc_fqdn() {
  _d="$(printf "%s" "$1" | _lower_case)"
  # strip ALL trailing dots then add one
  while _endswith "$_d" "."; do
    _d="${_d%?}"
  done
  printf "%s." "$_d"
}

# Same but without trailing dot
_yc_nodot() {
  _d="$(_yc_fqdn "$1")"
  printf "%s" "${_d%.}"
}

# POSIX endswith helper
_endswith() {
  # $1 string, $2 suffix
  case "$1" in
    *"$2") return 0 ;;
    *) return 1 ;;
  esac
}

# URL-encode for query parameter (minimal set)
_url_encode() {
  # acme.sh has _url_replace but it's for base64url; do simple encode here
  # keep: A-Z a-z 0-9 - _ . ~
  # encode others
  printf "%s" "$1" | awk '
    BEGIN {
      for (i=0; i<256; i++) ord[sprintf("%c",i)]=i
    }
    {
      s=$0
      out=""
      for (i=1; i<=length(s); i++) {
        c=substr(s,i,1)
        if (c ~ /[A-Za-z0-9_.~-]/) out = out c
        else out = out sprintf("%%%02X", ord[c])
      }
      printf "%s", out
    }'
}

# JSON string escape (returns escaped string WITHOUT surrounding quotes)
_yc_json_escape() {
  printf "%s" "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e 's/\r/\\r/g' \
    -e 's/\n/\\n/g' \
    -e 's/\t/\\t/g'
}

# returns:
#  _sub_domain="_acme-challenge.www"  (relative to zone)
#  _domain="example.com"             (zone, no trailing dot)
#  _domain_id="<id>"
_get_root() {
  domain_fqdn="$(_yc_fqdn "$1")"
  domain_nd="$(_yc_nodot "$1")"

  # 1) If Zone ID provided: validate zone and compute subdomain via suffix match
  if [ "${YC_Zone_ID:-}" ]; then
    if ! _yc_rest GET "zones/$YC_Zone_ID"; then
      return 1
    fi

    zone_raw="$(printf "%s" "$response" | _normalizeJson | _egrep_o "\"zone\":\"[^\"]*\"" | cut -d : -f 2 | tr -d '"')"
    zone_nd="$(printf "%s" "$zone_raw" | _lower_case)"
    # remove trailing dot if API returns it
    while _endswith "$zone_nd" "."; do zone_nd="${zone_nd%?}"; done

    if [ -z "$zone_nd" ]; then
      return 1
    fi

    case "$domain_nd" in
      *".${zone_nd}")
        sub="${domain_nd%.$zone_nd}"
        ;;
      "$zone_nd")
        sub="@"
        ;;
      *)
        _err "Domain '$domain_nd' does not match zone '$zone_nd' (YC_Zone_ID=$YC_Zone_ID)"
        return 1
        ;;
    esac

    _sub_domain="$sub"
    _domain="$zone_nd"
    _domain_id="$YC_Zone_ID"
    return 0
  fi

  # 2) Folder mode: list zones and find best suffix match
  if [ ! "${YC_Folder_ID:-}" ]; then
    _err "You didn't specify a Yandex Cloud Folder ID."
    return 1
  fi

  if ! _yc_rest GET "zones?folderId=$YC_Folder_ID"; then
    return 1
  fi

  json="$(_yc_zones_compact "$response")"
  # Iterate suffixes from most specific to least specific
  # e.g. a.b.c.example.com -> try a.b.c.example.com, b.c.example.com, c.example.com, example.com, com
  rest="$domain_nd"
  while :; do
    zid="$(_yc_find_zone_id "$json" "$rest")"
    if [ -n "$zid" ]; then
      _domain="$rest"
      _domain_id="$zid"
      if [ "$domain_nd" = "$rest" ]; then
        _sub_domain="@"
      else
        _sub_domain="${domain_nd%.$rest}"
      fi
      return 0
    fi

    # strip leftmost label
    case "$rest" in
      *.*) rest="${rest#*.}" ;;
      *) break ;;
    esac
  done

  return 1
}

# compact json for easier grep
_yc_zones_compact() {
  printf "%s" "$1" | _normalizeJson
}

# Find zone id by exact zone name (no trailing dot) in compact json list
_yc_find_zone_id() {
  _json="$1"
  _zone="$2"
  # Match: ..."zone":"<zone>",..."id":"<id>"...
  printf "%s" "$_json" \
    | _egrep_o "\\{[^\\}]*\"zone\":\"$(_yc_re_escape "$_zone")\"[^\\}]*\\}" \
    | _egrep_o "\"id\":\"[^\"]*\"" \
    | cut -d : -f 2 \
    | tr -d '" ' \
    | _head_n 1
}

# Escape for ERE/grep pattern
_yc_re_escape() {
  printf "%s" "$1" | sed -e 's/[][(){}.^$*+?|\\]/\\&/g'
}

# Extract TXT recordset "data" array from YC getRecordSet response
# Returns JSON array like ["v1","v2"] or empty string if not found
_yc_extract_txt_data_array() {
  printf "%s" "$response" \
    | _normalizeJson \
    | _egrep_o "\"data\":\\[[^\\]]*\\]" \
    | _egrep_o "\\[[^\\]]*\\]" \
    | _head_n 1
}

# Add one txt value to JSON array if not present
# Args: json_array txtvalue
# Prints: new json array
_yc_data_array_add_one() {
  _arr="$1"
  _val="$2"

  _val_esc="$(_yc_json_escape "$_val")"

  if [ -z "$_arr" ]; then
    printf "[\"%s\"]" "$_val_esc"
    return 0
  fi

  # already present?
  if printf "%s" "$_arr" | _contains "\"$_val_esc\""; then
    printf "%s" "$_arr"
    return 0
  fi

  # append
  case "$_arr" in
    "[]") printf "[\"%s\"]" "$_val_esc" ;;
    *) printf "%s" "$_arr" | sed "s/\\]$/,\"$_val_esc\"]/";;
  esac
}

# Remove one txt value from JSON array
# Args: json_array txtvalue
# Prints: new json array (possibly "[]")
_yc_data_array_rm_one() {
  _arr="$1"
  _val="$2"

  [ -z "$_arr" ] && { printf "[]"; return 0; }

  _val_esc="$(_yc_json_escape "$_val")"

  # remove exact JSON string element occurrences
  _new=$(printf "%s" "$_arr" | sed \
    -e "s/\"$_val_esc\",//g" \
    -e "s/,\"$_val_esc\"//g" \
    -e "s/\"$_val_esc\"//g" \
    -e 's/\[,/[/' \
    -e 's/,\]/]/' \
    -e 's/,,/,/g')

  # normalize empty leftovers
  _new=$(printf "%s" "$_new" | sed -e 's/\[ *\]/[]/g')

  if [ "$_new" = "[]" ] || [ "$_new" = "[" ] || [ "$_new" = "]" ] || [ "$_new" = "[,]" ]; then
    printf "[]"
    return 0
  fi

  # also normalize "[,x]" / "[x,]"
  _new=$(printf "%s" "$_new" | sed -e 's/\[,/[/' -e 's/,\]/]/')

  printf "%s" "$_new"
}

_yc_validate_creds() {
  if [ ! "${YC_SA_ID:-}" ] || [ ! "${YC_SA_Key_ID:-}" ] || [ ! "${YC_SA_Key_File:-}" ]; then
    _err "You didn't specify a YC_SA_ID or YC_SA_Key_ID or YC_SA_Key_File."
    return 1
  fi

  if [ ! -f "$YC_SA_Key_File" ]; then
    _err "YC_SA_Key_File not found in path $YC_SA_Key_File."
    return 1
  fi

  if ! _isRSA "$YC_SA_Key_File" >/dev/null 2>&1; then
    _err "YC_SA_Key_File not a RSA file(_isRSA function return false)."
    return 1
  fi

  if [ ! "${YC_Zone_ID:-}" ] && [ ! "${YC_Folder_ID:-}" ]; then
    _err "You didn't specify a Yandex Cloud Zone ID or Folder ID yet."
    return 1
  fi

  return 0
}

# Prepare YC_SA_Key_File from either PEM_b64 (tmp) or File_Path (persistent)
_yc_prepare_key_file() {
  YC_SA_Key_File_PEM_b64="${YC_SA_Key_File_PEM_b64:-$(_readaccountconf_mutable YC_SA_Key_File_PEM_b64)}"
  YC_SA_Key_File_Path="${YC_SA_Key_File_Path:-$(_readaccountconf_mutable YC_SA_Key_File_Path)}"

  _yc_tmp_key_file=""

  if [ "${YC_SA_Key_File_PEM_b64:-}" ]; then
    _yc_tmp_key_file="$(mktemp "${TMPDIR:-/tmp}/acme-yc-key.XXXXXX")"
    chmod 600 "$_yc_tmp_key_file"
    printf "%s" "$YC_SA_Key_File_PEM_b64" | _dbase64 >"$_yc_tmp_key_file"
    YC_SA_Key_File="$_yc_tmp_key_file"
  else
    YC_SA_Key_File="$YC_SA_Key_File_Path"
  fi
}

_yc_cleanup_key_file() {
  if [ "${_yc_tmp_key_file:-}" ] && [ -f "${_yc_tmp_key_file}" ]; then
    rm -f "${_yc_tmp_key_file}"
  fi
}

_yc_rest() {
  m="$1"
  ep="$2"
  data="${3-}"
  _debug "$ep"

  if [ ! "${YC_Token:-}" ]; then
    _debug "Login"
    _yc_login
  else
    _debug "Token already exists. Skip Login."
  fi

  token_trimmed="$(printf "%s" "$YC_Token" | tr -d '"')"

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $token_trimmed"

  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$YC_Api/$ep" "" "$m")"
  else
    response="$(_get "$YC_Api/$ep")"
  fi

  if [ "$?" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}

_yc_login() {
  header="$(printf "%s" "{\"typ\":\"JWT\",\"alg\":\"PS256\",\"kid\":\"$YC_SA_Key_ID\"}" | _normalizeJson | _base64 | _url_replace)"
  _debug header "$header"

  _current_timestamp="$(_time)"
  _expire_timestamp="$(_math "$_current_timestamp" + 1200)" # 20 minutes
  payload="$(printf "%s" "{\"iss\":\"$YC_SA_ID\",\"aud\":\"https://iam.api.cloud.yandex.net/iam/v1/tokens\",\"iat\":$_current_timestamp,\"exp\":$_expire_timestamp}" | _normalizeJson | _base64 | _url_replace)"
  _debug payload "$payload"

  _signature="$(printf "%s.%s" "$header" "$payload" | _sign "$YC_SA_Key_File" "sha256 -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1" | _url_replace)"
  _debug2 _signature "$_signature"

  _jwt="$(printf "{\"jwt\": \"%s.%s.%s\"}" "$header" "$payload" "$_signature")"
  _debug2 _jwt "$_jwt"

  export _H1="Content-Type: application/json"
  _iam_response="$(_post "$_jwt" "https://iam.api.cloud.yandex.net/iam/v1/tokens" "" "POST")"
  _debug3 _iam_response "$(printf "%s" "$_iam_response" | _normalizeJson)"

  YC_Token="$(printf "%s" "$_iam_response" | _normalizeJson | _egrep_o "\"iamToken\"[^,]*" | _egrep_o "[^:]*$" | tr -d '"')"
  _debug3 YC_Token "$YC_Token"

  return 0
}
