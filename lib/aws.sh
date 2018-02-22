#!/usr/bin/env sh

# usage: _aws <svc> <svcargs...>
#
# services:
#
#   ACM: _aws acm <rpc> <region> [json]
#        _aws acm ListCertificates us-east-1 '{"MaxItems": 2}'
#
#   R53: _aws r53 <verb> <path> [query] [xml]
#        _aws r53 GET /2013-04-01/hostedzone maxitems=2

_aws() {
  _svc="$1" # _args=...
  shift
  if ! _aws_auth; then
    return 255
  fi
  n="$(printf '\nn')" n="${n%n}"
  "_aws_svc_$_svc" "$@"
}

# private

# services

_aws_svc_acm() {
  _rpc="$1" _region="$2" _json="$3"

  _empty='{}'
  _rpc="x-amz-target:CertificateManager.$_rpc"
  _type='content-type:application/x-amz-json-1.1'

  _aws_wrap '"__type":' \
    POST "acm.$_region.amazonaws.com" '/' '' "$_region/acm" \
    "$_rpc$n$_type" "${_json:-$_empty}"
}

_aws_svc_r53() {
  _verb="$1" _path="$2" _query="$3" _xml="$4"

  _aws_wrap '<ErrorResponse' \
    "$_verb" 'route53.amazonaws.com' "$_path" "$_query" 'us-east-1/route53' \
    '' "$_xml"
}

# core

_aws_wrap() {
  _check="$1" # _args=...
  shift
  _resp="$(_aws_req4 "$@")"
  _ret="$?"
  _debug2 _resp "$_resp"
  if [ "$_ret" -eq 0 ] && _contains "$_resp" "$_check"; then
    _err "Response error: $_resp"
    return 1
  fi
  printf %s "$_resp"
  return "$_ret"
}

_aws_req4() {
  _verb="$1" _host="$2" _path="$3" _query="$4" _svc="$5" _hdrs="$6" _data="$7"

  _debug _verb "$_verb"
  _debug _host "$_host"
  _debug _path "$_path"
  _debug _query "$_query"
  _debug _svc "$_svc"
  _debug _hdrs "$_hdrs"
  _debug _data "$_data"

  _date="$(date -u +%Y%m%dT%H%M%SZ)"
  _debug2 _date "$_date"

  _hdrs="host:$_host${n}x-amz-date:$_date$n$_hdrs"
  if [ "$AWS_SESSION_TOKEN" ]; then
    _hdrs="$_hdrs${n}x-amz-security-token:$AWS_SESSION_TOKEN"
  fi
  _hdrs="$(printf %s "$_hdrs" | sort | sed '/^$/d')$n"
  _debug2 _hdrs "$_hdrs"

  _keys="$(
    printf %s "$_hdrs" | while read -r _hdr; do
      printf '%s\n' "${_hdr%%:*}"
    done | paste -sd ';'
  )"
  _debug2 _keys "$_keys"

  _scope="$(printf %s "$_date" | cut -c 1-8)/$_svc/aws4_request"
  _debug2 _scope "$_scope"

  _hash='sha256'
  _debug3 _hash "$_hash"
  _algo='AWS4-HMAC-SHA256'
  _debug3 _algo "$_algo"

  _bdy="$(printf %s "$_data" | _digest "$_hash" hex)"
  _debug2 _bdy "$_bdy"
  _req="$_verb$n$_path$n$_query$n$_hdrs$n$_keys$n$_bdy"
  _debug2 _req "$_req"
  _req="$(printf %s "$_req" | _digest "$_hash" hex)"
  _debug2 _req "$_req"
  _str="$_algo$n$_date$n$_scope$n$_req"
  _debug2 _str "$_str"

  _sig="$(printf %s "AWS4$AWS_SECRET_ACCESS_KEY" | _hex_dump | tr -d ' ')"
  _secure_debug2 _sig "$_sig"
  for _step in $(printf %s "$_scope" | tr '/' ' ') "$_str"; do
    _debug2 _step "$_step"
    _sig="$(printf %s "$_step" | _hmac "$_hash" "$_sig" hex)"
    _debug2 _sig "$_sig"
  done

  _cred="$AWS_ACCESS_KEY_ID/$_scope"
  _auth="$_algo Credential=$_cred, SignedHeaders=$_keys, Signature=$_sig"
  _debug2 _auth "$_auth"

  _url="https://$_host$_path"
  if [ "$_query" ]; then
    _url="$_url?$_query"
  fi

  unset i
  while read -r _line; do
    i=$((i + 1))
    eval "_H$i=\"\$_line\"; _debug2 _H$i \"\$_H$i\""
  done <<-END
		authorization:$_auth
		$_hdrs
	END

  case "$(printf %s "$_verb" | tr '[:upper:]' '[:lower:]')" in
    get) _get "$_url" ;;
    post) _post "$_data" "$_url" ;;
    *) _err '_aws only supports get and post' ;;
  esac
}

# credentials

_aws_auth() {
  _aws_auth_environment || _aws_auth_container_role || _aws_auth_instance_role
}

_aws_auth_environment() {
  AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$(_readaccountconf_mutable AWS_ACCESS_KEY_ID)}"
  AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$(_readaccountconf_mutable AWS_SECRET_ACCESS_KEY)}"
  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
    return 1
  fi
  if [ -z "$_aws_using_role" ]; then
    _saveaccountconf_mutable AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"
    _saveaccountconf_mutable AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"
  fi
}

_aws_auth_container_role() {
  # automatically set if running inside ECS
  if [ -z "$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" ]; then
    _debug 'no ECS environment variable detected'
    return 1
  fi
  _aws_auth_metadata "169.254.170.2$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI"
}

_aws_auth_instance_role() {
  _url='http://169.254.169.254/latest/meta-data/iam/security-credentials/'
  _debug _url "$_url"
  _aws_role=$(_get "$_url" '' 1)
  if [ "$?" -gt 0 ]; then
    _debug 'unable to fetch IAM role from instance metadata'
    return 1
  fi
  _debug _aws_role "$_aws_role"
  _aws_auth_metadata "$_url$_aws_role"
}

_aws_auth_metadata() {
  _url="$1"

  _aws_creds="$(
    _get "$_url" "" 1 \
      | _normalizeJson \
      | tr '{,}' '\n' \
      | while read -r _line; do
        _key="$(printf %s "${_line%%:*}" | tr -d '"')" _value="${_line#*:}"
        _debug3 _key "$_key"
        _secure_debug3 _value "$_value"
        case "$_key" in
          AccessKeyId) printf '%s\n' "AWS_ACCESS_KEY_ID=$_value" ;;
          SecretAccessKey) printf '%s\n' "AWS_SECRET_ACCESS_KEY=$_value" ;;
          Token) printf '%s\n' "AWS_SESSION_TOKEN=$_value" ;;
        esac
      done \
        | paste -sd' ' -
  )"
  _secure_debug _aws_creds "$_aws_creds"

  if [ -z "$_aws_creds" ]; then
    return 1
  fi

  eval "$_aws_creds"
  _aws_using_role=true
}
