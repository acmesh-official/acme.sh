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
 YC_SA_Key_File_PEM_b64 Base64 content of private key file. Optional.
Issues: github.com/acmesh-official/acme.sh/issues/4210
'

YC_Api="https://dns.api.cloud.yandex.net/dns/v1"

########################
# add
########################

dns_yc_add() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue="$2"

  _yc_init || return 1

  _debug "Detect root zone"
  _get_root "$fulldomain" || return 1

  _debug "Fetching existing TXT"
  _yc_rest GET "zones/${_domain_id}:getRecordSet?type=TXT&name=$_sub_domain" || return 1

  existing="$(_yc_extract_data_array)"

#!/usr/bin/env sh
# shellcheck disable=SC2034

dns_yc_info='Yandex Cloud DNS
Site: Cloud.Yandex.com
Docs: https://github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_yc
Options:
 YC_Zone_ID DNS Zone ID
 YC_Folder_ID YC Folder ID
 YC_SA_ID Service Account ID
 YC_SA_Key_ID Service Account IAM Key ID
 YC_SA_Key_File_Path Private key file path
 YC_SA_Key_File_PEM_b64 Base64 content of private key file
'

YC_Api="https://dns.api.cloud.yandex.net/dns/v1"

############################
# Public functions
############################

dns_yc_add() {
  fulldomain="$(echo "$1." | _lower_case)"
  txtvalue="$2"

  _yc_load_credentials || return 1

  _debug "Detect root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug "_domain_id=$_domain_id"
  _debug "_sub_domain=$_sub_domain"

  # Try get existing recordset (may not exist!)
  _yc_rest GET "zones/${_domain_id}:getRecordSet?type=TXT&name=$_sub_domain" || true

  _existing="$(_yc_extract_txt_data_array)"

  if [ -z "$_existing" ]; then
    _new="[\"$txtvalue\"]"
  else
    if _contains "$_existing" "\"$txtvalue\""; then
      _info "TXT already exists."
      return 0
    fi
    _new=$(printf "%s" "$_existing" | sed "s/]$/,\"$txtvalue\"]/")
  fi

  _info "Adding TXT record"
  if _yc_rest POST "zones/$_domain_id:upsertRecordSets" \
    "{\"merges\": [{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":\"120\",\"data\":$_new}]}"; then
      if _contains "$response" "\"done\": true"; then
        _info "Added"
        return 0
      fi
  fi

  _err "Add failed"
  return 1
}

dns_yc_rm() {
  fulldomain="$(echo "$1." | _lower_case)"
  txtvalue="$2"

  _yc_load_credentials || return 1

  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _yc_rest GET "zones/${_domain_id}:getRecordSet?type=TXT&name=$_sub_domain" || return 0

  _existing="$(_yc_extract_txt_data_array)"
  [ -z "$_existing" ] && return 0

  if ! _contains "$_existing" "\"$txtvalue\""; then
    _info "TXT not present, skip"
    return 0
  fi

  _new=$(printf "%s" "$_existing" | sed \
      -e "s/\"$txtvalue\",//" \
      -e "s/,\"$txtvalue\"//" \
      -e "s/\"$txtvalue\"//" \
      -e 's/\[,/[/' \
      -e 's/,\]/]/')

  if [ "$_new" = "[]" ] || [ -z "$_new" ]; then
    _info "Deleting full recordset"
    if _yc_rest POST "zones/$_domain_id:updateRecordSets" \
      "{\"deletions\": [{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":\"120\",\"data\":$_existing}]}"; then
        return 0
    fi
  else
    _info "Updating recordset"
    if _yc_rest POST "zones/$_domain_id:upsertRecordSets" \
      "{\"merges\": [{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":\"120\",\"data\":$_new}]}"; then
        return 0
    fi
  fi

  _err "Delete failed"
  return 1
}

############################
# Helpers
############################

_yc_load_credentials() {
  YC_SA_ID="${YC_SA_ID:-$(_readaccountconf_mutable YC_SA_ID)}"
  YC_SA_Key_ID="${YC_SA_Key_ID:-$(_readaccountconf_mutable YC_SA_Key_ID)}"
  YC_SA_Key_File_Path="${YC_SA_Key_File_Path:-$(_readaccountconf_mutable YC_SA_Key_File_Path)}"
  YC_SA_Key_File_PEM_b64="${YC_SA_Key_File_PEM_b64:-$(_readaccountconf_mutable YC_SA_Key_File_PEM_b64)}"
  YC_Zone_ID="${YC_Zone_ID:-$(_readaccountconf_mutable YC_Zone_ID)}"
  YC_Folder_ID="${YC_Folder_ID:-$(_readaccountconf_mutable YC_Folder_ID)}"

  [ -z "$YC_SA_ID" ] && return 1
  [ -z "$YC_SA_Key_ID" ] && return 1

  if [ "$YC_SA_Key_File_PEM_b64" ]; then
    YC_SA_Key_File="$(_mktemp)"
    echo "$YC_SA_Key_File_PEM_b64" | _dbase64 > "$YC_SA_Key_File"
  else
    YC_SA_Key_File="$YC_SA_Key_File_Path"
  fi

  [ -f "$YC_SA_Key_File" ] || return 1

  _saveaccountconf_mutable YC_SA_ID "$YC_SA_ID"
  _saveaccountconf_mutable YC_SA_Key_ID "$YC_SA_Key_ID"

  return 0
}

_yc_extract_txt_data_array() {
  echo "$response" | _normalizeJson | _egrep_o "\"data\":\[[^]]*\]" | _egrep_o "\[[^]]*\]"
}

_yc_rest() {
  m="$1"
  ep="$2"
  data="$3"

  if [ ! "$YC_Token" ]; then
    _yc_login || return 1
  fi

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $YC_Token"

  if [ "$m" = "GET" ]; then
    response="$(_get "$YC_Api/$ep")"
  else
    response="$(_post "$data" "$YC_Api/$ep" "" "$m")"
  fi

  return 0
}

_yc_login() {
  header=$(printf '{"typ":"JWT","alg":"PS256","kid":"%s"}' "$YC_SA_Key_ID" | _normalizeJson | _base64 | _url_replace)
  now=$(_time)
  exp=$(_math "$now" + 1200)
  payload=$(printf '{"iss":"%s","aud":"https://iam.api.cloud.yandex.net/iam/v1/tokens","iat":%s,"exp":%s}' "$YC_SA_ID" "$now" "$exp" | _normalizeJson | _base64 | _url_replace)
  sig=$(printf "%s.%s" "$header" "$payload" | _sign "$YC_SA_Key_File" "sha256 -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1" | _url_replace)
  jwt=$(printf '{"jwt":"%s.%s.%s"}' "$header" "$payload" "$sig")

  iam="$(_post "$jwt" "https://iam.api.cloud.yandex.net/iam/v1/tokens" "" "POST")"
  YC_Token="$(echo "$iam" | _normalizeJson | _egrep_o "\"iamToken\"[^,]*" | _egrep_o "[^:]*$" | tr -d '"')"

  [ -n "$YC_Token" ] || return 1
  return 0
}
