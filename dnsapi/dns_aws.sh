#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_aws_info='Amazon AWS Route53 domain API
Site: docs.aws.amazon.com/route53/
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_aws
Options:
 AWS_ACCESS_KEY_ID API Key ID
 AWS_SECRET_ACCESS_KEY API Secret
 AWS_RA_TRUST_ANCHOR_ARN IAM Roles Anywhere trust anchor ARN. Optional, enables X.509 cert auth.
 AWS_RA_PROFILE_ARN IAM Roles Anywhere profile ARN. Optional.
 AWS_RA_ROLE_ARN IAM role ARN to assume via Roles Anywhere. Optional.
 AWS_RA_CERT Roles Anywhere client certificate: a PEM file path or the PEM contents. Optional, default "~/.aws/rolesanywhere/certificate.pem".
 AWS_RA_KEY Roles Anywhere client private key: a PEM file path or the PEM contents. Optional, default "~/.aws/rolesanywhere/private-key.pem".
 AWS_RA_REGION Roles Anywhere region. Optional, default parsed from the trust anchor ARN.
 AWS_RA_DURATION Roles Anywhere session duration in seconds (900-43200). Optional, default "3600".
'

# All `_sleep` commands are included to avoid Route53 throttling, see
# https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/DNSLimitations.html#limits-api-requests

# Updated from "route53.amazonaws.com"
AWS_HOST="route53.global.api.aws"
AWS_URL="https://$AWS_HOST"

AWS_WIKI="https://github.com/acmesh-official/acme.sh/wiki/How-to-use-Amazon-Route53-API"

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_aws_add() {
  fulldomain=$1
  txtvalue=$2

  AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$(_readaccountconf_mutable AWS_ACCESS_KEY_ID)}"
  AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$(_readaccountconf_mutable AWS_SECRET_ACCESS_KEY)}"
  AWS_DNS_SLOWRATE="${AWS_DNS_SLOWRATE:-$(_readaccountconf_mutable AWS_DNS_SLOWRATE)}"

  # IAM Roles Anywhere takes precedence when configured: it is a deliberate opt-in
  # and should not silently lose to a stale key left in account.conf.
  if _aws_ra_configured; then
    if ! _use_roles_anywhere; then
      return 1
    fi
  elif [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    _use_container_role || _use_instance_role
  fi

  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_ACCESS_KEY_ID=""
    AWS_SECRET_ACCESS_KEY=""
    _err "You haven't specified the aws route53 api key id and and api key secret yet."
    _err "Please create your key and try again. see $(__green $AWS_WIKI)"
    return 1
  fi

  #save for future use, unless using a role which will be fetched as needed
  if [ -z "$_using_role" ]; then
    _saveaccountconf_mutable AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"
    _saveaccountconf_mutable AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"
    _saveaccountconf_mutable AWS_DNS_SLOWRATE "$AWS_DNS_SLOWRATE"
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    _sleep 1
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Getting existing records for $fulldomain"
  if ! aws_rest GET "2013-04-01$_domain_id/rrset" "name=$fulldomain&type=TXT"; then
    _sleep 1
    return 1
  fi

  if _contains "$response" "<Name>$fulldomain.</Name>"; then
    _resource_record="$(echo "$response" | sed 's/<ResourceRecordSet>/"/g' | tr '"' "\n" | grep "<Name>$fulldomain.</Name>" | _egrep_o "<ResourceRecords.*</ResourceRecords>" | sed "s/<ResourceRecords>//" | sed "s#</ResourceRecords>##")"
    _debug "_resource_record" "$_resource_record"
  else
    _debug "single new add"
  fi

  if [ "$_resource_record" ] && _contains "$response" "$txtvalue"; then
    _info "The TXT record already exists. Skipping."
    _sleep 1
    return 0
  fi

  _debug "Adding records"

  _aws_tmpl_xml="<ChangeResourceRecordSetsRequest xmlns=\"https://route53.amazonaws.com/doc/2013-04-01/\"><ChangeBatch><Changes><Change><Action>UPSERT</Action><ResourceRecordSet><Name>$fulldomain</Name><Type>TXT</Type><TTL>300</TTL><ResourceRecords>$_resource_record<ResourceRecord><Value>\"$txtvalue\"</Value></ResourceRecord></ResourceRecords></ResourceRecordSet></Change></Changes></ChangeBatch></ChangeResourceRecordSetsRequest>"

  if aws_rest POST "2013-04-01$_domain_id/rrset/" "" "$_aws_tmpl_xml" && _contains "$response" "ChangeResourceRecordSetsResponse"; then
    _info "TXT record updated successfully."
    if [ -n "$AWS_DNS_SLOWRATE" ]; then
      _info "Slow rate activated: sleeping for $AWS_DNS_SLOWRATE seconds"
      _sleep "$AWS_DNS_SLOWRATE"
    else
      _sleep 1
    fi

    return 0
  fi
  _sleep 1
  return 1
}

#fulldomain txtvalue
dns_aws_rm() {
  fulldomain=$1
  txtvalue=$2

  AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$(_readaccountconf_mutable AWS_ACCESS_KEY_ID)}"
  AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$(_readaccountconf_mutable AWS_SECRET_ACCESS_KEY)}"
  AWS_DNS_SLOWRATE="${AWS_DNS_SLOWRATE:-$(_readaccountconf_mutable AWS_DNS_SLOWRATE)}"

  if _aws_ra_configured; then
    if ! _use_roles_anywhere; then
      return 1
    fi
  elif [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    _use_container_role || _use_instance_role
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    _sleep 1
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _info "Getting existing records for $fulldomain"
  if ! aws_rest GET "2013-04-01$_domain_id/rrset" "name=$fulldomain&type=TXT"; then
    _sleep 1
    return 1
  fi

  if _contains "$response" "<Name>$fulldomain.</Name>"; then
    _resource_record="$(echo "$response" | sed 's/<ResourceRecordSet>/"/g' | tr '"' "\n" | grep "<Name>$fulldomain.</Name>" | _egrep_o "<ResourceRecords.*</ResourceRecords>" | sed "s/<ResourceRecords>//" | sed "s#</ResourceRecords>##")"
    _debug "_resource_record" "$_resource_record"
  else
    _debug "no records exist, skip"
    _sleep 1
    return 0
  fi

  _aws_tmpl_xml="<ChangeResourceRecordSetsRequest xmlns=\"https://route53.amazonaws.com/doc/2013-04-01/\"><ChangeBatch><Changes><Change><Action>DELETE</Action><ResourceRecordSet><ResourceRecords>$_resource_record</ResourceRecords><Name>$fulldomain.</Name><Type>TXT</Type><TTL>300</TTL></ResourceRecordSet></Change></Changes></ChangeBatch></ChangeResourceRecordSetsRequest>"

  if aws_rest POST "2013-04-01$_domain_id/rrset/" "" "$_aws_tmpl_xml" && _contains "$response" "ChangeResourceRecordSetsResponse"; then
    _info "TXT record deleted successfully."
    if [ -n "$AWS_DNS_SLOWRATE" ]; then
      _info "Slow rate activated: sleeping for $AWS_DNS_SLOWRATE seconds"
      _sleep "$AWS_DNS_SLOWRATE"
    else
      _sleep 1
    fi

    return 0
  fi
  _sleep 1
  return 1
}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=1
  p=1

  # iterate over names (a.b.c.d -> b.c.d -> c.d -> d)
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f "$i"-100 | sed 's/\./\\./g')
    _debug "Checking domain: $h"
    if [ -z "$h" ]; then
      _err "invalid domain"
      return 1
    fi

    # iterate over paginated result for list_hosted_zones
    aws_rest GET "2013-04-01/hostedzone"
    while true; do
      if _contains "$response" "<Name>$h.</Name>"; then
        hostedzone="$(echo "$response" | tr -d '\n' | sed 's/<HostedZone>/#&/g' | tr '#' '\n' | _egrep_o "<HostedZone><Id>[^<]*<.Id><Name>$h.<.Name>.*<PrivateZone>false<.PrivateZone>.*<.HostedZone>")"
        _debug hostedzone "$hostedzone"
        if [ "$hostedzone" ]; then
          _domain_id=$(printf "%s\n" "$hostedzone" | _egrep_o "<Id>.*<.Id>" | head -n 1 | _egrep_o ">.*<" | tr -d "<>")
          if [ "$_domain_id" ]; then
            _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-"$p")
            _domain=$h
            return 0
          fi
          _err "Can't find domain with id: $h"
          return 1
        fi
      fi
      if _contains "$response" "<IsTruncated>true</IsTruncated>" && _contains "$response" "<NextMarker>"; then
        _debug "IsTruncated"
        _nextMarker="$(echo "$response" | _egrep_o "<NextMarker>.*</NextMarker>" | cut -d '>' -f 2 | cut -d '<' -f 1)"
        _debug "NextMarker" "$_nextMarker"
      else
        break
      fi
      _debug "Checking domain: $h - Next Page "
      aws_rest GET "2013-04-01/hostedzone" "marker=$_nextMarker"
    done
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_use_container_role() {
  # automatically set if running inside ECS
  if [ -z "$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" ]; then
    _debug "No ECS environment variable detected"
    return 1
  fi
  _use_metadata "169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
}

_use_instance_role() {
  _instance_role_name_url="http://169.254.169.254/latest/meta-data/iam/security-credentials/"

  if _get "$_instance_role_name_url" true 1 | _head_n 1 | grep -Fq 401; then
    _debug "Using IMDSv2"
    _token_url="http://169.254.169.254/latest/api/token"
    export _H1="X-aws-ec2-metadata-token-ttl-seconds: 21600"
    _token="$(_post "" "$_token_url" "" "PUT")"
    _secure_debug3 "_token" "$_token"
    if [ -z "$_token" ]; then
      _debug "Unable to fetch IMDSv2 token from instance metadata"
      return 1
    fi
    export _H1="X-aws-ec2-metadata-token: $_token"
  fi

  if ! _get "$_instance_role_name_url" true 1 | _head_n 1 | grep -Fq 200; then
    _debug "Unable to fetch IAM role from instance metadata"
    return 1
  fi

  _instance_role_name=$(_get "$_instance_role_name_url" "" 1)
  _debug "_instance_role_name" "$_instance_role_name"
  _use_metadata "$_instance_role_name_url$_instance_role_name" "$_token"

}

_use_metadata() {
  export _H1="X-aws-ec2-metadata-token: $2"
  _aws_creds="$(
    _get "$1" "" 1 |
      _normalizeJson |
      tr '{,}' '\n' |
      while read -r _line; do
        _key="$(echo "${_line%%:*}" | tr -d '\"')"
        _value="${_line#*:}"
        _debug3 "_key" "$_key"
        _secure_debug3 "_value" "$_value"
        case "$_key" in
        AccessKeyId) echo "AWS_ACCESS_KEY_ID=$_value" ;;
        SecretAccessKey) echo "AWS_SECRET_ACCESS_KEY=$_value" ;;
        Token) echo "AWS_SESSION_TOKEN=$_value" ;;
        esac
      done |
      paste -sd' ' -
  )"
  _secure_debug "_aws_creds" "$_aws_creds"

  if [ -z "$_aws_creds" ]; then
    return 1
  fi

  eval "$_aws_creds"
  _using_role=true
}

# Returns 0 when the IAM Roles Anywhere trust anchor, profile and role ARNs are all set.
_aws_ra_configured() {
  AWS_RA_TRUST_ANCHOR_ARN="${AWS_RA_TRUST_ANCHOR_ARN:-$(_readaccountconf_mutable AWS_RA_TRUST_ANCHOR_ARN)}"
  AWS_RA_PROFILE_ARN="${AWS_RA_PROFILE_ARN:-$(_readaccountconf_mutable AWS_RA_PROFILE_ARN)}"
  AWS_RA_ROLE_ARN="${AWS_RA_ROLE_ARN:-$(_readaccountconf_mutable AWS_RA_ROLE_ARN)}"
  [ -n "$AWS_RA_TRUST_ANCHOR_ARN" ] && [ -n "$AWS_RA_PROFILE_ARN" ] && [ -n "$AWS_RA_ROLE_ARN" ]
}

# decimal_string multiplier addend
# Computes (decimal_string * multiplier + addend) for small multiplier/addend,
# keeping the running value as a decimal string so serials wider than the shell's
# integer type are handled. No bc/awk/python (not portable across acme.sh targets).
_aws_ra_dec_muladd() {
  _num="$1"
  _mul="$2"
  _carry="$3"
  _out=""
  _i=${#_num}
  while [ "$_i" -ge 1 ]; do
    _digit=$(printf "%s" "$_num" | cut -c "$_i")
    _p=$(_math "$_digit" \* "$_mul" + "$_carry")
    _carry=$(_math "$_p" / 10)
    _out="$(_math "$_p" % 10)$_out"
    _i=$(_math "$_i" - 1)
  done
  while [ "$_carry" -gt 0 ]; do
    _out="$(_math "$_carry" % 10)$_out"
    _carry=$(_math "$_carry" / 10)
  done
  [ -z "$_out" ] && _out=0
  printf "%s" "$_out"
}

# hex_string
# Converts an arbitrarily long hex string to its decimal representation. Used to turn
# a certificate serial number into the decimal form the Roles Anywhere Credential field
# expects (matches certificate.SerialNumber.String() in the AWS credential helper).
_aws_ra_hex2dec() {
  _hex=$(printf "%s" "$1" | _upper_case)
  _dec=0
  _i=1
  _len=${#_hex}
  while [ "$_i" -le "$_len" ]; do
    _ch=$(printf "%s" "$_hex" | cut -c "$_i")
    _d=$(_h_char_2_dec "$_ch")
    _dec=$(_aws_ra_dec_muladd "$_dec" 16 "$_d")
    _i=$(_math "$_i" + 1)
  done
  printf "%s" "$_dec"
}

# Authenticate to AWS via IAM Roles Anywhere using an X.509 client certificate,
# exchanging it for temporary credentials through the CreateSession API. On success
# it sets AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN and marks the
# session as a role so the (temporary) credentials are never persisted.
#
# Wrapper: materialise any inline PEM to a temp file, run the implementation, then
# always clean up the temp files (they may hold the private key), preserving the
# implementation's return code.
_use_roles_anywhere() {
  AWS_RA_CERT="${AWS_RA_CERT:-$(_readaccountconf_mutable AWS_RA_CERT)}"
  AWS_RA_KEY="${AWS_RA_KEY:-$(_readaccountconf_mutable AWS_RA_KEY)}"

  # AWS_RA_CERT/AWS_RA_KEY may be a filesystem path or the PEM contents themselves
  # (contents let the material be supplied through an env var / secret, e.g. CI).
  _ra_cert_tmp=""
  _ra_key_tmp=""
  _ra_cert="${AWS_RA_CERT:-$HOME/.aws/rolesanywhere/certificate.pem}"
  _ra_key="${AWS_RA_KEY:-$HOME/.aws/rolesanywhere/private-key.pem}"
  if _startswith "$AWS_RA_CERT" "-----BEGIN"; then
    if ! _ra_cert_tmp="$(_aws_ra_write_temp "$AWS_RA_CERT")"; then
      return 1
    fi
    _ra_cert="$_ra_cert_tmp"
  fi
  if _startswith "$AWS_RA_KEY" "-----BEGIN"; then
    if ! _ra_key_tmp="$(_aws_ra_write_temp "$AWS_RA_KEY")"; then
      [ -n "$_ra_cert_tmp" ] && rm -f "$_ra_cert_tmp"
      return 1
    fi
    _ra_key="$_ra_key_tmp"
  fi

  _use_roles_anywhere_impl
  _ra_ret="$?"

  [ -n "$_ra_cert_tmp" ] && rm -f "$_ra_cert_tmp"
  [ -n "$_ra_key_tmp" ] && rm -f "$_ra_key_tmp"
  return "$_ra_ret"
}

# contents
# Writes PEM contents to a private temp file and echoes its path.
#
# Because the file holds a private key, it must be created by mktemp(1), which
# atomically opens a fresh file with O_EXCL and mode 600. We deliberately do NOT fall
# back to the predictable _mktemp name here: that path is not created by mktemp, so
# writing to it could follow an attacker-planted symlink or truncate an existing file
# (a symlink/tempfile race). On systems without mktemp, callers must pass file paths.
_aws_ra_write_temp() {
  if ! _exists mktemp; then
    _err "Roles Anywhere: inline PEM contents require the 'mktemp' command."
    _err "Point AWS_RA_CERT/AWS_RA_KEY at PEM file paths instead."
    return 1
  fi
  _ra_tmp="$(
    umask 077
    mktemp 2>/dev/null || mktemp -t "$PROJECT_NAME" 2>/dev/null
  )"
  if [ -z "$_ra_tmp" ] || [ ! -f "$_ra_tmp" ] || [ -L "$_ra_tmp" ]; then
    _err "Roles Anywhere: unable to create a secure temporary file."
    [ -n "$_ra_tmp" ] && rm -f "$_ra_tmp"
    return 1
  fi
  if ! printf "%s" "$1" >"$_ra_tmp"; then
    _err "Roles Anywhere: unable to write the temporary certificate/key file."
    rm -f "$_ra_tmp"
    return 1
  fi
  printf "%s" "$_ra_tmp"
}

# Implementation of the Roles Anywhere exchange. Reads $_ra_cert / $_ra_key (resolved
# to real files by _use_roles_anywhere) and $AWS_RA_* for the rest of the config.
_use_roles_anywhere_impl() {
  AWS_RA_REGION="${AWS_RA_REGION:-$(_readaccountconf_mutable AWS_RA_REGION)}"
  AWS_RA_DURATION="${AWS_RA_DURATION:-$(_readaccountconf_mutable AWS_RA_DURATION)}"
  _ra_duration="${AWS_RA_DURATION:-3600}"

  if [ ! -r "$_ra_cert" ]; then
    _err "Roles Anywhere certificate not found or not readable: $_ra_cert"
    _err "See $(__green "$AWS_WIKI")"
    return 1
  fi
  if [ ! -r "$_ra_key" ]; then
    _err "Roles Anywhere private key not found or not readable: $_ra_key"
    _err "See $(__green "$AWS_WIKI")"
    return 1
  fi

  # Region: explicit override, else the region field of the trust anchor ARN
  # arn:aws:rolesanywhere:<region>:<account>:trust-anchor/<id>
  _ra_region="$AWS_RA_REGION"
  if [ -z "$_ra_region" ]; then
    _ra_region=$(printf "%s" "$AWS_RA_TRUST_ANCHOR_ARN" | cut -d : -f 4)
  fi
  if [ -z "$_ra_region" ]; then
    _err "Unable to determine Roles Anywhere region. Set AWS_RA_REGION."
    return 1
  fi
  _debug2 _ra_region "$_ra_region"

  # Signing algorithm is fixed by the client certificate's key type.
  if ${ACME_OPENSSL_BIN:-openssl} rsa -in "$_ra_key" -noout >/dev/null 2>&1; then
    _ra_algorithm="AWS4-X509-RSA-SHA256"
  elif ${ACME_OPENSSL_BIN:-openssl} ec -in "$_ra_key" -noout >/dev/null 2>&1; then
    _ra_algorithm="AWS4-X509-ECDSA-SHA256"
  else
    _err "Unsupported Roles Anywhere key type (need an RSA or EC private key): $_ra_key"
    return 1
  fi
  _debug2 _ra_algorithm "$_ra_algorithm"

  # base64(DER(cert)) for the X-Amz-X509 header, single line.
  _ra_x509=$(${ACME_OPENSSL_BIN:-openssl} x509 -in "$_ra_cert" -outform DER | _base64 | tr -d '\r\n')
  if [ -z "$_ra_x509" ]; then
    _err "Unable to read Roles Anywhere certificate: $_ra_cert"
    return 1
  fi

  # Certificate serial number as a decimal integer for the Credential field.
  _ra_serial_hex=$(${ACME_OPENSSL_BIN:-openssl} x509 -in "$_ra_cert" -serial -noout | cut -d = -f 2)
  _ra_serial=$(_aws_ra_hex2dec "$_ra_serial_hex")
  _debug2 _ra_serial "$_ra_serial"

  _ra_host="rolesanywhere.$_ra_region.amazonaws.com"
  _ra_date="$(date -u +"%Y%m%dT%H%M%SZ")"
  _ra_date_only="$(echo "$_ra_date" | cut -c 1-8)"

  _ra_payload="{\"durationSeconds\":$_ra_duration,\"profileArn\":\"$AWS_RA_PROFILE_ARN\",\"roleArn\":\"$AWS_RA_ROLE_ARN\",\"trustAnchorArn\":\"$AWS_RA_TRUST_ANCHOR_ARN\"}"
  _debug2 _ra_payload "$_ra_payload"

  _ra_signed_headers="content-type;host;x-amz-date;x-amz-x509"
  _ra_canonical_headers="content-type:application/json\nhost:$_ra_host\nx-amz-date:$_ra_date\nx-amz-x509:$_ra_x509\n"
  _ra_canonical_request="POST\n/sessions\n\n$_ra_canonical_headers\n$_ra_signed_headers\n$(printf "%s" "$_ra_payload" | _digest "sha256" hex)"
  _debug2 _ra_canonical_request "$_ra_canonical_request"

  _ra_scope="$_ra_date_only/$_ra_region/rolesanywhere/aws4_request"
  _ra_string_to_sign="$_ra_algorithm\n$_ra_date\n$_ra_scope\n$(printf "$_ra_canonical_request%s" | _digest "sha256" hex)"
  _debug2 _ra_string_to_sign "$_ra_string_to_sign"

  # Sign with the certificate's private key. openssl emits PKCS#1 for RSA and ASN.1 DER
  # for ECDSA, which is exactly what Roles Anywhere expects; hex-encode the result.
  _ra_signature=$(printf "$_ra_string_to_sign%s" | ${ACME_OPENSSL_BIN:-openssl} dgst -sha256 -sign "$_ra_key" | _hex_dump | tr -d ' ')
  if [ -z "$_ra_signature" ]; then
    _err "Roles Anywhere signing failed for key: $_ra_key"
    return 1
  fi
  _secure_debug2 _ra_signature "$_ra_signature"

  _ra_authz="$_ra_algorithm Credential=$_ra_serial/$_ra_scope, SignedHeaders=$_ra_signed_headers, Signature=$_ra_signature"
  _secure_debug2 _ra_authz "$_ra_authz"

  export _H1="x-amz-date: $_ra_date"
  export _H2="x-amz-x509: $_ra_x509"
  export _H3="content-type: application/json"
  export _H4="Authorization: $_ra_authz"

  _ra_response="$(_post "$_ra_payload" "https://$_ra_host/sessions")"
  _ret="$?"
  unset _H1 _H2 _H3 _H4
  _secure_debug2 _ra_response "$_ra_response"
  if [ "$_ret" != "0" ]; then
    _err "Roles Anywhere CreateSession request failed."
    return 1
  fi

  _aws_creds="$(
    echo "$_ra_response" |
      _normalizeJson |
      tr '{,}' '\n' |
      while read -r _line; do
        _key="$(echo "${_line%%:*}" | tr -d '\"')"
        _value="${_line#*:}"
        case "$_key" in
        accessKeyId) echo "AWS_ACCESS_KEY_ID=$_value" ;;
        secretAccessKey) echo "AWS_SECRET_ACCESS_KEY=$_value" ;;
        sessionToken) echo "AWS_SESSION_TOKEN=$_value" ;;
        esac
      done |
      paste -sd' ' -
  )"
  _secure_debug "_aws_creds" "$_aws_creds"

  if [ -z "$_aws_creds" ]; then
    _err "Roles Anywhere did not return credentials. Response: $_ra_response"
    return 1
  fi

  eval "$_aws_creds"
  _using_role=true
}

#method uri qstr data
aws_rest() {
  mtd="$1"
  ep="$2"
  qsr="$3"
  data="$4"

  _debug mtd "$mtd"
  _debug ep "$ep"
  _debug qsr "$qsr"
  _debug data "$data"

  CanonicalURI="/$ep"
  _debug2 CanonicalURI "$CanonicalURI"

  CanonicalQueryString="$qsr"
  _debug2 CanonicalQueryString "$CanonicalQueryString"

  RequestDate="$(date -u +"%Y%m%dT%H%M%SZ")"
  _debug2 RequestDate "$RequestDate"

  #RequestDate="20161120T141056Z" ##############

  export _H1="x-amz-date: $RequestDate"

  aws_host="$AWS_HOST"
  CanonicalHeaders="host:$aws_host\nx-amz-date:$RequestDate\n"
  SignedHeaders="host;x-amz-date"
  if [ -n "$AWS_SESSION_TOKEN" ]; then
    export _H3="x-amz-security-token: $AWS_SESSION_TOKEN"
    CanonicalHeaders="${CanonicalHeaders}x-amz-security-token:$AWS_SESSION_TOKEN\n"
    SignedHeaders="${SignedHeaders};x-amz-security-token"
  fi
  _debug2 CanonicalHeaders "$CanonicalHeaders"
  _debug2 SignedHeaders "$SignedHeaders"

  RequestPayload="$data"
  _debug2 RequestPayload "$RequestPayload"

  Hash="sha256"

  CanonicalRequest="$mtd\n$CanonicalURI\n$CanonicalQueryString\n$CanonicalHeaders\n$SignedHeaders\n$(printf "%s" "$RequestPayload" | _digest "$Hash" hex)"
  _debug2 CanonicalRequest "$CanonicalRequest"

  HashedCanonicalRequest="$(printf "$CanonicalRequest%s" | _digest "$Hash" hex)"
  _debug2 HashedCanonicalRequest "$HashedCanonicalRequest"

  Algorithm="AWS4-HMAC-SHA256"
  _debug2 Algorithm "$Algorithm"

  RequestDateOnly="$(echo "$RequestDate" | cut -c 1-8)"
  _debug2 RequestDateOnly "$RequestDateOnly"

  Region="us-east-1"
  Service="route53"

  CredentialScope="$RequestDateOnly/$Region/$Service/aws4_request"
  _debug2 CredentialScope "$CredentialScope"

  StringToSign="$Algorithm\n$RequestDate\n$CredentialScope\n$HashedCanonicalRequest"

  _debug2 StringToSign "$StringToSign"

  kSecret="AWS4$AWS_SECRET_ACCESS_KEY"

  #kSecret="wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY" ############################

  _secure_debug2 kSecret "$kSecret"

  kSecretH="$(printf "%s" "$kSecret" | _hex_dump | tr -d " ")"
  _secure_debug2 kSecretH "$kSecretH"

  kDateH="$(printf "$RequestDateOnly%s" | _hmac "$Hash" "$kSecretH" hex)"
  _debug2 kDateH "$kDateH"

  kRegionH="$(printf "$Region%s" | _hmac "$Hash" "$kDateH" hex)"
  _debug2 kRegionH "$kRegionH"

  kServiceH="$(printf "$Service%s" | _hmac "$Hash" "$kRegionH" hex)"
  _debug2 kServiceH "$kServiceH"

  kSigningH="$(printf "%s" "aws4_request" | _hmac "$Hash" "$kServiceH" hex)"
  _debug2 kSigningH "$kSigningH"

  signature="$(printf "$StringToSign%s" | _hmac "$Hash" "$kSigningH" hex)"
  _debug2 signature "$signature"

  Authorization="$Algorithm Credential=$AWS_ACCESS_KEY_ID/$CredentialScope, SignedHeaders=$SignedHeaders, Signature=$signature"
  _debug2 Authorization "$Authorization"

  _H2="Authorization: $Authorization"
  _debug _H2 "$_H2"

  url="$AWS_URL/$ep"
  if [ "$qsr" ]; then
    url="$AWS_URL/$ep?$qsr"
  fi

  if [ "$mtd" = "GET" ]; then
    response="$(_get "$url")"
  else
    response="$(_post "$data" "$url")"
  fi

  _ret="$?"
  _debug2 response "$response"
  if [ "$_ret" = "0" ]; then
    if _contains "$response" "<ErrorResponse"; then
      _err "Response error:$response"
      return 1
    fi
  fi

  return "$_ret"
}
