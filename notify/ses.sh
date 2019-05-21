#!/usr/bin/env sh

#Support Amazon SES api

#AWS_ACCESS_KEY=""
#AWS_SECRET_KEY=""
#AWS_REGION=""
#AWS_SES_TO="xxxx@xxx.com"
#AWS_SES_FROM="xxxx@cccc.com"

ses_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  AWS_ACCESS_KEY="${AWS_ACCESS_KEY:-$(_readaccountconf_mutable AWS_ACCESS_KEY)}"
  if [ -z "$AWS_ACCESS_KEY" ]; then
    AWS_ACCESS_KEY=""
    _err "You didn't specify a amazon access key AWS_ACCESS_KEY yet."
    _err "See https://docs.aws.amazon.com/en_us/general/latest/gr/aws-sec-cred-types.html"
    return 1
  fi
  _saveaccountconf_mutable AWS_ACCESS_KEY "$AWS_ACCESS_KEY"

  AWS_SECRET_KEY="${AWS_SECRET_KEY:-$(_readaccountconf_mutable AWS_SECRET_KEY)}"
  if [ -z "$AWS_SECRET_KEY" ]; then
    AWS_SECRET_KEY=""
    _err "You didn't specify a amazon secret key AWS_SECRET_KEY yet."
    _err "See https://docs.aws.amazon.com/en_us/general/latest/gr/aws-sec-cred-types.html"
    return 1
  fi
  _saveaccountconf_mutable AWS_SECRET_KEY "$AWS_SECRET_KEY"

  AWS_REGION="${AWS_REGION:-$(_readaccountconf_mutable AWS_REGION)}"
  if [ -z "$AWS_REGION" ]; then
    AWS_REGION=""
    _err "You didn't specify the AWS_REGION."
    return 1
  fi
  AWS_REGION="$(echo "$AWS_REGION" | _lower_case)"
  _saveaccountconf_mutable AWS_REGION "$AWS_REGION"

  AWS_SES_TO="${AWS_SES_TO:-$(_readaccountconf_mutable AWS_SES_TO)}"
  if [ -z "$AWS_SES_TO" ]; then
    AWS_SES_TO=""
    _err "You didn't specify an email to AWS_SES_TO receive messages."
    return 1
  fi
  _saveaccountconf_mutable AWS_SES_TO "$AWS_SES_TO"

  AWS_SES_FROM="${AWS_SES_FROM:-$(_readaccountconf_mutable AWS_SES_FROM)}"
  if [ -z "$AWS_SES_FROM" ]; then
    AWS_SES_FROM=""
    _err "You didn't specify an email to AWS_SES_FROM receive messages."
    return 1
  fi
  _saveaccountconf_mutable AWS_SES_FROM "$AWS_SES_FROM"

  _date="$(date -R)"
  _signature="$(echo -n "$_date" | _openssl_bin dgst -sha256 -hmac "$AWS_SECRET_KEY" -binary | _base64 -w 0)"
  _endpoint="https://email.$AWS_REGION.amazonaws.com/"

  export _H1="X-Amzn-Authorization: AWS3-HTTPS AWSAccessKeyId=$AWS_ACCESS_KEY, Algorithm=HmacSHA256, Signature=$_signature"
  export _H2="Content-Type: application/x-www-form-urlencoded"
  export _H3="Date: $_date"

  _data="Action=SendEmail&Source=$(printf "%s" "$AWS_SES_FROM" | _url_encode)&Destination.ToAddresses.member.1=$(printf "%s" "$AWS_SES_TO" | _url_encode)&Message.Subject.Data=$(printf "%s" "$_subject" | _url_encode)&Message.Body.Text.Data=$(printf "%s" "$_content" | _url_encode)"

  response=$(_post "$_data" "$_endpoint")
  if _contains "$response" "MessageId"; then
    _debug "Amazon SES send success."
    return 0
  else
    _err "Amazon SES send error"
    _err "$response"
    return 1
  fi

}
