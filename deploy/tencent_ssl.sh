#!/usr/bin/env sh

#export DEPLOY_TENCENT_SSL_SECRET_ID="AKIDz81d2cd22cdcdc2dcd1cc1d1A"
#export DEPLOY_TENCENT_SSL_SECRET_KEY="Gu5t9abcabcaabcbabcbbbcbcbbccbbcb"

tencent_ssl_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _cfullchain "$_cfullchain"

  _getdeployconf DEPLOY_TENCENT_SSL_SECRET_ID
  _getdeployconf DEPLOY_TENCENT_SSL_SECRET_KEY
  if [ -z "${DEPLOY_TENCENT_SSL_SECRET_ID}" ]; then
    _err "Please define DEPLOY_TENCENT_SSL_SECRET_ID."
    return 1
  fi
  if [ -z "${DEPLOY_TENCENT_SSL_SECRET_KEY}" ]; then
    _err "Please define DEPLOY_TENCENT_SSL_SECRET_KEY."
    return 1
  fi
  _savedeployconf DEPLOY_TENCENT_SSL_SECRET_ID "$DEPLOY_TENCENT_SSL_SECRET_ID"
  _savedeployconf DEPLOY_TENCENT_SSL_SECRET_KEY "$DEPLOY_TENCENT_SSL_SECRET_KEY"

  # https://cloud.tencent.com/document/api/400/41665
  _payload="{\"CertificatePublicKey\":\"$(_json_encode <"$_cfullchain")\",\"CertificatePrivateKey\":\"$(_json_encode <"$_ckey")\",\"Alias\":\"acme.sh $_cdomain\"}"
  if ! cert_id="$(tencent_api_request_ssl "UploadCertificate" "$_payload" "CertificateId")"; then
    return 1
  fi
  _debug cert_id "$cert_id"

  _getdeployconf DEPLOY_TENCENT_SSL_CURRENT_CERTIFICATE_ID
  old_cert_id="$DEPLOY_TENCENT_SSL_CURRENT_CERTIFICATE_ID"
  # https://cloud.tencent.com/document/api/400/91649
  # NOTE: no new cert id returned from UpdateCertificateInstance+cert_data
  # so it's necessary to upload cert first then UpdateCertificateInstance+new_cert_id
  if [ -n "${old_cert_id}" ]; then
    _payload="{\"OldCertificateId\":\"$old_cert_id\",\"CertificateId\":\"$cert_id\",\"ResourceTypes\":[\"clb\",\"cdn\",\"waf\",\"live\",\"ddos\",\"teo\",\"apigateway\",\"vod\",\"tke\",\"tcb\",\"tse\"]}"
    if ! tencent_api_request_ssl "UpdateCertificateInstance" "$_payload" "RequestId"; then
      return 1
    fi
    _payload="{\"CertificateId\":\"$old_cert_id\"}"
    if ! tencent_api_request_ssl "DeleteCertificate" "$_payload" "RequestId"; then
      _err "Can not delete old certificate: $old_cert_id"
      # NOTE: non-exist old cert id will not break from UpdateCertificateInstance
      # break it here
      return 1
    fi
  fi
  _savedeployconf DEPLOY_TENCENT_SSL_CURRENT_CERTIFICATE_ID "$cert_id"

  return 0
}

tencent_api_request_ssl() {
  action=$1
  payload=$2
  response_field=$3

  if ! response="$(tencent_api_request "ssl" "2019-12-05" "$action" "$payload")"; then
    _err "Error <$1>"
    return 1
  fi

  err_message="$(echo "$response" | _egrep_o "\"Message\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")"
  if [ "$err_message" ]; then
    _err "$err_message"
    return 1
  fi

  _debug response "$response"

  value="$(echo "$response" | _egrep_o "\"$response_field\":\"[^\"]*\"" | cut -d : -f 2 | tr -d \")"
  if [ -z "$value" ]; then
    _err "$response_field not found"
    return 1
  fi
  echo "$value"
}

# shell client for tencent cloud api v3 | @author: rehiy
# copy from dns_tencent.sh
tencent_sha256() {
  printf %b "$@" | _digest sha256 hex
}

tencent_hmac_sha256() {
  k=$1
  shift
  hex_key=$(printf %b "$k" | _hex_dump | tr -d ' ')
  printf %b "$@" | _hmac sha256 "$hex_key" hex
}

tencent_hmac_sha256_hexkey() {
  k=$1
  shift
  printf %b "$@" | _hmac sha256 "$k" hex
}

tencent_signature_v3() {
  service=$1
  action=$(echo "$2" | _lower_case)
  payload=${3:-'{}'}
  timestamp=${4:-$(date +%s)}

  domain="$service.tencentcloudapi.com"
  secretId="$DEPLOY_TENCENT_SSL_SECRET_ID"
  secretKey="$DEPLOY_TENCENT_SSL_SECRET_KEY"

  algorithm='TC3-HMAC-SHA256'
  date=$(date -u -d "@$timestamp" +%Y-%m-%d 2>/dev/null)
  [ -z "$date" ] && date=$(date -u -r "$timestamp" +%Y-%m-%d)

  canonicalUri='/'
  canonicalQuery=''
  canonicalHeaders="content-type:application/json\nhost:$domain\nx-tc-action:$action\n"
  _debug2 payload "$payload"

  signedHeaders='content-type;host;x-tc-action'
  canonicalRequest="POST\n$canonicalUri\n$canonicalQuery\n$canonicalHeaders\n$signedHeaders\n$(printf %s "$payload" | _digest sha256 hex)"
  _debug2 canonicalRequest "$canonicalRequest"

  credentialScope="$date/$service/tc3_request"
  stringToSign="$algorithm\n$timestamp\n$credentialScope\n$(tencent_sha256 "$canonicalRequest")"
  _debug2 stringToSign "$stringToSign"

  secretDate=$(tencent_hmac_sha256 "TC3$secretKey" "$date")
  secretService=$(tencent_hmac_sha256_hexkey "$secretDate" "$service")
  secretSigning=$(tencent_hmac_sha256_hexkey "$secretService" 'tc3_request')
  signature=$(tencent_hmac_sha256_hexkey "$secretSigning" "$stringToSign")

  echo "$algorithm Credential=$secretId/$credentialScope, SignedHeaders=$signedHeaders, Signature=$signature"
}

tencent_api_request() {
  service=$1
  version=$2
  action=$3
  payload=${4:-'{}'}
  timestamp=${5:-$(date +%s)}

  token=$(tencent_signature_v3 "$service" "$action" "$payload" "$timestamp")

  _H1="Authorization: $token"
  _H2="X-TC-Version: $version"
  _H3="X-TC-Timestamp: $timestamp"
  _H4="X-TC-Action: $action"
  _H5="X-TC-Language: en-US"

  _post "$payload" "https://$service.tencentcloudapi.com" "" "POST" "application/json"
}
