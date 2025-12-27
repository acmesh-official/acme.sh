#!/usr/bin/env sh
# shellcheck disable=SC2034,SC2154

# Script to create certificate to Alibaba Cloud CDN
#
# Docs: https://github.com/acmesh-official/acme.sh/wiki/deployhooks#33-deploy-your-certificate-to-cdn-or-dcdn-of-alibaba-cloud-aliyun
#
# This deployment required following variables
# export Ali_Key="ALIACCESSKEY"
# export Ali_Secret="ALISECRETKEY"
# The credentials are shared with all the Alibaba Cloud deploy hooks and dnsapi
#
# To specify the CDN domain that is different from the certificate CN, usually used for multi-domain or wildcard certificates
# export DEPLOY_ALI_CDN_DOMAIN="cdn.example.com"
# If you have multiple CDN domains using the same certificate, just
# export DEPLOY_ALI_CDN_DOMAIN="cdn1.example.com cdn2.example.com"
#
# For DCDN, see ali_dcdn deploy hook

Ali_CDN_API="https://cdn.aliyuncs.com/"

ali_cdn_deploy() {
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

  # Load dnsapi/dns_ali.sh to reduce the duplicated codes
  # https://github.com/acmesh-official/acme.sh/pull/5205#issuecomment-2357867276
  dnsapi_ali="$(_findHook "$_cdomain" "$_SUB_FOLDER_DNSAPI" dns_ali)"
  # shellcheck source=/dev/null
  if ! . "$dnsapi_ali"; then
    _err "Error loading file $dnsapi_ali. Please check your API file and try again."
    return 1
  fi

  _prepare_ali_credentials || return 1

  _getdeployconf DEPLOY_ALI_CDN_DOMAIN
  if [ "$DEPLOY_ALI_CDN_DOMAIN" ]; then
    _savedeployconf DEPLOY_ALI_CDN_DOMAIN "$DEPLOY_ALI_CDN_DOMAIN"
  else
    DEPLOY_ALI_CDN_DOMAIN="$_cdomain"
  fi

  # read cert and key files and urlencode both
  _cert=$(_url_encode upper-hex <"$_cfullchain")
  _key=$(_url_encode upper-hex <"$_ckey")

  _debug2 _cert "$_cert"
  _debug2 _key "$_key"

  ## update domain ssl config
  for domain in $DEPLOY_ALI_CDN_DOMAIN; do
    _set_cdn_domain_ssl_certificate_query "$domain" "$_cert" "$_key"
    if _ali_rest "Set CDN domain SSL certificate for $domain" "" POST; then
      _info "Domain $domain certificate has been deployed successfully"
    fi
  done

  return 0
}

# domain pub pri
_set_cdn_domain_ssl_certificate_query() {
  endpoint=$Ali_CDN_API
  query=''
  query=$query'AccessKeyId='$Ali_Key
  query=$query'&Action=SetCdnDomainSSLCertificate'
  query=$query'&CertType=upload'
  query=$query'&DomainName='$1
  query=$query'&Format=json'
  query=$query'&SSLPri='$3
  query=$query'&SSLProtocol=on'
  query=$query'&SSLPub='$2
  query=$query'&SignatureMethod=HMAC-SHA1'
  query=$query"&SignatureNonce=$(_ali_nonce)"
  query=$query'&SignatureVersion=1.0'
  query=$query'&Timestamp='$(_ali_timestamp)
  query=$query'&Version=2018-05-10'
}
