#!/usr/bin/env sh

#
#AWS_ACCESS_KEY_ID="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#AWS_SECRET_ACCESS_KEY="xxxxxxx"

#This is the Amazon Route53 api wrapper for acme.sh

AWS_HOST="route53.amazonaws.com"
AWS_URL="https://$AWS_HOST"

AWS_WIKI="https://github.com/Neilpang/acme.sh/wiki/How-to-use-Amazon-Route53-API"

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_aws_add() {
  fulldomain=$1
  txtvalue=$2

  if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    AWS_ACCESS_KEY_ID=""
    AWS_SECRET_ACCESS_KEY=""
    _err "You don't specify aws route53 api key id and and api key secret yet."
    _err "Please create you key and try again. see $(__green $AWS_WIKI)"
    return 1
  fi

  _saveaccountconf AWS_ACCESS_KEY_ID "$AWS_ACCESS_KEY_ID"
  _saveaccountconf AWS_SECRET_ACCESS_KEY "$AWS_SECRET_ACCESS_KEY"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _aws_tmpl_xml="<ChangeResourceRecordSetsRequest xmlns=\"https://route53.amazonaws.com/doc/2013-04-01/\"><ChangeBatch><Changes><Change><Action>UPSERT</Action><ResourceRecordSet><Name>$fulldomain</Name><Type>TXT</Type><TTL>300</TTL><ResourceRecords><ResourceRecord><Value>\"$txtvalue\"</Value></ResourceRecord></ResourceRecords></ResourceRecordSet></Change></Changes></ChangeBatch></ChangeResourceRecordSetsRequest>"

  if aws_rest POST "2013-04-01$_domain_id/rrset/" "" "$_aws_tmpl_xml" && _contains "$response" "ChangeResourceRecordSetsResponse"; then
    _info "txt record updated success."
    return 0
  fi

  return 1
}

#fulldomain txtvalue
dns_aws_rm() {
  fulldomain=$1
  txtvalue=$2

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _aws_tmpl_xml="<ChangeResourceRecordSetsRequest xmlns=\"https://route53.amazonaws.com/doc/2013-04-01/\"><ChangeBatch><Changes><Change><Action>DELETE</Action><ResourceRecordSet><ResourceRecords><ResourceRecord><Value>\"$txtvalue\"</Value></ResourceRecord></ResourceRecords><Name>$fulldomain.</Name><Type>TXT</Type><TTL>300</TTL></ResourceRecordSet></Change></Changes></ChangeBatch></ChangeResourceRecordSetsRequest>"

  if aws_rest POST "2013-04-01$_domain_id/rrset/" "" "$_aws_tmpl_xml" && _contains "$response" "ChangeResourceRecordSetsResponse"; then
    _info "txt record deleted success."
    return 0
  fi

  return 1

}

####################  Private functions below ##################################

_get_root() {
  domain=$1
  i=2
  p=1

  if aws_rest GET "2013-04-01/hostedzone"; then
    _debug "response" "$response"
    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f $i-100)
      if [ -z "$h" ]; then
        #not valid
        return 1
      fi

      if _contains "$response" "<Name>$h.</Name>"; then
        hostedzone="$(echo "$response" | sed 's/<HostedZone>/\n&/g' | _egrep_o "<HostedZone>.*<Name>$h.<.Name>.*<.HostedZone>")"
        _debug hostedzone "$hostedzone"
        if [ -z "$hostedzone" ]; then
          _err "Error, can not get hostedzone."
          return 1
        fi
        _domain_id=$(printf "%s\n" "$hostedzone" | _egrep_o "<Id>.*<.Id>" | head -n 1 | _egrep_o ">.*<" | tr -d "<>")
        if [ "$_domain_id" ]; then
          _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
          _domain=$h
          return 0
        fi
        return 1
      fi
      p=$i
      i=$(_math "$i" + 1)
    done
  fi
  return 1
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

  _H1="x-amz-date: $RequestDate"

  aws_host="$AWS_HOST"
  CanonicalHeaders="host:$aws_host\nx-amz-date:$RequestDate\n"
  _debug2 CanonicalHeaders "$CanonicalHeaders"

  SignedHeaders="host;x-amz-date"
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

  _debug2 kSecret "$kSecret"

  kSecretH="$(_hex "$kSecret")"
  _debug2 kSecretH "$kSecretH"

  kDateH="$(printf "$RequestDateOnly%s" | _hmac "$Hash" "$kSecretH" hex)"
  _debug2 kDateH "$kDateH"

  kRegionH="$(printf "$Region%s" | _hmac "$Hash" "$kDateH" hex)"
  _debug2 kRegionH "$kRegionH"

  kServiceH="$(printf "$Service%s" | _hmac "$Hash" "$kRegionH" hex)"
  _debug2 kServiceH "$kServiceH"

  kSigningH="$(printf "aws4_request%s" | _hmac "$Hash" "$kServiceH" hex)"
  _debug2 kSigningH "$kSigningH"

  signature="$(printf "$StringToSign%s" | _hmac "$Hash" "$kSigningH" hex)"
  _debug2 signature "$signature"

  Authorization="$Algorithm Credential=$AWS_ACCESS_KEY_ID/$CredentialScope, SignedHeaders=$SignedHeaders, Signature=$signature"
  _debug2 Authorization "$Authorization"

  _H3="Authorization: $Authorization"
  _debug _H3 "$_H3"

  url="$AWS_URL/$ep"

  if [ "$mtd" = "GET" ]; then
    response="$(_get "$url")"
  else
    response="$(_post "$data" "$url")"
  fi

  _ret="$?"
  if [ "$_ret" = "0" ]; then
    if _contains "$response" "<ErrorResponse"; then
      _err "Response error:$response"
      return 1
    fi
  fi

  return "$_ret"
}
