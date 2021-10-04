#!/usr/bin/env sh

#
#AWS_ACCESS_KEY_ID="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#AWS_SECRET_ACCESS_KEY="xxxxxxx"

#This is the Amazon Route53 api wrapper for acme.sh
#All `_sleep` commands are included to avoid Route53 throttling, see
#https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/DNSLimitations.html#limits-api-requests

AWS_WIKI="https://github.com/acmesh-official/acme.sh/wiki/How-to-use-Amazon-Route53-API"

# shellcheck source=common/aws.sh
. "$LE_WORKING_DIR/common/aws.sh"

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_aws_add() {
  fulldomain=$1
  txtvalue=$2

  AWS_DNS_SLOWRATE="${AWS_DNS_SLOWRATE:-$(_readaccountconf_mutable AWS_DNS_SLOWRATE)}"

  if ! _aws_auth; then
    _err "You haven't specifed the aws route53 api key id and and api key secret yet."
    _err "Please create your key and try again. see $(__green $AWS_WIKI)"
    return 1
  fi

  _saveaccountconf_mutable AWS_DNS_SLOWRATE "$AWS_DNS_SLOWRATE"

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
  response="$(_aws r53 GET "/2013-04-01$_domain_id/rrset" "name=$fulldomain&type=TXT")"
  if [ "$?" -gt 0 ]; then
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

  response="$(_aws r53 POST "/2013-04-01$_domain_id/rrset/" "" "$_aws_tmpl_xml")"
  if [ "$?" -eq 0 ] && _contains "$response" "ChangeResourceRecordSetsResponse"; then
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

  AWS_DNS_SLOWRATE="${AWS_DNS_SLOWRATE:-$(_readaccountconf_mutable AWS_DNS_SLOWRATE)}"

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
  response="$(_aws r53 GET "/2013-04-01$_domain_id/rrset" "name=$fulldomain&type=TXT")"
  if [ "$?" -gt 0 ]; then
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

  response="$(_aws r53 POST "/2013-04-01$_domain_id/rrset/" "" "$_aws_tmpl_xml")"
  if [ "$?" -eq 0 ] && _contains "$response" "ChangeResourceRecordSetsResponse"; then
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
  i=2
  p=1

  response="$(_aws r53 GET '/2013-04-01/hostedzone')"
  if [ "$?" -eq 0 ]; then
    while true; do
      h=$(printf "%s" "$domain" | cut -d . -f $i-100)
      _debug2 "Checking domain: $h"
      if [ -z "$h" ]; then
        if _contains "$response" "<IsTruncated>true</IsTruncated>" && _contains "$response" "<NextMarker>"; then
          _debug "IsTruncated"
          _nextMarker="$(echo "$response" | _egrep_o "<NextMarker>.*</NextMarker>" | cut -d '>' -f 2 | cut -d '<' -f 1)"
          _debug "NextMarker" "$_nextMarker"
          response="$(_aws r53 GET '/2013-04-01/hostedzone' "marker=$_nextMarker")"
          if [ "$?" -eq 0 ]; then
            _debug "Truncated request OK"
            i=2
            p=1
            continue
          else
            _err "Truncated request error."
          fi
        fi
        #not valid
        _err "Invalid domain"
        return 1
      fi

      if _contains "$response" "<Name>$h.</Name>"; then
        hostedzone="$(echo "$response" | sed 's/<HostedZone>/#&/g' | tr '#' '\n' | _egrep_o "<HostedZone><Id>[^<]*<.Id><Name>$h.<.Name>.*<PrivateZone>false<.PrivateZone>.*<.HostedZone>")"
        _debug hostedzone "$hostedzone"
        if [ "$hostedzone" ]; then
          _domain_id=$(printf "%s\n" "$hostedzone" | _egrep_o "<Id>.*<.Id>" | head -n 1 | _egrep_o ">.*<" | tr -d "<>")
          if [ "$_domain_id" ]; then
            _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
            _domain=$h
            return 0
          fi
          _err "Can't find domain with id: $h"
          return 1
        fi
      fi
      p=$i
      i=$(_math "$i" + 1)
    done
  fi
  return 1
}
