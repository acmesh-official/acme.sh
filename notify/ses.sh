#!/usr/bin/env sh

#Support Amazon SES api

#AWS_ACCESS_KEY_ID=""
#AWS_SECRET_ACCESS_KEY=""
#AWS_REGION=""
#AWS_SES_TO="xxxx@xxx.com"
#AWS_SES_FROM="xxxx@cccc.com"

ses_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$(_readaccountconf_mutable AWS_ACCESS_KEY_ID)}"
  if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    AWS_ACCESS_KEY_ID=""
    _err "You didn't specify a amazon access key AWS_ACCESS_KEY_ID yet."
    _err "See https://docs.aws.amazon.com/en_us/general/latest/gr/aws-sec-cred-types.html"
    return 1
  fi
  _saveaccountconf_mutable AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"

  AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$(_readaccountconf_mutable AWS_SECRET_ACCESS_KEY)}"
  if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_SECRET_ACCESS_KEY=""
    _err "You didn't specify a amazon secret key AWS_SECRET_ACCESS_KEY yet."
    _err "See https://docs.aws.amazon.com/en_us/general/latest/gr/aws-sec-cred-types.html"
    return 1
  fi
  _saveaccountconf_mutable AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"

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

  _host="email.$AWS_REGION.amazonaws.com"
  _endpoint="https://$_host"
  _data="Action=SendEmail&Source=$(printf "%s" "$AWS_SES_FROM" | _url_encode)&Destination.ToAddresses.member.1=$(printf "%s" "$AWS_SES_TO" | _url_encode)&Message.Subject.Data=$(printf "%s" "$_subject" | _url_encode)&Message.Body.Text.Data=$(printf "%s" "$_content" | _url_encode)"

  Service="ses"
  Hash="sha256"

  Algorithm="AWS4-HMAC-SHA256"
  _debug2 Algorithm "$Algorithm"

  RequestDate="$(date -u +"%Y%m%dT%H%M%SZ")"
  RequestDateOnly="$(echo "$RequestDate" | cut -c 1-8)"
  _debug2 RequestDateOnly "$RequestDateOnly"

  CredentialScope="$RequestDateOnly/$AWS_REGION/$Service/aws4_request"
  _debug2 StringToSign "$StringToSign"

  CanonicalHeaders="host:$_host\nx-amz-date:$RequestDate\n"
  _debug2 CanonicalHeaders "$CanonicalHeaders"

  SignedHeaders="host;x-amz-date"
  _debug2 SignedHeaders "$SignedHeaders"

  CanonicalRequest="POST\n/\n\n$CanonicalHeaders\n$SignedHeaders\n$(printf "%s" "$_data" | _digest "$Hash" hex)"
  _debug2 CanonicalRequest "$CanonicalRequest"

  HashedCanonicalRequest="$(printf "$CanonicalRequest%s" | _digest "$Hash" hex)"
  _debug2 HashedCanonicalRequest "$HashedCanonicalRequest"

  StringToSign="$Algorithm\n$RequestDate\n$CredentialScope\n$HashedCanonicalRequest"
  _debug2 StringToSign "$StringToSign"

  kSecret="AWS4$AWS_SECRET_ACCESS_KEY"

  kSecretH="$(printf "%s" "$kSecret" | _hex_dump | tr -d " ")"
  _secure_debug2 kSecretH "$kSecretH"

  kDateH="$(printf "$RequestDateOnly%s" | _hmac "$Hash" "$kSecretH" hex)"
  _debug2 kDateH "$kDateH"

  kRegionH="$(printf "$AWS_REGION%s" | _hmac "$Hash" "$kDateH" hex)"
  _debug2 kRegionH "$kRegionH"

  kServiceH="$(printf "$Service%s" | _hmac "$Hash" "$kRegionH" hex)"
  _debug2 kServiceH "$kServiceH"

  kSigningH="$(printf "%s" "aws4_request" | _hmac "$Hash" "$kServiceH" hex)"
  _debug2 kSigningH "$kSigningH"

  signature="$(printf "$StringToSign%s" | _hmac "$Hash" "$kSigningH" hex)"
  _debug2 signature "$signature"

  Authorization="$Algorithm Credential=$AWS_ACCESS_KEY_ID/$CredentialScope, SignedHeaders=$SignedHeaders, Signature=$signature"
  _debug2 Authorization "$Authorization"

  export _H1="x-amz-date: $RequestDate"
  export _H2="Authorization: $Authorization"

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
