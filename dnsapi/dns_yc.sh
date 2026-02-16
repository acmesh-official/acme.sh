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

  newdata="$(_yc_array_add "$existing" "$txtvalue")"

  _info "Adding TXT record"
  _yc_rest POST "zones/${_domain_id}:upsertRecordSets" \
    "{\"merges\":[{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":\"60\",\"data\":$newdata}]}" \
    || return 1

  _contains "$response" "\"done\": true" || return 1

  return 0
}

########################
# rm
########################

dns_yc_rm() {
  fulldomain="$(echo "$1" | _lower_case)"
  txtvalue="$2"

  _yc_init || return 1

  _get_root "$fulldomain" || return 1

  _yc_rest GET "zones/${_domain_id}:getRecordSet?type=TXT&name=$_sub_domain" || return 1

  existing="$(_yc_extract_data_array)"

  [ -z "$existing" ] && return 0

  newdata="$(_yc_array_remove "$existing" "$txtvalue")"

  if [ "$newdata" = "$existing" ]; then
    return 0
  fi

  if [ "$newdata" = "[]" ]; then
    _yc_rest POST "zones/${_domain_id}:updateRecordSets" \
      "{\"deletions\":[{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":\"60\",\"data\":$existing}]}" \
      || return 1
  else
    _yc_rest POST "zones/${_domain_id}:upsertRecordSets" \
      "{\"merges\":[{\"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":\"60\",\"data\":$newdata}]}" \
      || return 1
  fi

  _contains "$response" "\"done\": true" || return 1

  return 0
}

########################
# internal helpers
########################

_yc_init() {

  YC_SA_ID="${YC_SA_ID:-$(_readaccountconf_mutable YC_SA_ID)}"
  YC_SA_Key_ID="${YC_SA_Key_ID:-$(_readaccountconf_mutable YC_SA_Key_ID)}"
  YC_Zone_ID="${YC_Zone_ID:-$(_readaccountconf_mutable YC_Zone_ID)}"
  YC_Folder_ID="${YC_Folder_ID:-$(_readaccountconf_mutable YC_Folder_ID)}"
  YC_SA_Key_File_Path="${YC_SA_Key_File_Path:-$(_readaccountconf_mutable YC_SA_Key_File_Path)}"
  YC_SA_Key_File_PEM_b64="${YC_SA_Key_File_PEM_b64:-$(_readaccountconf_mutable YC_SA_Key_File_PEM_b64)}"

  [ -z "$YC_SA_ID" ] && return 1
  [ -z "$YC_SA_Key_ID" ] && return 1

  if [ "$YC_SA_Key_File_PEM_b64" ]; then
    tmpkey="$(_mktemp)"
    echo "$YC_SA_Key_File_PEM_b64" | _dbase64 > "$tmpkey"
    chmod 600 "$tmpkey"
    YC_SA_Key_File="$tmpkey"
  else
    YC_SA_Key_File="$YC_SA_Key_File_Path"
  fi

  [ ! -f "$YC_SA_Key_File" ] && return 1

  return 0
}

_yc_extract_data_array() {
  echo "$response" | _normalizeJson | _egrep_o "\"data\":\\[[^\\]]*\\]" | _egrep_o "\\[[^\\]]*\\]"
}

_yc_array_add() {
  arr="$1"
  val="$2"

  [ -z "$arr" ] && { printf "[\"%s\"]" "$val"; return; }

  if printf "%s" "$arr" | _contains "\"$val\""; then
    printf "%s" "$arr"
    return
  fi

  printf "%s" "$arr" | sed "s/]$/,\"$val\"]/"

}

_yc_array_remove() {
  arr="$1"
  val="$2"

  printf "%s" "$arr" | sed \
    -e "s/\"$val\",//g" \
    -e "s/,\"$val\"//g" \
    -e "s/\"$val\"//g" \
    -e 's/\[,/[/' \
    -e 's/,\]/]/' \
    -e 's/,,/,/g'
}

