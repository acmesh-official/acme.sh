#!/usr/bin/env sh

# Script to upload certificates to Alibaba Cloud CAS and optionally bind them to OSS CNAMEs.
#
# Supported OSS binding variables:
#    export ALIYUN_OSS_BINDINGS="bucket-a@oss-cn-hangzhou.aliyuncs.com:static.example.com bucket-b@oss-cn-shanghai.aliyuncs.com:img.example.com"
#
# Notes:
# - Binding a brand-new custom domain to OSS may still require a CNAME token workflow.
#   This hook is aimed at rotating the certificate for existing OSS custom domains.
# - `Ali_CAS_REGION` controls where the certificate is uploaded in CAS.
# - Each `ALIYUN_OSS_BINDINGS` item must use the format `bucket@endpoint:domain`.
# - This hook requires the `aliyun` CLI, `ossutil`, and `jq`.

ali_cas_oss_deploy() {
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

  if ! _ali_cas_prepare_oss; then
    return 1
  fi

  DOMAIN="$_cdomain"
  _ali_cas_name_prefix="$(_ali_cas_name_prefix "$DOMAIN")"
  # Certificate name includes a saved-only instance marker to distinguish multiple acme.sh instances.
  CERT_NAME="${_ali_cas_name_prefix}-$(date +%s)"

  result=$(aliyun cas ListUserCertificateOrder --access-key-id="$_ali_key" --access-key-secret="$_ali_secret" --region "$Ali_CAS_REGION" --OrderType CERT --Keyword "$_ali_cas_name_prefix") || return 1
  cert_list=$(printf '%s\n' "$result" | jq -cr ".CertificateOrderList | map(select((.Name // \"\") | startswith(\"$_ali_cas_name_prefix\"))) | map(.CertificateId) | .[]")

  upload_result=$(aliyun cas UploadUserCertificate --access-key-id="$_ali_key" --access-key-secret="$_ali_secret" --region "$Ali_CAS_REGION" --Name "$CERT_NAME" --Cert="$(cat $_cfullchain)" --Key="$(cat $_ckey)") || return 1
  _debug2 upload_result "$upload_result"

  cert_id=$(printf '%s\n' "$upload_result" | jq -r '.CertId // .CertificateId // empty' 2>/dev/null)
  if [ -z "$cert_id" ]; then
    _err "UploadUserCertificate succeeded but no CertId was returned."
    return 1
  fi

  if ! _ali_cas_deploy_oss_cnames "$cert_id"; then
    aliyun cas DeleteUserCertificate --access-key-id="$_ali_key" --access-key-secret="$_ali_secret" --region "$Ali_CAS_REGION" --CertId "$cert_id" >/dev/null
    _err "Certificate uploaded, but OSS CNAME binding failed."
    return 1
  fi

  for _id in $cert_list; do
    aliyun cas DeleteUserCertificate --access-key-id="$_ali_key" --access-key-secret="$_ali_secret" --region "$Ali_CAS_REGION" --CertId "$_id" >/dev/null || return 1
    _info "Deleted old certificate: $_id"
  done
  unset _id

  return 0
}

_ali_cas_prepare_oss() {
  _getdeployconf ALIYUN_OSS_BINDINGS

  if [ "$ALIYUN_OSS_BINDINGS" ]; then
    _savedeployconf ALIYUN_OSS_BINDINGS "$ALIYUN_OSS_BINDINGS"
  else
    _err "ALIYUN_OSS_BINDINGS must be set."
    return 1
  fi

  if ! command -v ossutil >/dev/null 2>&1; then
    _err "ossutil is required for OSS certificate binding but was not found in PATH."
    return 1
  fi

  return 0
}

_ali_cas_deploy_oss_cnames() {
  _cert_id="$1"

  _bindings="$(_ali_cas_collect_oss_bindings)"

  _info "Updating OSS CNAME certificates with CertId=$_cert_id"
  for _binding in $_bindings; do
    if ! _ali_cas_deploy_single_oss_cname "$_binding" "$_cert_id"; then
      _err "Failed to update OSS binding: $_binding"
      return 1
    fi
  done

  return 0
}

_ali_cas_collect_oss_bindings() {
  printf '%s\n' "$ALIYUN_OSS_BINDINGS"
}

_ali_cas_deploy_single_oss_cname() {
  _binding="$1"
  _cert_id="$2"

  _bucket_and_endpoint="${_binding%%:*}"
  _domain="${_binding#*:}"
  if [ -z "$_bucket_and_endpoint" ] || [ -z "$_domain" ] || [ "$_bucket_and_endpoint" = "$_binding" ]; then
    _err "Invalid ALIYUN_OSS binding: $_binding"
    _err "Expected format: bucket@endpoint:domain"
    return 1
  fi

  _bucket="${_bucket_and_endpoint%%@*}"
  _oss_endpoint="${_bucket_and_endpoint#*@}"

  if [ -z "$_bucket" ] || [ -z "$_domain" ]; then
    _err "Invalid ALIYUN_OSS binding: $_binding"
    return 1
  fi

  if [ "$_bucket" = "$_bucket_and_endpoint" ] || [ -z "$_oss_endpoint" ]; then
    _err "No OSS endpoint provided for binding: $_binding"
    return 1
  fi

  _tmp_xml="$(mktemp /tmp/acme-aliyun-oss-cname-XXXXXX.xml)"
  _tmp_current="$(mktemp /tmp/acme-aliyun-oss-current-XXXXXX.xml)"
  rm -f "$_tmp_current"

  if ! _ali_cas_ossutil_get_cname_config "$_bucket" "$_oss_endpoint" "$_tmp_current"; then
    _err "ossutil failed to fetch current CNAME config for bucket $_bucket with endpoint $_oss_endpoint"
    rm -f "$_tmp_xml" "$_tmp_current"
    return 1
  fi

  _previous_cert_id="$(_ali_cas_extract_previous_cert_id "$_domain" "$_tmp_current")"
  _ali_cas_write_oss_certificate_xml "$_domain" "$_cert_id" "$_previous_cert_id" "$_tmp_xml"

  if ! _ali_cas_ossutil_put_cname_certificate "$_bucket" "$_oss_endpoint" "$_tmp_xml"; then
    _err "ossutil failed to update CNAME certificate for domain $_domain on bucket $_bucket with endpoint $_oss_endpoint"
    rm -f "$_tmp_xml" "$_tmp_current"
    return 1
  fi

  _info "Updated OSS domain $_domain on bucket $_bucket"
  rm -f "$_tmp_xml" "$_tmp_current"
  return 0
}

_ali_cas_ossutil_get_cname_config() {
  _bucket="$1"
  _endpoint="$2"
  _outfile="$3"
  _proxy_host="$(_ali_cas_ossutil_proxy_host)"

  set -- ossutil bucket-cname \
    --method get \
    --endpoint "$_endpoint" \
    --access-key-id="$_ali_key" \
    --access-key-secret="$_ali_secret"
  if [ "$_proxy_host" ]; then
    set -- "$@" --proxy-host "$_proxy_host"
  fi
  set -- "$@" "oss://$_bucket" "$_outfile"

  _ossutil_output="$("$@" 2>&1)"
  _ossutil_status=$?

  if [ "$_ossutil_status" != "0" ]; then
    [ "$_ossutil_output" ] && _err "$_ossutil_output"
    return "$_ossutil_status"
  fi

  return 0
}

_ali_cas_ossutil_put_cname_certificate() {
  _bucket="$1"
  _endpoint="$2"
  _xml_file="$3"
  _proxy_host="$(_ali_cas_ossutil_proxy_host)"

  set -- ossutil bucket-cname \
    --method put \
    --item certificate \
    --endpoint "$_endpoint" \
    --access-key-id="$_ali_key" \
    --access-key-secret="$_ali_secret"
  if [ "$_proxy_host" ]; then
    set -- "$@" --proxy-host "$_proxy_host"
  fi
  set -- "$@" "oss://$_bucket" "$_xml_file"

  _ossutil_output="$("$@" 2>&1)"
  _ossutil_status=$?

  if [ "$_ossutil_status" != "0" ]; then
    [ "$_ossutil_output" ] && _err "$_ossutil_output"
    return "$_ossutil_status"
  fi

  return 0
}

_ali_cas_ossutil_proxy_host() {
  _proxy_host="${HTTPS_PROXY:-${https_proxy:-${HTTP_PROXY:-${http_proxy:-}}}}"

  if [ -z "$_proxy_host" ]; then
    return 0
  fi

  if _ali_cas_ossutil_no_proxy_covers_aliyuncs; then
    return 0
  fi

  printf '%s\n' "$_proxy_host"
}

_ali_cas_ossutil_no_proxy_covers_aliyuncs() {
  _no_proxy_value="${NO_PROXY:-${no_proxy:-}}"

  if [ -z "$_no_proxy_value" ]; then
    return 1
  fi

  _old_ifs=$IFS
  IFS=','
  for _no_proxy_entry in $_no_proxy_value; do
    _no_proxy_entry=$(printf '%s' "$_no_proxy_entry" | sed 's/^ *//; s/ *$//')
    case "$_no_proxy_entry" in
      "*" | "aliyuncs.com" | ".aliyuncs.com" | "*.aliyuncs.com")
        IFS=$_old_ifs
        return 0
        ;;
    esac
  done
  IFS=$_old_ifs

  return 1
}

_ali_cas_extract_previous_cert_id() {
  _domain="$1"
  _xml_file="$2"

  _ali_cas_extract_matching_cname_block "$_domain" "$_xml_file" | _ali_cas_extract_cert_id_from_cname_block
}

_ali_cas_extract_matching_cname_block() {
  _domain="$1"
  _xml_file="$2"

  awk -v domain="$_domain" '
    /<Cname>/ {
      block = $0 ORS
      inblock = 1
      next
    }

    inblock {
      block = block $0 ORS
    }

    /<\/Cname>/ {
      if (index(block, "<Domain>" domain "</Domain>") > 0) {
        printf "%s", block
        exit 0
      }
      block = ""
      inblock = 0
    }
  ' "$_xml_file"
}

_ali_cas_extract_cert_id_from_cname_block() {
  tr '\n' ' ' | sed -n 's:.*<CertId>\([^<]*\)</CertId>.*:\1:p'
}

_ali_cas_write_oss_certificate_xml() {
  _domain="$1"
  _cert_id="$2"
  _previous_cert_id="$3"
  _outfile="$4"

  {
    printf '%s\n' '<?xml version="1.0" encoding="utf-8"?>'
    printf '%s\n' '<BucketCnameConfiguration>'
    printf '%s\n' '  <Cname>'
    printf '    <Domain>%s</Domain>\n' "$_domain"
    _ali_cas_write_oss_certificate_configuration "$_cert_id" "$_previous_cert_id"
    printf '%s\n' '  </Cname>'
    printf '%s\n' '</BucketCnameConfiguration>'
  } >"$_outfile"
}

_ali_cas_write_oss_certificate_configuration() {
  _cert_id="$1"
  _previous_cert_id="$2"

  printf '%s\n' '    <CertificateConfiguration>'
  printf '      <CertId>%s</CertId>\n' "$_cert_id"
  if [ "$_previous_cert_id" ]; then
    printf '      <PreviousCertId>%s</PreviousCertId>\n' "$_previous_cert_id"
  fi
  printf '%s\n' '      <Force>true</Force>'
  printf '%s\n' '    </CertificateConfiguration>'
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
