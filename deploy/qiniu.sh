#!/usr/bin/env sh

# Script to create certificate to qiniu.com
#
# This deployment required following variables
# export QINIU_AK="QINIUACCESSKEY"
# export QINIU_SK="QINIUSECRETKEY"
# export QINIU_CDN_DOMAIN="cdn.example.com"
# If you have more than one domain, just
# export QINIU_CDN_DOMAIN="cdn1.example.com cdn2.example.com"

QINIU_API_BASE="https://api.qiniu.com"

qiniu_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  if [ -z "$QINIU_AK" ]; then
    _err "QINIU_AK is not defined."
    return 1
  else
    _savedomainconf QINIU_AK "$QINIU_AK"
  fi

  if [ -z "$QINIU_SK" ]; then
    _err "QINIU_SK is not defined."
    return 1
  else
    _savedomainconf QINIU_SK "$QINIU_SK"
  fi

  if [ "$QINIU_CDN_DOMAIN" ]; then
    _savedomainconf QINIU_CDN_DOMAIN "$QINIU_CDN_DOMAIN"
  else
    QINIU_CDN_DOMAIN="$_cdomain"
  fi

  ## upload certificate
  string_fullchain=$(sed 's/$/\\n/' "$_cfullchain" | tr -d '\n')
  string_key=$(sed 's/$/\\n/' "$_ckey" | tr -d '\n')

  sslcert_path="/sslcert"
  sslcerl_body="{\"name\":\"$_cdomain\",\"common_name\":\"$QINIU_CDN_DOMAIN\",\"ca\":\"$string_fullchain\",\"pri\":\"$string_key\"}"
  sslcert_access_token="$(_make_access_token "$sslcert_path")"
  _debug sslcert_access_token "$sslcert_access_token"
  export _H1="Authorization: QBox $sslcert_access_token"
  sslcert_response=$(_post "$sslcerl_body" "$QINIU_API_BASE$sslcert_path" 0 "POST" "application/json" | _dbase64 "multiline")

  if ! _contains "$sslcert_response" "certID"; then
    _err "Error in creating certificate:"
    _err "$sslcert_response"
    return 1
  fi

  _debug sslcert_response "$sslcert_response"
  _info "Certificate successfully uploaded, updating domain $_cdomain"

  ## extract certId
  _certId="$(printf "%s" "$sslcert_response" | _normalizeJson | _egrep_o "certID\": *\"[^\"]*\"" | cut -d : -f 2)"
  _debug certId "$_certId"

  ## update domain ssl config
  update_body="{\"certid\":$_certId,\"forceHttps\":false}"
  for domain in $QINIU_CDN_DOMAIN; do
    update_path="/domain/$domain/httpsconf"
    update_access_token="$(_make_access_token "$update_path")"
    _debug update_access_token "$update_access_token"
    export _H1="Authorization: QBox $update_access_token"
    update_response=$(_post "$update_body" "$QINIU_API_BASE$update_path" 0 "PUT" "application/json" | _dbase64 "multiline")

    if _contains "$update_response" "error"; then
      _err "Error in updating domain $domain httpsconf:"
      _err "$update_response"
      return 1
    fi

    _debug update_response "$update_response"
    _info "Domain $domain certificate has been deployed successfully"
  done

  return 0
}

_make_access_token() {
  _token="$(printf "%s\n" "$1" | _hmac "sha1" "$(printf "%s" "$QINIU_SK" | _hex_dump | tr -d " ")" | _base64 | tr -- '+/' '-_')"
  echo "$QINIU_AK:$_token"
}
