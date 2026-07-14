#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_oci_info='Oracle Cloud Infrastructure (OCI)
 Resource principal auth is selected automatically when OCI_RESOURCE_PRINCIPAL_VERSION=2.2.
 API-key auth from OCI CLI config or OCI_CLI_* values is used otherwise.
 delegated subzones are supported by selecting the most-specific accessible zone.
 DNS policy must allow zone read and TXT record write, for example "read dns-zones" and "use dns-records".
Site: cloud.oracle.com
Docs: github.com/acmesh-official/acme.sh/wiki/How-to-use-Oracle-Cloud-Infrastructure-DNS
Options:
 OCI_CLI_TENANCY OCID of tenancy that contains the target DNS zone. Optional.
 OCI_CLI_USER OCID of user with permission to add/remove records from zones. Optional.
 OCI_CLI_REGION Should point to the tenancy home region. Optional.
 OCI_CLI_KEY_FILE Path to private API signing key file in PEM format. Optional.
 OCI_CLI_KEY The private API signing key in PEM format. Optional.
 OCI_RESOURCE_PRINCIPAL_VERSION Must be 2.2 for resource principal auth. Optional.
 OCI_RESOURCE_PRINCIPAL_RPST Path to RPST file or inline RPST value. Optional.
 OCI_RESOURCE_PRINCIPAL_PRIVATE_PEM Path to private PEM file or inline PEM value. Optional.
 OCI_RESOURCE_PRINCIPAL_REGION Region for resource principal DNS requests. Optional.
 OCI_RESOURCE_PRINCIPAL_PRIVATE_PEM_PASSPHRASE Path to passphrase file or inline passphrase value. Optional.
Issues: github.com/acmesh-official/acme.sh/issues/3540
'

# Copyright (c) 2021, Oracle and/or its affiliates
# Copyright (c) 2026, Avi Miller <me@dje.li>
#
# API-key auth will automatically use the default profile from an OCI SDK and
# CLI configuration file, if it exists.
#
# Alternatively, set the following environment variables:
# - OCI_CLI_TENANCY : OCID of tenancy that contains the target DNS zone
# - OCI_CLI_USER    : OCID of user with permission to add/remove records from zones
# - OCI_CLI_REGION  : Should point to the tenancy home region
#
# For API-key auth, one of the following two variables is required:
# - OCI_CLI_KEY_FILE: Path to private API signing key file in PEM format; or
# - OCI_CLI_KEY     : The private API signing key in PEM format
#
# Resource principal auth is selected when OCI_RESOURCE_PRINCIPAL_VERSION=2.2,
# using the configured RPST, private PEM, region, and optional passphrase.
#

dns_oci_add() {
  _fqdn="$1"
  _rdata="$2"

  if _get_oci_zone; then

    _oci_record_domain_json=$(_oci_json_escape "$_oci_record_domain")
    _rdata_json=$(_oci_json_escape "$_rdata")
    _add_record_body="{\"items\":[{\"domain\":\"$_oci_record_domain_json\",\"rdata\":\"$_rdata_json\",\"rtype\":\"TXT\",\"ttl\": 30,\"operation\":\"ADD\"}]}"
    response=$(_signed_request "PATCH" "/20180115/zones/${_domain}/records" "$_add_record_body")
    if [ "$response" ]; then
      _info "Success: added TXT record for $_oci_record_domain."
    else
      _err "Error: failed to add TXT record for $_oci_record_domain."
      _err "Check that the user has permission to add records to this zone."
      return 1
    fi

  else
    return 1
  fi

}

dns_oci_rm() {
  _fqdn="$1"
  _rdata="$2"

  if _get_oci_zone; then

    _oci_record_domain_json=$(_oci_json_escape "$_oci_record_domain")
    _rdata_json=$(_oci_json_escape "$_rdata")
    _remove_record_body="{\"items\":[{\"domain\":\"$_oci_record_domain_json\",\"rdata\":\"$_rdata_json\",\"rtype\":\"TXT\",\"operation\":\"REMOVE\"}]}"
    response=$(_signed_request "PATCH" "/20180115/zones/${_domain}/records" "$_remove_record_body")
    if [ "$response" ]; then
      _info "Success: removed TXT record for $_oci_record_domain."
    else
      _err "Error: failed to remove TXT record for $_oci_record_domain."
      _err "Check that the user has permission to remove records from this zone."
      return 1
    fi

  else
    return 1
  fi

}

####################  Private functions below ##################################
_oci_auth_mode=""
_oci_resource_principal_auth_error=""
_oci_rp_rpst=""
_oci_rp_private_pem=""
_oci_rp_private_pem_passphrase=""
_oci_rp_region=""

_get_oci_zone() {
  _oci_resource_principal_auth_error=""

  if ! _oci_select_auth; then
    return 1
  fi

  if ! _get_zone "$_fqdn"; then
    if [ "$_oci_resource_principal_auth_error" ]; then
      return 1
    fi
    if [ "$_oci_zone_lookup_authz_error" ]; then
      return 1
    fi
    _err "Error: DNS Zone not found for $_fqdn in $OCI_CLI_TENANCY"
    _err "Check that the zone exists and the user has permission to read it."
    return 1
  fi

  return 0

}

_oci_select_auth() {
  _oci_auth_mode=""

  if _oci_resource_principal_requested; then
    _oci_auth_mode="resource_principal"
    return 0
  fi

  if _oci_config; then
    _oci_auth_mode="api_key"
    return 0
  fi

  _oci_report_api_key_auth_missing

  _oci_report_resource_principal_auth_missing
  return 1
}

_oci_report_api_key_auth_missing() {
  _oci_missing_api_key_fields=""

  [ -z "$OCI_CLI_TENANCY" ] && _oci_missing_api_key_fields="${_oci_missing_api_key_fields} OCI_CLI_TENANCY"
  [ -z "$OCI_CLI_USER" ] && _oci_missing_api_key_fields="${_oci_missing_api_key_fields} OCI_CLI_USER"
  [ -z "$OCI_CLI_REGION" ] && _oci_missing_api_key_fields="${_oci_missing_api_key_fields} OCI_CLI_REGION"
  if [ -z "$OCI_CLI_KEY_FILE" ] && [ -z "$OCI_CLI_KEY" ]; then
    _oci_missing_api_key_fields="${_oci_missing_api_key_fields} OCI_CLI_KEY_FILE or OCI_CLI_KEY"
  fi

  if [ "$_oci_missing_api_key_fields" ]; then
    _oci_missing_api_key_fields=$(printf "%s" "$_oci_missing_api_key_fields" | sed 's/^ //')
    _err "Error: OCI API-key authentication is incomplete. Missing: $_oci_missing_api_key_fields."
  fi
}

_oci_resource_principal_requested() {
  [ "$OCI_RESOURCE_PRINCIPAL_VERSION" = "2.2" ]
}

_oci_report_resource_principal_auth_missing() {
  _oci_missing_resource_principal_fields=""

  [ "$OCI_RESOURCE_PRINCIPAL_VERSION" != "2.2" ] && _oci_missing_resource_principal_fields="${_oci_missing_resource_principal_fields} OCI_RESOURCE_PRINCIPAL_VERSION=2.2"
  [ -z "$OCI_RESOURCE_PRINCIPAL_RPST" ] && _oci_missing_resource_principal_fields="${_oci_missing_resource_principal_fields} OCI_RESOURCE_PRINCIPAL_RPST"
  [ -z "$OCI_RESOURCE_PRINCIPAL_PRIVATE_PEM" ] && _oci_missing_resource_principal_fields="${_oci_missing_resource_principal_fields} OCI_RESOURCE_PRINCIPAL_PRIVATE_PEM"
  [ -z "$OCI_RESOURCE_PRINCIPAL_REGION" ] && _oci_missing_resource_principal_fields="${_oci_missing_resource_principal_fields} OCI_RESOURCE_PRINCIPAL_REGION"

  if [ "$_oci_missing_resource_principal_fields" ]; then
    _oci_missing_resource_principal_fields=$(printf "%s" "$_oci_missing_resource_principal_fields" | sed 's/^ //')
    _err "Error: OCI resource principal authentication is incomplete. Missing: $_oci_missing_resource_principal_fields."
  fi
}

_oci_reset_resource_principal_material() {
  _oci_rp_rpst=""
  _oci_rp_private_pem=""
  _oci_rp_private_pem_passphrase=""
  _oci_rp_region=""
}

_oci_strip_quotes() {
  printf "%s" "$1" | sed "s/^[\"']//; s/[\"']$//"
}

_oci_resolve_api_key_field() {
  _oci_field_name=$1
  _oci_field_ini_key=$2
  eval "_oci_field_value=\$$_oci_field_name"
  if [ -z "$_oci_field_value" ] && [ -f "$OCI_CLI_CONFIG_FILE" ]; then
    _debug "Reading $_oci_field_name value from: $OCI_CLI_CONFIG_FILE"
    _oci_field_value=$(_readini "$OCI_CLI_CONFIG_FILE" "$_oci_field_ini_key" "$OCI_CLI_PROFILE")
  fi
  if [ -z "$_oci_field_value" ] && [ -z "$_oci_ignore_saved_api_key_config" ]; then
    _oci_field_value=$(_readaccountconf_mutable "$_oci_field_name")
  fi
  _oci_field_value=$(_oci_strip_quotes "$_oci_field_value")
  if [ "$_oci_field_value" ]; then
    _saveaccountconf_mutable "$_oci_field_name" "$_oci_field_value"
  fi
  eval "$_oci_field_name=\$_oci_field_value"
  if [ -z "$_oci_field_value" ]; then
    _err "Error: unable to read $_oci_field_name from config file or environment variable."
    return 1
  fi
  return 0
}

_oci_normalize_path() {
  [ "$1" ] || return 0
  _oci_path=$(_oci_strip_quotes "$1")

  case "$_oci_path" in
  [~]) printf "%s" "$HOME" ;;
  [~]/*) printf "%s%s" "$HOME" "${_oci_path#?}" ;;
  *) printf "%s" "$_oci_path" ;;
  esac
}

_oci_read_resource_principal_value() {
  _oci_rp_env_name="$1"
  _oci_rp_required="${2:-}"

  eval "_oci_rp_env_value=\${$_oci_rp_env_name:-}"

  if [ -z "$_oci_rp_env_value" ]; then
    if [ "$_oci_rp_required" = "required" ]; then
      _err "Error: OCI resource principal material $_oci_rp_env_name missing."
      return 1
    fi
    return 0
  fi

  if [ -f "$_oci_rp_env_value" ]; then
    if ! _oci_rp_file_value=$(cat "$_oci_rp_env_value" 2>/dev/null); then
      _err "Error: OCI resource principal material $_oci_rp_env_name unreadable."
      return 1
    fi
    printf "%s" "$_oci_rp_file_value"
    return 0
  fi

  printf "%s" "$_oci_rp_env_value"
}

_oci_load_resource_principal_material() {
  _oci_reset_resource_principal_material

  if [ "$OCI_RESOURCE_PRINCIPAL_VERSION" != "2.2" ]; then
    _err "Error: OCI resource principal material OCI_RESOURCE_PRINCIPAL_VERSION=2.2 unsupported."
    return 1
  fi

  if [ -z "$OCI_RESOURCE_PRINCIPAL_REGION" ]; then
    _err "Error: OCI resource principal material OCI_RESOURCE_PRINCIPAL_REGION missing."
    return 1
  fi

  if ! _oci_rp_rpst="$(_oci_read_resource_principal_value OCI_RESOURCE_PRINCIPAL_RPST required)"; then
    _oci_reset_resource_principal_material
    return 1
  fi

  if ! _oci_rp_private_pem="$(_oci_read_resource_principal_value OCI_RESOURCE_PRINCIPAL_PRIVATE_PEM required)"; then
    _oci_reset_resource_principal_material
    return 1
  fi

  if ! _oci_rp_private_pem_passphrase="$(_oci_read_resource_principal_value OCI_RESOURCE_PRINCIPAL_PRIVATE_PEM_PASSPHRASE optional)"; then
    _oci_reset_resource_principal_material
    return 1
  fi

  _oci_rp_region="$OCI_RESOURCE_PRINCIPAL_REGION"
  return 0
}

_oci_config() {

  _DEFAULT_OCI_CLI_CONFIG_FILE="$HOME/.oci/config"
  _oci_ignore_saved_api_key_config=""
  _oci_saved_config_file="$(_readaccountconf_mutable OCI_CLI_CONFIG_FILE)"
  if [ -z "$OCI_CLI_CONFIG_FILE" ] && [ "$_oci_saved_config_file" ]; then
    OCI_CLI_CONFIG_FILE="$(_oci_normalize_path "$_oci_saved_config_file")"
    if [ ! -f "$OCI_CLI_CONFIG_FILE" ]; then
      _debug "Saved OCI_CLI_CONFIG_FILE not found, using default OCI CLI config" "$OCI_CLI_CONFIG_FILE"
      _clearaccountconf_mutable OCI_CLI_CONFIG_FILE
      _clearaccountconf_mutable OCI_CLI_TENANCY
      _clearaccountconf_mutable OCI_CLI_USER
      _clearaccountconf_mutable OCI_CLI_REGION
      _clearaccountconf_mutable OCI_CLI_KEY
      OCI_CLI_CONFIG_FILE="$_DEFAULT_OCI_CLI_CONFIG_FILE"
      _oci_ignore_saved_api_key_config=1
    fi
  elif [ "$OCI_CLI_CONFIG_FILE" ]; then
    OCI_CLI_CONFIG_FILE="$(_oci_normalize_path "$OCI_CLI_CONFIG_FILE")"
  fi

  if [ -z "$OCI_CLI_CONFIG_FILE" ]; then
    OCI_CLI_CONFIG_FILE="$_DEFAULT_OCI_CLI_CONFIG_FILE"
  fi

  if [ "$_DEFAULT_OCI_CLI_CONFIG_FILE" != "$OCI_CLI_CONFIG_FILE" ]; then
    _saveaccountconf_mutable OCI_CLI_CONFIG_FILE "$OCI_CLI_CONFIG_FILE"
  else
    _clearaccountconf_mutable OCI_CLI_CONFIG_FILE
  fi

  _DEFAULT_OCI_CLI_PROFILE="DEFAULT"
  OCI_CLI_PROFILE="${OCI_CLI_PROFILE:-$(_readaccountconf_mutable OCI_CLI_PROFILE)}"
  OCI_CLI_PROFILE="$(_oci_strip_quotes "$OCI_CLI_PROFILE")"
  if [ -z "$OCI_CLI_PROFILE" ]; then
    OCI_CLI_PROFILE="$_DEFAULT_OCI_CLI_PROFILE"
  fi
  if [ "$_DEFAULT_OCI_CLI_PROFILE" != "$OCI_CLI_PROFILE" ]; then
    _saveaccountconf_mutable OCI_CLI_PROFILE "$OCI_CLI_PROFILE"
  else
    OCI_CLI_PROFILE="$_DEFAULT_OCI_CLI_PROFILE"
    _clearaccountconf_mutable OCI_CLI_PROFILE
  fi

  _oci_resolve_api_key_field OCI_CLI_TENANCY tenancy || return 1
  _oci_resolve_api_key_field OCI_CLI_USER user || return 1
  _oci_resolve_api_key_field OCI_CLI_REGION region || return 1

  if [ -z "$OCI_CLI_KEY_FILE" ] && [ -f "$OCI_CLI_CONFIG_FILE" ]; then
    OCI_CLI_KEY_FILE="$(_readini "$OCI_CLI_CONFIG_FILE" key_file "$OCI_CLI_PROFILE")"
  fi
  OCI_CLI_KEY_FILE="$(_oci_normalize_path "$OCI_CLI_KEY_FILE")"

  if [ "$OCI_CLI_KEY" ]; then
    _saveaccountconf_mutable OCI_CLI_KEY "$OCI_CLI_KEY"
  elif [ "$OCI_CLI_KEY_FILE" ] && [ -f "$OCI_CLI_KEY_FILE" ]; then
    _debug "Reading OCI_CLI_KEY value from: $OCI_CLI_KEY_FILE"
    OCI_CLI_KEY=$(_base64 <"$OCI_CLI_KEY_FILE")
    _saveaccountconf_mutable OCI_CLI_KEY "$OCI_CLI_KEY"
  elif [ -z "$_oci_ignore_saved_api_key_config" ]; then
    OCI_CLI_KEY="$(_readaccountconf_mutable OCI_CLI_KEY)"
  fi

  if [ -z "$OCI_CLI_KEY_FILE" ] && [ -z "$OCI_CLI_KEY" ]; then
    _err "Error: unable to find key file path in OCI config file or OCI_CLI_KEY_FILE."
    _err "Error: unable to load private API signing key from OCI_CLI_KEY."
    return 1
  fi

  if [ "$(printf "%s\n" "$OCI_CLI_KEY" | wc -l)" -eq 1 ]; then
    OCI_CLI_KEY=$(printf "%s" "$OCI_CLI_KEY" | _dbase64)
  fi

  return 0

}

# _get_zone(): retrieves the Zone name and OCID
#
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_ociid=ocid1.dns-zone.oc1..
# OCI RecordDetails.domain is the full record FQDN, stored in _oci_record_domain.
_get_zone() {
  domain=$1
  i=1
  p=1
  _oci_zone_lookup_authz_error=""

  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100)
    _debug h "$h"
    if [ -z "$h" ]; then
      # not valid
      return 1
    fi

    _oci_zone_response=$(_signed_request "GET" "/20180115/zones/$h")
    _oci_signed_status="$?"
    if [ "$_oci_signed_status" != "0" ] && [ "$_oci_auth_mode" = "resource_principal" ]; then
      _oci_resource_principal_auth_error=1
      return 1
    fi

    _domain_id=$(_oci_json_string "id" "$_oci_zone_response")
    if [ "$_domain_id" ]; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
      _domain=$h
      _oci_record_domain="${_sub_domain}.${_domain}"

      _debug2 _domain_id "$_domain_id"
      _debug _sub_domain "$_sub_domain"
      _debug _domain "$_domain"
      _debug _oci_record_domain "$_oci_record_domain"
      return 0
    fi

    _oci_status=$(_oci_json_number "status" "$_oci_zone_response")
    _oci_error_code=$(_oci_json_string "code" "$_oci_zone_response")
    _oci_error_message=$(_oci_json_string "message" "$_oci_zone_response")

    if _oci_authz_error "$_oci_status" "$_oci_error_code" "$_oci_error_message"; then
      _oci_zone_lookup_authz_error=1
      _err "Error: OCI returned an authorization or permission failure for $h."
      _err "OCI lookup status=${_oci_status:-unknown} code=${_oci_error_code:-none}."
      return 1
    fi

    _next_i=$(_math "$i" + 1)
    _next_h=$(printf "%s" "$domain" | cut -d . -f "$_next_i"-100)
    if [ "$_next_h" ]; then
      _debug "OCI zone lookup result" "$h status=${_oci_status:-unknown} code=${_oci_error_code:-none}; trying $_next_h"
    fi

    p=$i
    i=$_next_i
  done
  return 1

}

_oci_json_string() {
  _oci_json_field="$1"
  _oci_json_body="$2"

  _oci_json_match=$(printf "%s" "$_oci_json_body" | sed 's/\\\"//g' | _egrep_o "\"$_oci_json_field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | _head_n 1)
  if [ "$_oci_json_match" ]; then
    printf "%s" "$_oci_json_match" | sed 's/^[^:]*:[[:space:]]*"//; s/"$//'
  fi
}

_oci_json_number() {
  _oci_json_field="$1"
  _oci_json_body="$2"

  _oci_json_match=$(printf "%s" "$_oci_json_body" | sed 's/\\\"//g' | _egrep_o "\"$_oci_json_field\"[[:space:]]*:[[:space:]]*[0-9][0-9]*" | _head_n 1)
  if [ "$_oci_json_match" ]; then
    printf "%s" "$_oci_json_match" | sed 's/^[^:]*:[[:space:]]*//'
  fi
}

_oci_authz_error() {
  _oci_status="$1"
  _oci_code="$2"
  _oci_message="$3"

  case "$_oci_code" in
  *NotAuthorizedOrNotFound*) return 1 ;;
  esac

  case "$_oci_status" in
  401 | 403) return 0 ;;
  esac

  case "$_oci_code" in
  *NotAuthenticated* | *NotAuthorized* | *Unauthorized* | *Forbidden* | *Permission* | *permission*) return 0 ;;
  esac

  case "$_oci_message" in
  *"not authorized"* | *"Not authorized"* | *NotAuthorized* | *"permission denied"* | *"Permission denied"* | *Forbidden* | *forbidden* | *Unauthorized* | *unauthorized*) return 0 ;;
  esac

  return 1
}

_oci_json_escape() {
  printf "%s" "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

#Usage: privatekey
#Output MD5 fingerprint
_fingerprint() {

  pkey="$1"
  if [ -z "$pkey" ]; then
    _usage "Usage: _fingerprint privkey"
    return 1
  fi

  printf "%s" "$pkey" | ${ACME_OPENSSL_BIN:-openssl} rsa -pubout -outform DER 2>/dev/null | ${ACME_OPENSSL_BIN:-openssl} md5 -c | cut -d = -f 2 | tr -d ' '

}

_signed_request() {
  if [ "$_oci_auth_mode" = "resource_principal" ]; then
    _signed_request_resource_principal "$@"
    return $?
  fi

  _signed_request_api_key "$@"
}

_signed_request_api_key() {
  _sig_method="$1"
  _sig_target="$2"
  _sig_body="$3"
  _return_field="$4"

  _key_fingerprint=$(_fingerprint "$OCI_CLI_KEY")
  _sig_host="dns.$OCI_CLI_REGION.oraclecloud.com"
  _sig_keyId="$OCI_CLI_TENANCY/$OCI_CLI_USER/$_key_fingerprint"
  _sig_alg="rsa-sha256"
  _sig_version="1"
  _sig_now="$(LC_ALL=C \date -u "+%a, %d %h %Y %H:%M:%S GMT")"

  _request_method=$(printf %s "$_sig_method" | _lower_case)
  _curl_method=$(printf %s "$_sig_method" | _upper_case)

  _request_target="(request-target): $_request_method $_sig_target"
  _date_header="date: $_sig_now"
  _host_header="host: $_sig_host"

  _string_to_sign="$_request_target\n$_date_header\n$_host_header"
  _sig_headers="(request-target) date host"

  if [ "$_sig_body" ]; then
    _secure_debug3 _sig_body "$_sig_body"
    _sig_body_sha256="x-content-sha256: $(printf %s "$_sig_body" | _digest sha256)"
    _sig_body_type="content-type: application/json"
    _sig_body_length="content-length: ${#_sig_body}"
    _string_to_sign="$_string_to_sign\n$_sig_body_sha256\n$_sig_body_type\n$_sig_body_length"
    _sig_headers="$_sig_headers x-content-sha256 content-type content-length"
  fi

  _tmp_file=$(_mktemp)
  if [ -f "$_tmp_file" ]; then
    printf '%s' "$OCI_CLI_KEY" >"$_tmp_file"
    _signature=$(printf '%b' "$_string_to_sign" | _sign "$_tmp_file" sha256 | tr -d '\r\n')
    rm -f "$_tmp_file"
  fi

  _signed_header=$(printf 'Authorization: Signature version="%s",keyId="%s",algorithm="%s",headers="%s",signature="%s"' "$_sig_version" "$_sig_keyId" "$_sig_alg" "$_sig_headers" "$_signature")
  _secure_debug3 _signed_header "$_signed_header"

  if [ "$_curl_method" = "GET" ]; then
    export _H1="$_date_header"
    export _H2="$_signed_header"
    _response="$(_get "https://${_sig_host}${_sig_target}")"
  elif [ "$_curl_method" = "PATCH" ]; then
    export _H1="$_date_header"
    # shellcheck disable=SC2090
    export _H2="$_sig_body_sha256"
    export _H3="$_sig_body_type"
    export _H4="$_sig_body_length"
    # shellcheck disable=SC2090
    export _H5="$_signed_header"
    _response="$(_post "$_sig_body" "https://${_sig_host}${_sig_target}" "" "PATCH")"
  else
    _err "Unable to process method: $_curl_method."
  fi

  _ret="$?"
  if [ "$_return_field" ]; then
    _response="$(echo "$_response" | sed 's/\\\"//g')"
    _return=$(echo "${_response}" | _egrep_o "\"$_return_field\"\\s*:\\s*\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d "\"")
  else
    _return="$_response"
  fi

  printf "%s" "$_return"
  return $_ret

}

_signed_request_resource_principal() {
  _sig_method="$1"
  _sig_target="$2"
  _sig_body="$3"
  _return_field="$4"

  if ! _oci_load_resource_principal_material; then
    _oci_resource_principal_auth_error=1
    return 1
  fi

  _sig_host="dns.$_oci_rp_region.oraclecloud.com"
  _sig_keyId="ST\$$_oci_rp_rpst"
  _sig_alg="rsa-sha256"
  _sig_version="1"
  _sig_now="$(LC_ALL=C \date -u "+%a, %d %h %Y %H:%M:%S GMT")"

  _request_method=$(printf %s "$_sig_method" | _lower_case)
  _curl_method=$(printf %s "$_sig_method" | _upper_case)

  _request_target="(request-target): $_request_method $_sig_target"
  _date_header="date: $_sig_now"
  _host_header="host: $_sig_host"

  _string_to_sign="$_request_target\n$_date_header\n$_host_header"
  _sig_headers="(request-target) date host"

  if [ "$_sig_body" ]; then
    _secure_debug3 _sig_body "$_sig_body"
    _sig_body_sha256="x-content-sha256: $(printf %s "$_sig_body" | _digest sha256)"
    _sig_body_type="content-type: application/json"
    _sig_body_length="content-length: ${#_sig_body}"
    _string_to_sign="$_string_to_sign\n$_sig_body_sha256\n$_sig_body_type\n$_sig_body_length"
    _sig_headers="$_sig_headers x-content-sha256 content-type content-length"
  fi

  _tmp_file=$(_mktemp)
  _sign_status=1
  if [ -f "$_tmp_file" ]; then
    printf '%s' "$_oci_rp_private_pem" >"$_tmp_file"
    _signature=$(printf '%b' "$_string_to_sign" | _oci_sign_with_private_key_file "$_tmp_file" sha256)
    _sign_status="$?"
    _signature=$(printf '%s' "$_signature" | tr -d '\r\n')
    rm -f "$_tmp_file"
  fi

  if [ "$_sign_status" != "0" ] || [ -z "$_signature" ]; then
    _oci_resource_principal_auth_error=1
    if [ "$_oci_rp_private_pem_passphrase" ]; then
      _err "Error: OCI resource principal signing failed for OCI_RESOURCE_PRINCIPAL_PRIVATE_PEM_PASSPHRASE."
    else
      _err "Error: OCI resource principal signing failed."
    fi
    _oci_reset_resource_principal_material
    return 1
  fi

  _signed_header=$(printf 'Authorization: Signature version="%s",keyId="%s",algorithm="%s",headers="%s",signature="%s"' "$_sig_version" "$_sig_keyId" "$_sig_alg" "$_sig_headers" "$_signature")
  _secure_debug3 _string_to_sign "$_string_to_sign"
  _secure_debug3 _signed_header "$_signed_header"

  if [ "$_curl_method" = "GET" ]; then
    export _H1="$_date_header"
    export _H2="$_signed_header"
    _response="$(_get "https://${_sig_host}${_sig_target}")"
  elif [ "$_curl_method" = "PATCH" ]; then
    export _H1="$_date_header"
    # shellcheck disable=SC2090
    export _H2="$_sig_body_sha256"
    export _H3="$_sig_body_type"
    export _H4="$_sig_body_length"
    # shellcheck disable=SC2090
    export _H5="$_signed_header"
    _response="$(_post "$_sig_body" "https://${_sig_host}${_sig_target}" "" "PATCH")"
  else
    _err "Unable to process method: $_curl_method."
  fi

  _ret="$?"
  if [ "$_return_field" ]; then
    _response="$(echo "$_response" | sed 's/\\\"//g')"
    _return=$(echo "${_response}" | _egrep_o "\"$_return_field\"\\s*:\\s*\"[^\"]*\"" | _head_n 1 | cut -d : -f 2 | tr -d "\"")
  else
    _return="$_response"
  fi

  _oci_reset_resource_principal_material
  printf "%s" "$_return"
  return $_ret
}

_oci_sign_with_private_key_file() {
  _oci_sign_key_file="$1"
  _oci_sign_alg="$2"

  if [ -z "$_oci_rp_private_pem_passphrase" ]; then
    _sign "$_oci_sign_key_file" "$_oci_sign_alg"
    return $?
  fi

  _oci_passphrase_file=$(_mktemp)
  if [ ! -f "$_oci_passphrase_file" ]; then
    return 1
  fi

  printf '%s' "$_oci_rp_private_pem_passphrase" >"$_oci_passphrase_file"
  _oci_openssl_sign_with_passphrase "$_oci_sign_key_file" "$_oci_sign_alg" "$_oci_passphrase_file"
  _oci_sign_status="$?"
  rm -f "$_oci_passphrase_file"
  return "$_oci_sign_status"
}

_oci_openssl_sign_with_passphrase() {
  _oci_sign_key_file="$1"
  _oci_sign_alg="$2"
  _oci_passphrase_file="$3"
  _oci_signature_file=$(_mktemp)

  if [ ! -f "$_oci_signature_file" ]; then
    return 1
  fi

  if ${ACME_OPENSSL_BIN:-openssl} dgst "-$_oci_sign_alg" -sign "$_oci_sign_key_file" -passin "file:$_oci_passphrase_file" >"$_oci_signature_file" 2>/dev/null; then
    _base64 <"$_oci_signature_file"
    _oci_sign_status=0
  else
    _oci_sign_status=1
  fi

  rm -f "$_oci_signature_file"
  return "$_oci_sign_status"
}

# file  key  [section]
_readini() {
  _file="$1"
  _key="$2"
  _section="${3:-DEFAULT}"

  _start_n=$(grep -n '\['"$_section"']' "$_file" | cut -d : -f 1)
  _debug3 _start_n "$_start_n"
  if [ -z "$_start_n" ]; then
    _err "Can not find section: $_section"
    return 1
  fi

  _start_nn=$(_math "$_start_n" + 1)
  _debug3 "_start_nn" "$_start_nn"

  _left="$(sed -n "${_start_nn},99999p" "$_file")"
  _debug3 _left "$_left"
  _end="$(echo "$_left" | grep -n "^\[" | _head_n 1)"
  _debug3 "_end" "$_end"
  if [ "$_end" ]; then
    _end_n=$(echo "$_end" | cut -d : -f 1)
    _debug3 "_end_n" "$_end_n"
    _seg_n=$(echo "$_left" | sed -n "1,${_end_n}p")
  else
    _seg_n="$_left"
  fi

  _debug3 "_seg_n" "$_seg_n"
  _lineini="$(echo "$_seg_n" | grep "^ *$_key *= *")"
  _inivalue="$(printf "%b" "$(eval "echo $_lineini | sed \"s/^ *${_key} *= *//g\"")")"
  _debug2 _inivalue "$_inivalue"
  echo "$_inivalue"

}
