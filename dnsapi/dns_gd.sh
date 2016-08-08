#!/usr/bin/env sh

#Godaddy domain api
#
#GD_Key="sdfsdfsdfljlbjkljlkjsdfoiwje"
#
#GD_Secret="asdfsdfsfsdfsdfdfsdf"


GD_Api="https://api.godaddy.com/v1"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_gd_add(){
  fulldomain=$1
  txtvalue=$2
  
  if [ -z "$GD_Key" ] || [ -z "$GD_Secret" ] ; then
    _err "You don't specify godaddy api key and secret yet."
    _err "Please create you key and try again."
    return 1
  fi
  
  #save the api key and email to the account conf file.
  _saveaccountconf GD_Key "$GD_Key"
  _saveaccountconf GD_Secret "$GD_Secret"
  
  _debug "First detect the root zone"
  if ! _get_root $fulldomain ; then
    _err "invalid domain"
    return 1
  fi
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  

  _info "Adding record"
  if _gd_rest PUT "domains/$_domain/records/TXT/$_sub_domain"  "[{\"data\":\"$txtvalue\"}]"; then
    if [ "$response" = "{}" ] ; then
      _info "Added, sleeping 10 seconds"
      sleep 10
      #todo: check if the record takes effect
      return 0
    else
      _err "Add txt record error."
      _err "$response"
      return 1
    fi
  fi
  _err "Add txt record error."
  
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
    
    if ! _gd_rest GET "domains/$h" ; then
      return 1
    fi
    
    if printf "$response" | grep '"code":"NOT_FOUND"' >/dev/null ; then
      _debug "$h not found"
    else
      _sub_domain=$(printf $domain | cut -d . -f 1-$p)
      _domain=$h
      return 0
    fi
    p=$i
    i=$(expr $i + 1)
  done
  return 1
}

_gd_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug $ep
  
  _H1="Authorization: sso-key $GD_Key:$GD_Secret"
  _H2="Content-Type: application/json"
  
  if [ "$data" ] ; then
    _debug data "$data"
    response="$(_post "$data" "$GD_Api/$ep" "" $m)"
  else
    response="$(_get "$GD_Api/$ep")"
  fi
  
  if [ "$?" != "0" ] ; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}


