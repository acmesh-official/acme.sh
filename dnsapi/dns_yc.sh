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

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_yc_add() {
  fulldomain="$(echo "$1". | _lower_case)" # Add dot at end of domain name
  txtvalue=$2

  YC_SA_Key_File_PEM_b64="${YC_SA_Key_File_PEM_b64:-$(_readaccountconf_mutable YC_SA_Key_File_PEM_b64)}"
  YC_SA_Key_File_Path="${YC_SA_Key_File_Path:-$(_readaccountconf_mutable YC_SA_Key_File_Path)}"

  if [ "$YC_SA_Key_File_PEM_b64" ]; then
    echo "$YC_SA_Key_File_PEM_b64" | _dbase64 >private.key
    YC_SA_Key_File="private.key"
    _savedomainconf YC_SA_Key_File_PEM_b64 "$YC_SA_Key_File_PEM_b64"
  else
    YC_SA_Key_File="$YC_SA_Key_File_Path"
    _savedomainconf YC_SA_Key_File_Path "$YC_SA_Key_File_Path"
  fi

  YC_Zone_ID="${YC_Zone_ID:-$(_readaccountconf_mutable YC_Zone_ID)}"
  YC_Folder_ID="${YC_Folder_ID:-$(_readaccountconf_mutable YC_Folder_ID)}"
  YC_SA_ID="${YC_SA_ID:-$(_readaccountconf_mutable YC_SA_ID)}"
  YC_SA_Key_ID="${YC_SA_Key_ID:-$(_readaccountconf_mutable YC_SA_Key_ID)}"

  if [ "$YC_SA_ID" ] && [ "$YC_SA_Key_ID" ] && [ "$YC_SA_Key_File" ]; then
    if [ -f "$YC_SA_Key_File" ]; then
      if _isRSA "$YC_SA_Key_File" >/dev/null 2>&1; then
        if [ "$YC_Zone_ID" ]; then
          _savedomainconf YC_Zone_ID "$YC_Zone_ID"
          _savedomainconf YC_SA_ID "$YC_SA_ID"
          _savedomainconf YC_SA_Key_ID "$YC_SA_Key_ID"
        elif [ "$YC_Folder_ID" ]; then
          _savedomainconf YC_Folder_ID "$YC_Folder_ID"
          _saveaccountconf_mutable YC_SA_ID "$YC_SA_ID"
          _saveaccountconf_mutable YC_SA_Key_ID "$YC_SA_Key_ID"
          _clearaccountconf_mutable YC_Zone_ID
          _clearaccountconf YC_Zone_ID
        else
          _err "You didn't specify a Yandex Cloud Zone ID or Folder ID yet."
          return 1
        fi
      else
        _err "YC_SA_Key_File not a RSA file(_isRSA function return false)."
        return 1
      fi
    else
      _err "YC_SA_Key_File not found in path $YC_SA_Key_File."
      return 1
    fi
  else
    _clearaccountconf YC_Zone_ID
    _clearaccountconf YC_Folder_ID
    _clearaccountconf YC_SA_ID
    _clearaccountconf YC_SA_Key_ID
    _clearaccountconf YC_SA_Key_File_PEM_b64
    _clearaccountconf YC_SA_Key_File_Path
    _err "You didn't specify a YC_SA_ID or YC_SA_Key_ID or YC_SA_Key_File."
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

  _info "Adding record"
  if _yc_rest POST "zones/$_domain_id:upsertRecordSets" "{\"merges\": [ { \"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":\"120\",\"data\":[\"$txtvalue\"]}]}"; then
    if _contains "$response" "\"done\": true"; then
      _info "Added, OK"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1

}

#fulldomain txtvalue
dns_yc_rm() {
  fulldomain="$(echo "$1". | _lower_case)" # Add dot at end of domain name
  txtvalue=$2

  YC_Zone_ID="${YC_Zone_ID:-$(_readaccountconf_mutable YC_Zone_ID)}"
  YC_Folder_ID="${YC_Folder_ID:-$(_readaccountconf_mutable YC_Folder_ID)}"
  YC_SA_ID="${YC_SA_ID:-$(_readaccountconf_mutable YC_SA_ID)}"
  YC_SA_Key_ID="${YC_SA_Key_ID:-$(_readaccountconf_mutable YC_SA_Key_ID)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _debug "Getting txt records"
  if _yc_rest GET "zones/${_domain_id}:getRecordSet?type=TXT&name=$_sub_domain"; then
    exists_txtvalue=$(echo "$response" | _normalizeJson | _egrep_o "\"data\".*\][^,]*" | _egrep_o "[^:]*$")
    _debug exists_txtvalue "$exists_txtvalue"
  else
    _err "Error: $response"
    return 1
  fi

  if _yc_rest POST "zones/$_domain_id:updateRecordSets" "{\"deletions\": [ { \"name\":\"$_sub_domain\",\"type\":\"TXT\",\"ttl\":\"120\",\"data\":$exists_txtvalue}]}"; then
    if _contains "$response" "\"done\": true"; then
      _info "Delete, OK"
      return 0
    else
      _err "Delete record error."
      return 1
    fi
  fi
  _err "Delete record error."
  return 1
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=1
  p=1

  # Use Zone ID directly if provided
  if [ "$YC_Zone_ID" ]; then
    if ! _yc_rest GET "zones/$YC_Zone_ID"; then
      return 1
    else
      if echo "$response" | tr -d " " | _egrep_o "\"id\":\"$YC_Zone_ID\"" >/dev/null; then
        _domain=$(echo "$response" | _egrep_o "\"zone\": *\"[^\"]*\"" | cut -d : -f 2 | tr -d \" | _head_n 1 | tr -d " ")
        if [ "$_domain" ]; then
          _cutlength=$((${#domain} - ${#_domain}))
          _sub_domain=$(printf "%s" "$domain" | cut -c "1-$_cutlength")
          _domain_id=$YC_Zone_ID
          return 0
        else
          return 1
        fi
      else
        return 1
      fi
    fi
  fi

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi
    if [ "$YC_Folder_ID" ]; then
      if ! _yc_rest GET "zones?folderId=$YC_Folder_ID"; then
        return 1
      fi
    else
      echo "You didn't specify a Yandex Cloud Folder ID."
      return 1
    fi
    if _contains "$response" "\"zone\": \"$h\""; then
      _domain_id=$(echo "$response" | _normalizeJson | _egrep_o "[^{]*\"zone\":\"$h\"[^}]*" | _egrep_o "\"id\"[^,]*" | _egrep_o "[^:]*$" | tr -d '"')
      _debug _domain_id "$_domain_id"
      if [ "$_domain_id" ]; then
        _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_yc_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  if [ ! "$YC_Token" ]; then
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

  #signature=$(printf "%s.%s" "$header" "$payload" | ${ACME_OPENSSL_BIN:-openssl} dgst -sign "$YC_SA_Key_File -sha256 -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1" | _base64 | _url_replace )
  _signature=$(printf "%s.%s" "$header" "$payload" | _sign "$YC_SA_Key_File" "sha256 -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-1" | _url_replace)
  _debug2 _signature "$_signature"

  rm -rf "$YC_SA_Key_File"

  _jwt=$(printf "{\"jwt\": \"%s.%s.%s\"}" "$header" "$payload" "$_signature")
  _debug2 _jwt "$_jwt"

  export _H1="Content-Type: application/json"
  _iam_response="$(_post "$_jwt" "https://iam.api.cloud.yandex.net/iam/v1/tokens" "" "POST")"
  _debug3 _iam_response "$(echo "$_iam_response" | _normalizeJson)"

  YC_Token="$(echo "$_iam_response" | _normalizeJson | _egrep_o "\"iamToken\"[^,]*" | _egrep_o "[^:]*$" | tr -d '"')"
  _debug3 YC_Token

  return 0
}
