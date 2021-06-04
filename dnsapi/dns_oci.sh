#!/usr/bin/env sh
#
# Acme.sh DNS API plugin for Oracle Cloud Infrastructure
# Copyright (c) 2021, Oracle and/or its affiliates
#
# Required environment variables:
# - OCI_TENANCY    : OCID of tenancy that contains the target DNS zone
# - OCI_USER       : OCID of user with permission to add/remove records from zones
# - OCI_FINGERPRINT: fingerprint of the public key for the user
# - OCI_PRIVATE_KEY: Path to private API signing key file in PEM format
#
# Optional environment variables:
# - OCI_KEY_PASSPHRASE: if the private key above s encrypted, the passphrase is required
# - OCI_REGION: Your home region will probably response the fastest
#

dns_oci_add() {
  _fqdn="$1"
  _rdata="$2"

  if _oci_config; then

    if ! _get_zone "$_fqdn"; then
      _err "Error: DNS Zone not found for $_fqdn."
      return 1
    fi

    if [ "$_sub_domain" ] && [ "$_domain" ]; then
      _add_record_body="{\"items\":[{\"domain\":\"${_sub_domain}.${_domain}\",\"rdata\":\"$_rdata\",\"rtype\":\"TXT\",\"ttl\": 30,\"operation\":\"ADD\"}]}"
      response=$(_signed_request "PATCH" "/20180115/zones/${_domain}/records" "$_add_record_body")
      if [ "$response" ]; then
        _info "Success: added TXT record for ${_sub_domain}.${_domain}."
      else
        _err "Error: failed to add TXT record for ${_sub_domain}.${_domain}."
        return 1
      fi
    fi

  else
    return 1
  fi

}

dns_oci_rm() {
  _fqdn="$1"
  _rdata="$2"

  if _oci_config; then

    if ! _get_zone "$_fqdn"; then
      _err "Error: DNS Zone not found for $_fqdn."
      return 1
    fi

    if [ "$_sub_domain" ] && [ "$_domain" ]; then
      _remove_record_body="{\"items\":[{\"domain\":\"${_sub_domain}.${_domain}\",\"rdata\":\"$_rdata\",\"rtype\":\"TXT\",\"operation\":\"REMOVE\"}]}"
      response=$(_signed_request "PATCH" "/20180115/zones/${_domain}/records" "$_remove_record_body")
      if [ "$response" ]; then
        _info "Success: removed TXT record for ${_sub_domain}.${_domain}."
      else
        _err "Error: failed to remove TXT record for ${_sub_domain}.${_domain}."
        return 1
      fi
    fi

  else
    return 1
  fi

}

####################  Private functions below ##################################
_oci_config() {

  OCI_TENANCY="${OCI_TENANCY:-$(_readaccountconf_mutable OCI_TENANCY)}"
  OCI_USER="${OCI_USER:-$(_readaccountconf_mutable OCI_USER)}"
  OCI_FINGERPRINT="${OCI_FINGERPRINT:-$(_readaccountconf_mutable OCI_FINGERPRINT)}"
  OCI_PRIVATE_KEY="${OCI_PRIVATE_KEY:-$(_readaccountconf_mutable OCI_PRIVATE_KEY)}"
  OCI_KEY_PASSPHRASE="${OCI_KEY_PASSPHRASE:-$(_readaccountconf_mutable OCI_KEY_PASSPHRASE)}"
  OCI_REGION="${OCI_REGION:-$(_readaccountconf_mutable OCI_REGION)}"

  _not_set=""
  _ret=0

  if [ -f "$OCI_PRIVATE_KEY" ]; then
    OCI_PRIVATE_KEY="$(openssl enc -a -A <"$OCI_PRIVATE_KEY")"
  fi

  if [ -z "$OCI_TENANCY" ]; then
    _not_set="OCI_TENANCY "
  fi

  if [ -z "$OCI_USER" ]; then
    _not_set="${_not_set}OCI_USER "
  fi

  if [ -z "$OCI_FINGERPRINT" ]; then
    _not_set="${_not_set}OCI_FINGERPRINT "
  fi

  if [ -z "$OCI_PRIVATE_KEY" ]; then
    _not_set="${_not_set}OCI_PRIVATE_KEY"
  fi

  if [ "$_not_set" ]; then
    _err "Fatal: environment variable(s): ${_not_set} not set."
    _ret=1
  else
    _saveaccountconf_mutable OCI_TENANCY "$OCI_TENANCY"
    _saveaccountconf_mutable OCI_USER "$OCI_USER"
    _saveaccountconf_mutable OCI_FINGERPRINT "$OCI_FINGERPRINT"
    _saveaccountconf_mutable OCI_PRIVATE_KEY "$OCI_PRIVATE_KEY"
  fi

  if [ "$OCI_PRIVATE_KEY" ] && [ "$(printf "%s\n" "$OCI_PRIVATE_KEY" | wc -l)" -eq 1 ]; then
    OCI_PRIVATE_KEY="$(echo "$OCI_PRIVATE_KEY" | openssl enc -d -a -A)"
    _secure_debug3 OCI_PRIVATE_KEY "$OCI_PRIVATE_KEY"
  fi

  if [ "$OCI_KEY_PASSPHRASE" ]; then
    _saveaccountconf_mutable OCI_KEY_PASSPHRASE "$OCI_KEY_PASSPHRASE"
  fi

  if [ "$OCI_REGION" ]; then
    _saveaccountconf_mutable OCI_REGION "$OCI_REGION"
  else
    OCI_REGION="us-ashburn-1"
  fi

  return $_ret

}

# _get_zone(): retrieves the Zone name and OCID
#
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_ociid=ocid1.dns-zone.oc1..
_get_zone() {
  domain=$1
  i=1
  p=1

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      # not valid
      return 1
    fi

    _domain_id=$(_signed_request "GET" "/20180115/zones/$h" "" "id")
    if [ "$_domain_id" ]; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain=$h

      _debug _domain_id "$_domain_id"
      _debug _sub_domain "$_sub_domain"
      _debug _domain "$_domain"
      return 0
    fi

    p=$i
    i=$(_math "$i" + 1)
  done
  return 1

}

_signed_request() {

  _sig_method="$1"
  _sig_target="$2"
  _sig_body="$3"
  _return_field="$4"

  _sig_host="dns.$OCI_REGION.oraclecloud.com"
  _sig_keyId="$OCI_TENANCY/$OCI_USER/$OCI_FINGERPRINT"
  _sig_alg="rsa-sha256"
  _sig_version="1"
  _sig_now="$(LC_ALL=C \date -u "+%a, %d %h %Y %H:%M:%S GMT")"

  if [ "$OCI_KEY_PASSPHRASE" ]; then
    export OCI_KEY_PASSPHRASE="$OCI_KEY_PASSPHRASE"
    _sig_passinArg="-passin env:OCI_KEY_PASSPHRASE"
  fi

  _request_method=$(printf %s "$_sig_method" | _lower_case)
  _curl_method=$(printf %s "$_sig_method" | _upper_case)

  _request_target="(request-target): $_request_method $_sig_target"
  _date_header="date: $_sig_now"
  _host_header="host: $_sig_host"

  _string_to_sign="$_request_target\n$_date_header\n$_host_header"
  _sig_headers="(request-target) date host"

  if [ "$_sig_body" ]; then
    _secure_debug3 _sig_body "$_sig_body"
    _sig_body_sha256="x-content-sha256: $(printf %s "$_sig_body" | openssl dgst -binary -sha256 | openssl enc -e -base64)"
    _sig_body_type="content-type: application/json"
    _sig_body_length="content-length: ${#_sig_body}"
    _string_to_sign="$_string_to_sign\n$_sig_body_sha256\n$_sig_body_type\n$_sig_body_length"
    _sig_headers="$_sig_headers x-content-sha256 content-type content-length"
  fi

  _tmp_file=$(_mktemp)
  if [ -f "$_tmp_file" ]; then
    printf '%s' "$OCI_PRIVATE_KEY" >"$_tmp_file"
    # Double quoting the file and passphrase breaks openssl
    # shellcheck disable=SC2086
    _signature=$(printf '%b' "$_string_to_sign" | openssl dgst -sha256 -sign $_tmp_file $_sig_passinArg | openssl enc -e -base64 | tr -d '\r\n')
    rm -f "$_tmp_file"
  fi

  _signed_header="Authorization: Signature version=\"$_sig_version\",keyId=\"$_sig_keyId\",algorithm=\"$_sig_alg\",headers=\"$_sig_headers\",signature=\"$_signature\""
  _secure_debug3 _signed_header "$_signed_header"

  if [ "$_curl_method" = "GET" ]; then
    export _H1="$_date_header"
    export _H2="$_signed_header"
    _response="$(_get "https://${_sig_host}${_sig_target}")"
  elif [ "$_curl_method" = "PATCH" ]; then
    export _H1="$_date_header"
    export _H2="$_sig_body_sha256"
    export _H3="$_sig_body_type"
    export _H4="$_sig_body_length"
    export _H5="$_signed_header"
    _response="$(_post "$_sig_body" "https://${_sig_host}${_sig_target}" "" "PATCH")"
  else
    _err "Unable to process method: $_curl_method."
  fi

  _ret="$?"
  if [ "$_return_field" ]; then
    _response="$(echo "$_response" | sed 's/\\\"//g'))"
    _return=$(echo "${_response}" | _egrep_o "\"$_return_field\"\\s*:\\s*\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d "\"")
  else
    _return="$_response"
  fi

  printf "%s" "$_return"
  return $_ret

}
