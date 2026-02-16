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
Issues: https://github.com/acmesh-official/acme.sh/issues
'

YC_Api="https://dns.api.cloud.yandex.net/dns/v1"

##############################################
# Public functions
##############################################

dns_yc_add() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue="$2"

  _yc_init || return 1
  _yc_prepare_key || return 1

  _debug "Detect root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  _debug "Adding TXT"
  if _yc_rest POST "zones/$_domain_id:upsertRecordSets" \
    "{\"merges\": [ { \"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":\"120\",\"data\":[\"$txtvalue\"]}]}"; then

    if _contains "$response" "\"done\": true"; then
      _info "Added TXT OK"
      return 0
    fi
  fi

  _err "Add TXT failed"
  return 1
}

dns_yc_rm() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue="$2"

  _yc_init || return 1
  _yc_prepare_key || return 1

  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi

  if ! _yc_rest GET "zones/${_domain_id}:getRecordSet?type=TXT&name=$_sub_domain"; then
    return 1
  fi

  _data="$(echo "$response" | _normalizeJson | _egrep_o "\"data\":\[[^]]*\]" | _egrep_o "\[[^]]*\]")"

  [ -z "$_data" ] && return 0

  _new="$(printf "%s" "$_data" | sed \
    -e "s/\"$txtvalue\",//g" \
    -e "s/,\"$txtvalue\"//g" \
    -e "s/\"$txtvalue\"//g" \
    -e 's/\[,/[/' \
    -e 's/,\]/]/' \
    -e 's/,,/,/g')"

  if [ "$_new" = "[]" ]; then
    _yc_rest POST "zones/$_domain_id:updateRecordSets" \
      "{\"deletions\": [ { \"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":\"120\",\"data\":$_data} ]}"
  else
    _yc_rest POST "zones/$_domain_id:upsertRecordSets" \
      "{\"merges\": [ { \"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":\"120\",\"data\":$_new} ]}"
  fi

  return 0
}

##############################################
# Internal helpers
##############################################

_yc_init() {
  YC_SA_ID="${YC_SA_ID:-$(_readaccountconf_mutable YC_SA_ID)}"
  YC_SA_Key_ID="${YC_SA_Key_ID:-$(_readaccountconf_mutable YC_SA_Key_ID)}"
  YC_SA_Key_File_Path="${YC_SA_Key_File_Path:-$(_readaccountconf_mutable YC_SA_Key_File_Path)}"
  YC_SA_Key_File_PEM_b64="${YC_SA_Key_File_PEM_b64:-$(_readaccountconf_mutable YC_SA_Key_File_PEM_b64)}"
  YC_Zone_ID="${YC_Zone_ID:-$(_readaccountconf_mutable YC_Zone_ID)}"
  YC_Folder_ID="${YC_Folder_ID:-$(_readaccountconf_mutable YC_Folder_ID)}"

  if [ -z "$YC_SA_ID" ] || [ -z "$YC_SA_Key_ID" ]; then
    _err "Missing YC_SA_ID or YC_SA_Key_ID"
    return 1
  fi

  _saveaccountconf_mutable YC_SA_ID "$YC_SA_ID"
  _saveaccountconf_mutable YC_SA_Key_ID "$YC_SA_Key_ID"

  return 0
}

_yc_prepare_key() {
  if [ "$YC_SA_Key_File_PEM_b64" ]; then
    _tmpkey="$(_mktemp)"
    echo "$YC_SA_Key_File_PEM_b64" | _dbase64 >"$_tmpkey"
    YC_SA_Key_File="$_tmpkey"
  else
    YC_SA_Key_File="$YC_SA_Key_File_Path"
  fi

  if [ ! -f "$YC_SA_Key_File" ]; then
    _err "Key file not found"
    return 1
  fi

  return 0
}

_get_root() {
  domain=$1

  if [ "$YC_Zone_ID" ]; then
    _domain_id="$YC_Zone_ID"
    _sub_domain="$domain"
    return 0
  fi

  if [ -z "$YC_Folder_ID" ]; then
    _err "Need YC_Zone_ID or YC_Folder_ID"
    return 1
  fi

  _yc_rest GET "zones?folderId=$YC_Folder_ID" || return 1

  for zone in $(echo "$response" | _egrep_o "\"zone\":\"[^\"]*\"" | cut -d '"' -f4); do
    if _endswith "$domain" "$zone"; then
      _domain_id=$(echo "$response" | _normalizeJson | _egrep_o "[^{]*\"zone\":\"$zone\"[^}]*" | _egrep_o "\"id\"[^,]*" | cut -d '"' -f4)
      _sub_domain="${domain%.$zone}"
      return 0
    fi
  done

  return 1
}

_yc_rest() {
  m="$1"
  ep="$2"
  data="$3"

  if [ -z "$YC_Token" ]; then
    _yc_login || return 1
  fi

  export _H1="Content-Type: application/json"
  export _H2="Authorization: Bearer $YC_Token"

  if [ "$m" = "GET" ]; then
    response="$(_get "$YC_Api/$ep")"
  else
    response="$(_post "$data" "$YC_Api/$ep" "" "$m")"
  fi

  return $?
}

_yc_login() {
  header=$(printf '{"typ":"JWT","alg":"PS256","kid":"%s"}' "$YC_SA_Key_ID" | _base64 | _url_replace)

  now=$(_time)
  exp=$(_math "$now" + 600)

  payload=$(printf '{"iss":"%s","aud":"https://iam.api.cloud.yandex.net/iam/v1/tokens","iat":%s,"exp":%s}' \
    "$YC_SA_ID" "$now" "$exp" | _base64 | _url_replace)

  signature=$(printf "%s.%s" "$header" "$payload" | \
    _sign "$YC_SA_Key_File" "sha256 -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1" | \
    _url_replace)

  jwt=$(printf '{"jwt":"%s.%s.%s"}' "$header" "$payload" "$signature")

  _iam="$(_post "$jwt" "https://iam.api.cloud.yandex.net/iam/v1/tokens")"

  YC_Token=$(echo "$_iam" | _normalizeJson | _egrep_o "\"iamToken\"[^,]*" | cut -d '"' -f4)

  [ -z "$YC_Token" ] && return 1
  return 0
}
