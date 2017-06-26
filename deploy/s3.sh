#!/bin/bash

#Here is the script to deploy the cert to your s3 bucket.
#export S3_BUCKET=acme
#export S3_REGION=eu-central-1
#export AWS_ACCESS_KEY_ID=exampleid
#export AWS_SECRET_ACCESS_KEY=examplekey

# Checks to see if awscli present
# If not, use curl + aws v4 signature to upload object
# Make sure your keys have access to upload objects.
# Also make sure your default region is correct, otherwise, override with $S3_REGION

########  Public functions #####################

#domain keyfile certfile cafile fullchain
s3_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"
  
  if [ -z "$S3_BUCKET" ] ; then
    _err "You haven't specified the bucket name yet."
    _err "Please set it via export and try again."
    _err "e.g. export S3_BUCKET=acme"
    return 1
  fi

  if ! command -v aws; then
    _debug "AWS CLI not installed, defaulting to curl method"
    _aws_cli_installed=0
  else
    _debug "AWS CLI installed, defaulting ignoring curl method"
    _aws_cli_installed=1
  fi

  if [ "$_aws_cli_installed" -eq "0" ] && ([ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]); then
    _err "AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY not set."
    _err "Please set them via export, or use the aws-cli."
    return 1
  fi

  if [ -z "$S3_REGION" ]; then
    S3_REGION="us-east-1"
  fi

  # Save s3 options if it's succesful (First run case)
  _saveaccountconf S3_BUCKET "$S3_BUCKET"
  _saveaccountconf S3_REGION "$S3_REGION"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _debug S3_BUCKET "$S3_BUCKET"
  _debug AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"
  _debug AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"
  
  # REMOVE BEFORE COMMIT, ONLY FOR DEBUGGING
  _aws_cli_installed=1

  _info "Deploying certificate to s3 bucket: $S3_BUCKET in $S3_REGION"
  
  if [ "$_aws_cli_installed" -eq "0" ]; then
    _debug "deploying with curl method"
  else
    _debug "deploying with aws cli method"
  fi

  # private
  _deploy_to_bucket $_ckey "$_cdomain/$_cdomain.key"
  # public
  _deploy_to_bucket $_ccert "$_cdomain/$_cdomain.cer"
  # ca
  _deploy_to_bucket $_cca "$_cdomain/ca.cer"
  # fullchain
  _deploy_to_bucket $_cfullchain "$_cdomain/fullchain.cer"

  return 0

}

####################  Private functions below ##################################

_deploy_to_bucket() {
  if [ "$_aws_cli_installed" -eq "0" ]; then
    _deploy_with_curl $1 $2
  else
    _deploy_with_awscli $1 $2
  fi
}

_deploy_with_awscli() {
  file="$1"
  bucket="$S3_BUCKET"
  prefix="$2"
  region="$S3_REGION"

  aws s3 cp "$file" s3://"$bucket"/"$prefix" --region "$region"
}

_deploy_with_curl() {

  file="${1}"
  bucket="${S3_BUCKET}"
  prefix="${2}"
  region="${S3_REGION}"
  acl="private"
  timestamp="$(date -u "+%Y-%m-%d %H:%M:%S")"
  signed_headers="date;host;x-amz-acl;x-amz-content-sha256;x-amz-date"

  if [[ $(uname) == "Darwin" ]]; then
    iso_timestamp=$(date -ujf "%Y-%m-%d %H:%M:%S" "${timestamp}" "+%Y%m%dT%H%M%SZ")
    date_scope=$(date -ujf "%Y-%m-%d %H:%M:%S" "${timestamp}" "+%Y%m%d")
    date_header=$(date -ujf "%Y-%m-%d %H:%M:%S" "${timestamp}" "+%a, %d %h %Y %T %Z")
  else
    iso_timestamp=$(date -ud "${timestamp}" "+%Y%m%dT%H%M%SZ")
    date_scope=$(date -ud "${timestamp}" "+%Y%m%d")
    date_header=$(date -ud "${timestamp}" "+%a, %d %h %Y %T %Z")
  fi

  _info "Uploading $S3_BUCKET/$prefix"

  curl \
    -T "${file}" \
    -H "Authorization: AWS4-HMAC-SHA256 Credential=${AWS_ACCESS_KEY_ID}/${date_scope}/${region}/s3/aws4_request,SignedHeaders=${signed_headers},Signature=$(_signature)" \
    -H "Date:${date_header}" \
    -H "x-amz-acl:${acl}" \
    -H "x-amz-content-sha256:$(_payload_hash)" \
    -H "x-amz-date:${iso_timestamp}" \
    "https://${bucket}.s3.${region}.amazonaws.com/${prefix}"

}

_payload_hash() {
  local output=$(shasum -ba 256 "$file")
  echo "${output%% *}"
}

_canonical_request() {
  echo "PUT"
  echo "/${prefix}"
  echo ""
  echo "date:${date_header}"
  echo "host:${bucket}.s3.${region}.amazonaws.com"
  echo "x-amz-acl:${acl}"
  echo "x-amz-content-sha256:$(_payload_hash)"
  echo "x-amz-date:${iso_timestamp}"
  echo ""
  echo "${signed_headers}"
  printf "$(_payload_hash)"
}

_canonical_request_hash() {
  local output=$(_canonical_request | shasum -a 256)
  echo "${output%% *}"
}

_string_to_sign() {
  echo "AWS4-HMAC-SHA256"
  echo "${iso_timestamp}"
  echo "${date_scope}/${region}/s3/aws4_request"
  printf "$(_canonical_request_hash)"
}

_signature_key() {
  local secret=$(printf "AWS4${AWS_SECRET_ACCESS_KEY?}" | _hex_key)
  local date_key=$(printf ${date_scope} | _hmac_sha256 "${secret}" | _hex_key)
  local region_key=$(printf ${region} | _hmac_sha256 "${date_key}" | _hex_key)
  local service_key=$(printf "s3" | _hmac_sha256 "${region_key}" | _hex_key)
  printf "aws4_request" | _hmac_sha256 "${service_key}" | _hex_key
}

_hex_key() {
  hexdump -ve '1/1 "%.2x"'; echo
}

_hmac_sha256() {
  local hexkey=$1
  openssl dgst -binary -sha256 -mac HMAC -macopt hexkey:${hexkey}
}

_signature() {
  _string_to_sign | _hmac_sha256 $(_signature_key) | _hex_key | sed "s/^.* //"
}