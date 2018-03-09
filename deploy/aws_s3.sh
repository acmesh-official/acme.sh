#!/usr/bin/env sh

#Here is a script to deploy cert to an Amazon S3 bucket.

#returns 0 means success, otherwise error.

# shellcheck source=common/aws.sh
. "$LE_WORKING_DIR/common/aws.sh"

########  Public functions #####################

#domain keyfile certfile cafile fullchain
aws_s3_deploy() {
  _cdomain="$1" _ckey="$2" _ccert="$3" _cca="$4" _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  _bucket="${AWS_S3_BUCKET:-$(_readdomainconf Aws_S3_Bucket)}"
  _prefix="${AWS_S3_PREFIX:-$(_readdomainconf Aws_S3_Prefix)}"
  _region="${AWS_S3_REGION:-$(_readdomainconf Aws_S3_Region)}"

  if [ -z "$_bucket" ]; then
    _err "no S3 bucket to use when deploying $_cdomain"
    return 1
  fi
  if [ -z "$_region" ]; then
    _err "no S3 region to use when deploying $_cdomain"
    return 1
  fi

  _savedomainconf Aws_S3_Bucket "$_bucket"
  _savedomainconf Aws_S3_Prefix "$_prefix"
  _savedomainconf Aws_S3_Region "$_region"

  _debug _bucket "$_bucket"
  _debug _prefix "$_prefix"
  _debug _region "$_region"

  _prefix="$(printf '/%s/' "$_prefix" | sed "s:%cn:$_cdomain:g; s://\+:/:g")"

  _debug _prefix "$_prefix"

  for _file in "$_ckey" "$_ccert" "$_cca" "$_cfullchain"; do
    if ! _aws s3 PUT "$_bucket" "$_prefix${_file##*/}" "$_region" <"$_file" >/dev/null; then
      _err "unable to deploy $_file to s3://$_bucket$_prefix in $_region"
      _ret=2
    fi
  done

  return $_ret
}
