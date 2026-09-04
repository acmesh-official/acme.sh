#!/usr/bin/env sh

# Script to upload certificates to Alibaba Cloud CAS
#
# Docs: https://github.com/acmesh-official/acme.sh/wiki/deployhooks
#
# This deployment requires the following variables
# export Ali_Key="ALIACCESSKEY"
# export Ali_Secret="ALISECRETKEY"
#
# Optional variable:
# export Ali_CAS_REGION="cn-hangzhou"
# Defaults to cn-hangzhou when not set.
#
# This hook requires the `aliyun` CLI.

ali_cas_deploy() {
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

  _getdeployconf Ali_CAS_REGION
  if [ -z "$Ali_CAS_REGION" ]; then
    Ali_CAS_REGION="cn-hangzhou"
  fi
  _savedeployconf Ali_CAS_REGION "$Ali_CAS_REGION"
  _ali_cas_prepare_instance_id || return 1
  Ali_Key="${Ali_Key:-$(_readaccountconf_mutable Ali_Key)}"
  Ali_Secret="${Ali_Secret:-$(_readaccountconf_mutable Ali_Secret)}"
  _ali_key="$Ali_Key"
  _ali_secret="$Ali_Secret"

  _debug Ali_CAS_REGION "$Ali_CAS_REGION"
  _debug Ali_CAS_INSTANCE_ID "$Ali_CAS_INSTANCE_ID"

  if [ -z "$_ali_key" ] || [ -z "$_ali_secret" ]; then
    _err "Ali_Key and Ali_Secret must be provided via environment variables or account.conf."
    return 1
  fi

  _saveaccountconf_mutable Ali_Key "$_ali_key"
  _saveaccountconf_mutable Ali_Secret "$_ali_secret"

  DOMAIN="$_cdomain"
  _ali_cas_name_prefix="$(_ali_cas_name_prefix "$DOMAIN")"
  # Certificate name includes a saved-only instance marker to distinguish multiple acme.sh instances.
  CERT_NAME="${_ali_cas_name_prefix}-$(date +%s)"

  # Fetch this instance's certificate list by name prefix before upload and delete them after a successful upload.
  result=$(aliyun cas ListUserCertificateOrder --access-key-id="$_ali_key" --access-key-secret="$_ali_secret" --region "$Ali_CAS_REGION" --OrderType CERT --Keyword "$_ali_cas_name_prefix") || return 1
  cert_list=$(printf '%s\n' "$result" | jq -cr ".CertificateOrderList | map(select((.Name // \"\") | startswith(\"$_ali_cas_name_prefix\"))) | map(.CertificateId) | .[]")

  upload_result=$(aliyun cas UploadUserCertificate --access-key-id="$_ali_key" --access-key-secret="$_ali_secret" --region "$Ali_CAS_REGION" --Name "$CERT_NAME" --Cert="$(cat $_cfullchain)" --Key="$(cat $_ckey)") || return 1
  _debug2 upload_result "$upload_result"

  cert_id=$(printf '%s\n' "$upload_result" | jq -r '.CertId // .CertificateId // empty' 2>/dev/null)
  if [ -z "$cert_id" ]; then
    _err "UploadUserCertificate succeeded but no CertId was returned."
    return 1
  fi

  # Delete old certificates.
  for _id in ${cert_list}; do
    aliyun cas DeleteUserCertificate --access-key-id="$_ali_key" --access-key-secret="$_ali_secret" --region "$Ali_CAS_REGION" --CertId $_id
    echo $_id
  done
  unset _id

  return 0
}

_ali_cas_prepare_instance_id() {
  Ali_CAS_INSTANCE_ID="$(_readdomainconf "SAVED_Ali_CAS_INSTANCE_ID")"
  if [ "$Ali_CAS_INSTANCE_ID" ]; then
    return 0
  fi

  Ali_CAS_INSTANCE_ID="$(_ali_cas_new_instance_id)"
  if [ -z "$Ali_CAS_INSTANCE_ID" ]; then
    _err "Failed to create Ali_CAS_INSTANCE_ID."
    return 1
  fi

  _savedeployconf Ali_CAS_INSTANCE_ID "$Ali_CAS_INSTANCE_ID"
}

_ali_cas_new_instance_id() {
  if [ "$ACME_OPENSSL_BIN" ]; then
    "$ACME_OPENSSL_BIN" rand -hex 4 2>/dev/null && return 0
  fi

  printf "%s" "$(date +%s)$$$(date +%N)" | _digest sha256 hex | cut -c 1-8
}

_ali_cas_name_prefix() {
  printf '%s-acme_sh_%s' "$(printf '%s' "$1" | sed 's/\./_/g')" "$Ali_CAS_INSTANCE_ID"
}
