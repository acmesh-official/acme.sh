#!/usr/bin/env sh

#
#AWS_ACCESS_KEY_ID="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#AWS_SECRET_ACCESS_KEY="xxxxxxx"
#
#AWS_SES_REGION="us-east-1"
#
#AWS_SES_TO="xxxx@xxx.com"
#
#AWS_SES_FROM="xxxx@cccc.com"
#
#AWS_SES_FROM_NAME="Something something"
#This is the Amazon SES api wrapper for acme.sh
AWS_WIKI="https://docs.aws.amazon.com/ses/latest/dg/send-email-api.html"

aws_ses_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped
  _debug "_statusCode" "$_statusCode"

  AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$(_readaccountconf_mutable AWS_ACCESS_KEY_ID)}"
  AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$(_readaccountconf_mutable AWS_SECRET_ACCESS_KEY)}"
  AWS_SES_REGION="${AWS_SES_REGION:-$(_readaccountconf_mutable AWS_SES_REGION)}"

  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    _use_container_role || _use_instance_role
  fi

  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_ACCESS_KEY_ID=""
    AWS_SECRET_ACCESS_KEY=""
    _err "You haven't specified the aws SES api key id and and api key secret yet."
    _err "Please create your key and try again. see $(__green $AWS_WIKI)"
    return 1
  fi

  if [ -z "$AWS_SES_REGION" ]; then
    AWS_SES_REGION=""
    _err "You haven't specified the aws SES api region yet."
    _err "Please specify your region and try again. see https://docs.aws.amazon.com/general/latest/gr/ses.html"
    return 1
  fi
  _saveaccountconf_mutable AWS_SES_REGION "$AWS_SES_REGION"

  #save for future use, unless using a role which will be fetched as needed
  if [ -z "$_using_role" ]; then
    _saveaccountconf_mutable AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"
    _saveaccountconf_mutable AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"
  fi

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

  AWS_SES_FROM_NAME="${AWS_SES_FROM_NAME:-$(_readaccountconf_mutable AWS_SES_FROM_NAME)}"
  _saveaccountconf_mutable AWS_SES_FROM_NAME "$AWS_SES_FROM_NAME"

  AWS_SES_SENDFROM="$AWS_SES_FROM_NAME <$AWS_SES_FROM>"

  AWS_SES_ACTION="Action=SendEmail"
  AWS_SES_SOURCE="Source=$AWS_SES_SENDFROM"
  AWS_SES_TO="Destination.ToAddresses.member.1=$AWS_SES_TO"
  AWS_SES_SUBJECT="Message.Subject.Data=$_subject"
  AWS_SES_MESSAGE="Message.Body.Text.Data=$_content"

  _data="${AWS_SES_ACTION}&${AWS_SES_SOURCE}&${AWS_SES_TO}&${AWS_SES_SUBJECT}&${AWS_SES_MESSAGE}"

  response="$(aws_rest POST "" "" "$_data")"
}

_use_metadata() {
  _aws_creds="$(
    _get "$1" "" 1 |
      _normalizeJson |
      tr '{,}' '\n' |
      while read -r _line; do
        _key="$(echo "${_line%%:*}" | tr -d '"')"
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

  aws_host="email.$AWS_SES_REGION.amazonaws.com"
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

  Region="$AWS_SES_REGION"
  Service="ses"

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

  url="https://$aws_host/$ep"
  if [ "$qsr" ]; then
    url="https://$aws_host/$ep?$qsr"
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
}
