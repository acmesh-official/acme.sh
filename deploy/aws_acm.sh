#!/usr/bin/env sh

#Here is a script to deploy cert to Amazon Certificate Manager.

#returns 0 means success, otherwise error.

# shellcheck source=lib/aws.sh
. "$LE_WORKING_DIR/lib/aws.sh"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
aws_acm_deploy() {
  _cdomain="$1" _ckey="$2" _ccert="$3" _cca="$4" _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  _regions="${AWS_ACM_REGIONS:-$(_readdomainconf Aws_Acm_Regions)}"

  if [ -z "$_regions" ]; then
    _err "no ACM regions to use when deploying $_cdomain"
    return 1
  fi

  _savedomainconf Aws_Acm_Regions "$_regions"

  _ret=0
  for _region in $(printf %s "$_regions" | tr ',' ' '); do
    _debug _region "$_region"

    _arn="$(_get_arn "$_cdomain" "$_region")"
    _debug2 _arn "$_arn"

    _json="{$(_fmt_json \
      CertificateArn "$_arn" \
      Certificate "$(_base64 <"$_ccert")" \
      CertificateChain "$(_base64 <"$_cfullchain")" \
      PrivateKey "$(_base64 <"$_ckey")"
    )}"
    _secure_debug2 _json "$_json"

    if ! _aws acm ImportCertificate "$_region" "$_json" >/dev/null; then
      _err "unable to deploy $_cdomain to ACM in $_region"
      _ret=2
    fi
  done

  return $_ret
}

_get_arn() {
  _page='"MaxItems": 20'
  _next="$_page"
  while [ "$_next" ]; do
    resp="$(_aws acm ListCertificates "$2" "{$_next,$_page}")"
    [ "$?" -eq 0 ] || return 2
    printf %s "$resp" \
      | _normalizeJson \
      | tr '{}' '\n' \
      | grep -F "\"DomainName\":\"$1\"" \
      | _egrep_o "arn:aws:acm:$2:[^\"]+" \
      | grep "^arn:aws:acm:$2:"
    [ "$?" -eq 0 ] && return
    _next="$(printf %s "$resp" | _egrep_o '"NextToken":"[^"]+"')"
    _debug3 _next "$_next"
  done
  return 1
}

_fmt_json() {
  while [ "$#" -gt 1 ]; do
    [ "$2" ] && printf '"%s":"%s"\n' "$1" "$2"
    shift 2
  done | paste -sd ','
}
