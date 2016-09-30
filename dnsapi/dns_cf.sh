#!/usr/bin/env sh


#
#CF_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#CF_Email="xxxx@sss.com"


CF_Api="https://api.cloudflare.com/client/v4"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_cf_add(){
  fulldomain=$1
  txtvalue=$2
  
  if [ -z "$CF_Key" ] || [ -z "$CF_Email" ] ; then
    _err "You don't specify cloudflare api key and email yet."
    _err "Please create you key and try again."
    return 1
  fi
  
  #save the api key and email to the account conf file.
  _saveaccountconf CF_Key "$CF_Key"
  _saveaccountconf CF_Email "$CF_Email"
  
  _debug "First detect the root zone"
  if ! _get_root $fulldomain ; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  
  _debug "Getting txt records"
  _cf_rest GET "zones/${_domain_id}/dns_records?type=TXT&name=$fulldomain"
  
  if ! printf "$response" | grep \"success\":true > /dev/null ; then
    _err "Error"
    return 1
  fi
  
  count=$(printf "%s\n" "$response" | _egrep_o \"count\":[^,]* | cut -d : -f 2)
  _debug count "$count"
  if [ "$count" = "0" ] ; then
    _info "Adding record"
    if _cf_rest POST "zones/$_domain_id/dns_records"  "{\"type\":\"TXT\",\"name\":\"$fulldomain\",\"content\":\"$txtvalue\",\"ttl\":120}"; then
      if printf -- "%s" "$response" | grep $fulldomain > /dev/null ; then
        _info "Added, sleeping 10 seconds"
        sleep 10
        #todo: check if the record takes effect
        return 0
      else
        _err "Add txt record error."
        return 1
      fi
    fi
    _err "Add txt record error."
  else
    _info "Updating record"
    record_id=$(printf "%s\n" "$response" | _egrep_o \"id\":\"[^\"]*\" | cut -d : -f 2 | tr -d \"| head -n 1)
    _debug "record_id" $record_id
    
    _cf_rest PUT "zones/$_domain_id/dns_records/$record_id"  "{\"id\":\"$record_id\",\"type\":\"TXT\",\"name\":\"$fulldomain\",\"content\":\"$txtvalue\",\"zone_id\":\"$_domain_id\",\"zone_name\":\"$_domain\"}"
    if [ "$?" = "0" ]; then
      _info "Updated, sleeping 10 seconds"
      sleep 10
      #todo: check if the record takes effect
      return 0;
    fi
    _err "Update error"
    return 1
  fi
  
}





####################  Private functions bellow ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  domain=$1
  i=2
  p=1
  while [ '1' ] ; do
    h=$(printf $domain | cut -d . -f $i-100)
    if [ -z "$h" ] ; then
      #not valid
      return 1;
    fi
    
    if ! _cf_rest GET "zones?name=$h" ; then
      return 1
    fi
    
    if printf $response | grep \"name\":\"$h\" >/dev/null ; then
      _domain_id=$(printf "%s\n" "$response" | _egrep_o \"id\":\"[^\"]*\" | head -n 1 | cut -d : -f 2 | tr -d \")
      if [ "$_domain_id" ] ; then
        _sub_domain=$(printf $domain | cut -d . -f 1-$p)
        _domain=$h
        return 0
      fi
      return 1
    fi
    p=$i
    i=$(expr $i + 1)
  done
  return 1
}

_cf_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug $ep
  
  _H1="X-Auth-Email: $CF_Email"
  _H2="X-Auth-Key: $CF_Key"
  _H3="Content-Type: application/json"
  
  if [ "$data" ] ; then
    _debug data "$data"
    response="$(_post "$data" "$CF_Api/$ep" "" $m)"
  else
    response="$(_get "$CF_Api/$ep")"
  fi
  
  if [ "$?" != "0" ] ; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}


