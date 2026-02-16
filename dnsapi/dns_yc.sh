#!/usr/bin/env sh
# shellcheck disable=SC2034

dns_yc_info='Yandex Cloud DNS
Site: Cloud.Yandex.com
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_yc
Options:
 YC_Zone_ID DNS Zone ID
 YC_Folder_ID YC_Folder_ID
 YC_SA_ID Service Account ID
 YC_SA_Key_ID Service Account IAM Key ID
 YC_SA_Key_File_Path Private key file path. Optional.
 YC_SA_Key_File_PEM_b64 Base64 content of private key file. Use instead of Path to private key file. Optional.
Issues: github.com/acmesh-official/acme.sh/issues/4210
'

YC_Api="https://dns.api.cloud.yandex.net/dns/v1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "txtvalue"
dns_yc_add() {
  fulldomain="$(echo "$1" | _lower_case)"
  fulldomain="$(_yc_fqdn "$fulldomain")"
  txtvalue=$2

  _yc_prepare_key_file
  trap _yc_cleanup_key_file 0

  YC_Zone_ID="${YC_Zone_ID:-$(_readaccountconf_mutable YC_Zone_ID)}"
  YC_Folder_ID="${YC_Folder_ID:-$(_readaccountconf_mutable YC_Folder_ID)}"
  YC_SA_ID="${YC_SA_ID:-$(_readaccountconf_mutable YC_SA_ID)}"
  YC_SA_Key_ID="${YC_SA_Key_ID:-$(_readaccountconf_mutable YC_SA_Key_ID)}"

  if ! _yc_validate_creds; then
    return 1
  fi

  # Save per-domain or per-account settings
  if [ "$YC_Zone_ID" ]; then
    _savedomainconf YC_Zone_ID "$YC_Zone_ID"
  elif [ "$YC_Folder_ID" ]; then
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

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  if ! _yc_rest GET "zones/${_domain_id}:getRecordSet?type=TXT&name=$_sub_domain"; then
    _err "Error: $response"
    return 1
  fi

  _info "Adding record"
  if _yc_rest POST "zones/$_domain_id:upsertRecordSets" \
    "{\"merges\": [ { \"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":120,\"data\":[\"$txtvalue\"]}]}"; then
    if _contains "$response" "\"done\": true"; then
      _info "Added, OK"
      return 0
    fi
  fi

  _err "Add txt record error."
  return 1
}

#fulldomain txtvalue
dns_yc_rm() {
  fulldomain="$(echo "$1" | _lower_case)"
  fulldomain="$(_yc_fqdn "$fulldomain")"
  txtvalue=$2

  _yc_prepare_key_file
  trap _yc_cleanup_key_file 0

  YC_Zone_ID="${YC_Zone_ID:-$(_readaccountconf_mutable YC_Zone_ID)}"
  YC_Folder_ID="${YC_Folder_ID:-$(_readaccountconf_mutable YC_Folder_ID)}"
  YC_SA_ID="${YC_SA_ID:-$(_readaccountconf_mutable YC_SA_ID)}"
  YC_SA_Key_ID="${YC_SA_Key_ID:-$(_readaccountconf_mutable YC_SA_Key_ID)}"

  if ! _yc_validate_creds; then
    return 1
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  if ! _yc_rest GET "zones/${_domain_id}:getRecordSet?type=TXT&name=$_sub_domain"; then
    _err "Error: $response"
    return 1
  fi

  _existing="$(_yc_extract_txt_data_array)"
  _debug existing_data "$_existing"

  # Nothing to delete
  if [ -z "$_existing" ]; then
    _info "No TXT recordset found, skip."
    return 0
  fi

  _newdata="$(_yc_data_array_rm_one "$_existing" "$txtvalue")"
  _debug new_data "$_newdata"

  # If value wasn't present, nothing to do
  if [ "$_newdata" = "$_existing" ]; then
    _info "TXT value not found, skip."
    return 0
  fi

  if [ "$_newdata" = "[]" ]; then
    # delete whole recordset (with previous data array)
    if _yc_rest POST "zones/$_domain_id:updateRecordSets" \
      "{\"deletions\": [ { \"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":120,\"data\":$_existing }]}"; then
      if _contains "$response" "\"done\": true"; then
        _info "Delete, OK"
        return 0
      fi
    fi
  else
    # keep remaining values
    if _yc_rest POST "zones/$_domain_id:upsertRecordSets" \
      "{\"merges\": [ { \"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":120,\"data\":$_newdata }]}"; then
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

# Ensure fqdn has trailing dot
_yc_fqdn() {
  _d="$1"
  [ -z "$_d" ] && { printf "%s" ""; return 0; }
  case "$_d" in
    *.) printf "%s" "$_d" ;;
    *)  printf "%s." "$_d" ;;
  esac
}

# Strip final dot (if any)
_yc_strip_dot() {
  _d="$1"
  printf "%s" "${_d%.}"
}

#returns
# _sub_domain=_acme-challenge  (relative to zone; or "@" for apex)
# _domain=domain.com.         (zone fqdn)
# _domain_id=<id>
_get_root() {
  domain="$1"
  domain="$(_yc_fqdn "$domain")"

  # Use Zone ID directly if provided
  if [ "$YC_Zone_ID" ]; then
    if ! _yc_rest GET "zones/$YC_Zone_ID"; then
      return 1
    fi

    # Extract zone fqdn from response
    _zone="$(echo "$response" | _normalizeJson | _egrep_o "\"zone\":\"[^\"]*\"" | cut -d : -f 2 | tr -d '"')"
    _zone="$(_yc_fqdn "$_zone")"

    if [ -z "$_zone" ]; then
      return 1
    fi

    _domain_id="$YC_Zone_ID"
    _domain="$_zone"

    # relative name inside zone
    _rel="${domain%"$_domain"}"
    _rel="${_rel%.}"
    if [ -z "$_rel" ]; then
      _sub_domain="@"
    else
      _sub_domain="$_rel"
    fi
    return 0
  fi

  # Folder mode: fetch zones once, then find best suffix match
  if [ ! "$YC_Folder_ID" ]; then
    _err "You didn't specify a Yandex Cloud Folder ID."
    return 1
  fi

  if ! _yc_rest GET "zones?folderId=$YC_Folder_ID"; then
    return 1
  fi
  _zones_json="$(_normalizeJson <<EOF
$response
EOF
)"

  # Work without trailing dot for splitting
  _d_nodot="$(_yc_strip_dot "$domain")"

  i=1
  while true; do
    h="$(printf "%s" "$_d_nodot" | cut -d . -f "$i"-100)"
    _debug h "$h"
    [ -z "$h" ] && return 1

    h_fqdn="$(_yc_fqdn "$h")"

    # YC обычно хранит zone с точкой на конце; но на всякий случай матчим оба варианта
    if _contains "$_zones_json" "\"zone\":\"$h_fqdn\"" || _contains "$_zones_json" "\"zone\":\"$h\""; then
      _domain_id="$(echo "$_zones_json" | _egrep_o "[^{]*\"zone\":\"$h_fqdn\"[^}]*" | _egrep_o "\"id\"[^,]*" | _egrep_o "[^:]*$" | tr -d '"')"
      if [ -z "$_domain_id" ]; then
        # fallback: zone without dot
        _domain_id="$(echo "$_zones_json" | _egrep_o "[^{]*\"zone\":\"$h\"[^}]*" | _egrep_o "\"id\"[^,]*" | _egrep_o "[^:]*$" | tr -d '"')"
      fi

      [ -z "$_domain_id" ] && return 1

      _domain="$h_fqdn"

      _rel="${domain%"$_domain"}"
      _rel="${_rel%.}"
      if [ -z "$_rel" ]; then
        _sub_domain="@"
      else
        _sub_domain="$_rel"
      fi
      return 0
    fi

    i=$(_math "$i" + 1)
  done
}

# Extract TXT recordset "data" array from YC response
# Returns JSON array like ["v1","v2"] or empty string if not found
_yc_extract_txt_data_array() {
  echo "$response" | _normalizeJson | _egrep_o "\"data\":\\[[^\\]]*\\]" | _egrep_o "\\[[^\\]]*\\]"
}

# Remove one txt value from JSON array
# Args: json_array txtvalue
# Prints: new json array (possibly "[]")
_yc_data_array_rm_one() {
  _arr="$1"
  _val="$2"

  [ -z "$_arr" ] && { printf "[]"; return 0; }

  # remove exact JSON string element occurrences
  _new=$(printf "%s" "$_arr" | sed \
    -e "s/\"$_val\",//g" \
    -e "s/,\"$_val\"//g" \
    -e "s/\"$_val\"//g" \
    -e 's/\[,/[/' \
    -e 's/,\]/]/' \
    -e 's/,,/,/g')

  # normalize empty leftovers
  _new=$(printf "%s" "$_new" | sed -e 's/\[ *\]/[]/g')

  # clean cases like "[" or "]" or "[,]"
  if [ "$_new" = "[]" ] || [ "$_new" = "[" ] || [ "$_new" = "]" ] || [ "$_new" = "[,]" ]; then
    printf "[]"
    return 0
  fi

  printf "%s" "$_new"
}

_yc_validate_creds() {
  if [ ! "$YC_SA_ID" ] || [ ! "$YC_SA_Key_ID" ] || [ ! "$YC_SA_Key_File" ]; then
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

  if [ ! "$YC_Zone_ID" ] && [ ! "$YC_Folder_ID" ]; then
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

  if [ "$YC_SA_Key_File_PEM_b64" ]; then
    _yc_tmp_key_file="$(mktemp "${TMPDIR:-/tmp}/acme-yc-key.XXXXXX")"
    chmod 600 "$_yc_tmp_key_file"
    echo "$YC_SA_Key_File_PEM_b64" | _dbase64 >"$_yc_tmp_key_file"
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
  m=$1
  ep="$2"
  data="${3-}"
  _debug "$ep"

  if [ ! "${YC_Token:-}" ]; then
    _debug "Login"
    _yc_login
  else
    _debug "Token already exists. Skip Login."
  fi

  token_trimmed=$(echo "$YC_Token" | tr -d '"')

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
  header=$(echo "{\"typ\":\"JWT\",\"alg\":\"PS256\",\"kid\":\"$YC_SA_Key_ID\"}" | _normalizeJson | _base64 | _url_replace)
  _debug header "$header"

  _current_timestamp=$(_time)
  _expire_timestamp=$(_math "$_current_timestamp" + 1200) # 20 minutes
  payload=$(echo "{\"iss\":\"$YC_SA_ID\",\"aud\":\"https://iam.api.cloud.yandex.net/iam/v1/tokens\",\"iat\":$_current_timestamp,\"exp\":$_expire_timestamp}" | _normalizeJson | _base64 | _url_replace)
  _debug payload "$payload"

  _signature=$(printf "%s.%s" "$header" "$payload" | _sign "$YC_SA_Key_File" "sha256 -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1" | _url_replace)
  _debug2 _signature "$_signature"

  _jwt=$(printf "{\"jwt\": \"%s.%s.%s\"}" "$header" "$payload" "$_signature")
  _debug2 _jwt "$_jwt"

  export _H1="Content-Type: application/json"
  _iam_response="$(_post "$_jwt" "https://iam.api.cloud.yandex.net/iam/v1/tokens" "" "POST")"
  _debug3 _iam_response "$(echo "$_iam_response" | _normalizeJson)"

  YC_Token="$(echo "$_iam_response" | _normalizeJson | _egrep_o "\"iamToken\"[^,]*" | _egrep_o "[^:]*$" | tr -d '"')"
  _debug3 YC_Token

  return 0
}
