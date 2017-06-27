#!/bin/sh

# This script deploys your cert to a s3 bucket.
# export S3_BUCKET=acme
# export S3_REGION=eu-central-1
# export AWS_PROFILE=default
# export AWS_ACCESS_KEY_ID=exampleid
# export AWS_SECRET_ACCESS_KEY=examplekey
# 
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

  if [ -z "$AWS_PROFILE" ]; then
    AWS_PROFILE="default"
  fi

  if ! _exists aws; then
    _debug "AWS CLI not installed, defaulting to curl method"
    _aws_cli_installed=0
  else
    _debug "AWS CLI installed, defaulting ignoring curl method"
    _aws_cli_installed=1
    S3_REGION="$(aws configure get region --profile ${AWS_PROFILE})"
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
  _saveaccountconf AWS_PROFILE "$AWS_PROFILE"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"
  _debug S3_BUCKET "$S3_BUCKET"
  _debug AWS_PROFILE "$AWS_PROFILE"
  _secure_debug AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"
  _secure_debug AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"
  
  # REMOVE BEFORE COMMIT, ONLY FOR DEBUGGING
  _aws_cli_installed=1

  _info "Deploying certificate to s3 bucket: $S3_BUCKET in $S3_REGION"
  
  if [ "$_aws_cli_installed" -eq "0" ]; then
    _debug "deploying with curl method"
  else
    _debug "deploying with aws cli method"
  fi

  # private
  _deploy_to_bucket "$_ckey" "$_cdomain/$_cdomain.key"
  # public
  _deploy_to_bucket "$_ccert" "$_cdomain/$_cdomain.cer"
  # ca
  _deploy_to_bucket "$_cca" "$_cdomain/ca.cer"
  # fullchain
  _deploy_to_bucket "$_cfullchain" "$_cdomain/fullchain.cer"

  return 0

}

####################  Private functions below ##################################

_deploy_to_bucket() {
  if [ "$_aws_cli_installed" -eq "0" ]; then
    _deploy_with_curl "$1" "$2"
  else
    _deploy_with_awscli "$1" "$2"
  fi
}

_deploy_with_awscli() {
  file="$1"
  prefix="$2"
  aws s3 cp "$file" s3://"$S3_BUCKET"/"$prefix" --region "$S3_REGION" --profile "$AWS_PROFILE"
}

_deploy_with_curl() {

  file="${1}"
  bucket="${S3_BUCKET}"
  prefix="${2}"
  region="${S3_REGION}"
  acl="private"
  timestamp="$(date -u "+%Y-%m-%d %H:%M:%S")"
  signed_headers="date;host;x-amz-acl;x-amz-content-sha256;x-amz-date"

  if [ "$(uname)" = "Darwin" ]; then
    iso_timestamp=$(date -ujf "%Y-%m-%d %H:%M:%S" "${timestamp}" "+%Y%m%dT%H%M%SZ")
    date_scope=$(date -ujf "%Y-%m-%d %H:%M:%S" "${timestamp}" "+%Y%m%d")
    date_header=$(date -ujf "%Y-%m-%d %H:%M:%S" "${timestamp}" "+%a, %d %h %Y %T %Z")
  else
    iso_timestamp=$(date -ud "${timestamp}" "+%Y%m%dT%H%M%SZ")
    date_scope=$(date -ud "${timestamp}" "+%Y%m%d")
    date_header=$(date -ud "${timestamp}" "+%a, %d %h %Y %T %Z")
  fi

  _info "Uploading $S3_BUCKET/$prefix"

  export _H1
  export _H2
  export _H3
  export _H4
  export _H5
  
  _H1="Authorization: AWS4-HMAC-SHA256 Credential=${AWS_ACCESS_KEY_ID}/${date_scope}/${region}/s3/aws4_request,SignedHeaders=${signed_headers},Signature=$(_signature)"
  _H2="Date:${date_header}"
  _H3="x-amz-acl:${acl}"
  _H4="x-amz-content-sha256:$(_payload_hash)"
  _H5="x-amz-date:${iso_timestamp}"

  _debug2 "$(_post "${file}" "https://$bucket.s3.$region.amazonaws.com/$prefix")"
}

####################  Private functions below ##################################

_payload_hash() {
  echo "$(shasum -ba 256 "$file")%% *"
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

  _payload_hash
}

_canonical_request_hash() {
  echo "$(_canonical_request | shasum -a 256)%% *"
}

_string_to_sign() {
  echo "AWS4-HMAC-SHA256"
  echo "${iso_timestamp}"
  echo "${date_scope}/${region}/s3/aws4_request"
  _canonical_request_hash
}

_signature_key() {
  secret_key=$(echo "AWS4${AWS_SECRET_ACCESS_KEY?}" | _hex_dump)
  date_key=$(echo "${date_scope}" | _hmac "sha256" "${secret_key}" hex | _hex_dump)
  region_key=$(echo "${region}" | _hmac "sha256" "${date_key}" hex | _hex_dump)
  service_key=$(echo "s3" | _hmac "sha256" "${region_key}" hex | _hex_dump)
  printf "aws4_request" | _hmac "sha256" "${service_key}" hex | _hex_dump
}

_signature() {
  _string_to_sign | _hmac "sha256" "$(_signature_key)" | _hex_dump | sed "s/^.* //"
}
