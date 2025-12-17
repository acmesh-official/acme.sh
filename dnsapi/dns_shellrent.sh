#!/usr/bin/env sh

#SH_Token="xxxx"
#SH_Username="xxxx"
#SH_Domain_ID="xxxx"
#SH_DNS_Record_ID="xxxx"  only for internal use

SH_Api="https://manager.shellrent.com/api2"

########  Public functions #####################

#Usage: add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_shellrent_add() {
  fulldomain=$1
  txtvalue=$2

  SH_Token="${SH_Token:-$(_readaccountconf_mutable SH_Token)}"
  SH_Username="${SH_Username:-$(_readaccountconf_mutable SH_Username)}"
  SH_Domain_ID="${SH_Domain_ID:-$(_readaccountconf_mutable SH_Domain_ID)}"

  if [ "$SH_Token" ]; then
    _saveaccountconf_mutable SH_Token "$SH_Token"
    _saveaccountconf_mutable SH_Username "$SH_Username"
    _saveaccountconf_mutable SH_Domain_ID "$SH_Domain_ID"
  else
    if [ -z "$SH_Token" ] || [ -z "$SH_Username" ]; then
      SH_Token=""
      SH_Username=""
      _err "You didn't specify a Shellrent api key and username yet."
      _err "You can get yours from here https://manager.shellrent.com/"
      return 1
    fi

    #save the api key and email to the account conf file.
    _saveaccountconf_mutable SH_Token "$SH_Token"
    _saveaccountconf_mutable SH_Username "$SH_Username"
  fi

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _fulldomain "$fulldomain"
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _prefix=$(echo "$fulldomain" | sed "s/.$_domain//g" )

  _debug _prefix "$_prefix"

  _debug "Getting records ids"
  _shellrent_rest GET "/dns_record/index/${_domain_id}"
  
  if ! echo "$response" | tr -d " " | grep \"error\":0 >/dev/null; then
    _err "Error"
    return 1
  fi

  # get dns records list
  _dns_record_list=$( echo "$response" | cut -d'[' -f2 | cut -d']' -f1 | sed 's/,\?"/ /g' )
  _debug _dns_record_list "$_dns_record_list"

  for _dns_record in $_dns_record_list; do
    _shellrent_rest GET "/dns_record/details/$_domain_id/$_dns_record"
    _dns_record_type=$( echo "$response" | sed 's/type/#/g' | cut -d"#" -f2 | cut -d"\"" -f3 )
    _debug _dns_record_type "$_dns_record_type"
    _dns_record_prefix=$( echo "$response" | sed 's/host/#/g' | cut -d"#" -f2 | cut -d"\"" -f3 )
    _debug _dns_record_prefix "$_dns_record_prefix"
    _dns_record_destination=$( echo "$response" | sed 's/destination/#/g' | cut -d"#" -f2 | cut -d"\"" -f3 )
    _debug _dns_record_destination "$_dns_record_destination"
    if [ "$_dns_record_type" = "TXT" ] && [ "$_dns_record_prefix" = "$_prefix" ] && [ "$_dns_record_destination" = "$txtvalue" ]; then
      _info "Already exists, OK"
      _saveaccountconf_mutable SH_DNS_Record_ID "$_dns_record"
      return 0
    fi
  done

   _info "Adding record"
  if _shellrent_rest POST "/dns_record/store/$_domain_id" "{\"type\":\"TXT\",\"host\":\"$_prefix\",\"destination\":\"$txtvalue\"}"; then
    if _contains "$response" "aggiunto con successo"; then
      _info "Added, OK"
      _dns_record=$( echo "$response" | sed 's/id/#/g' | cut -d"#" -f2 | cut -d"\"" -f3 )
      _debug _dns_record "$_dns_record"
      _saveaccountconf_mutable SH_DNS_Record_ID "$_dns_record"
      return 0
    else
      _err "Add txt record error."
      return 1
    fi
  fi
  _err "Add txt record error."
  return 1

}

#fulldomain txtvalue
dns_shellrent_rm() {
  fulldomain=$1
  txtvalue=$2

  SH_Token="${SH_Token:-$(_readaccountconf_mutable SH_Token)}"
  SH_Username="${SH_Username:-$(_readaccountconf_mutable SH_Username)}"
  SH_Domain_ID="${SH_Domain_ID:-$(_readaccountconf_mutable SH_Domain_ID)}"
  SH_DNS_Record_ID="${SH_DNS_Record_ID:-$(_readaccountconf_mutable SH_DNS_Record_ID)}"

  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _fulldomain "$fulldomain"
  _debug _domain_id "$_domain_id"
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"

  _prefix=$(echo "$fulldomain" | sed "s/.$_domain//g" )

  _debug _prefix "$_prefix"

 if [ "$SH_DNS_Record_ID" ]; then
    if _shellrent_rest GET "/dns_record/details/$SH_Domain_ID/$SH_DNS_Record_ID"; then
      if echo "$response" | tr -d " " | grep \"error\":0 >/dev/null; then
        _info "Record Fount. Try to delete it"
        _shellrent_rest DELETE "/dns_record/remove/$SH_Domain_ID/$SH_DNS_Record_ID"
        return 0
      else
        _Info "Record NOT Found. Try to search on all records"
      fi
    fi
  fi

  _debug "Getting records ids"
  _shellrent_rest GET "/dns_record/index/${_domain_id}"
  
  if ! echo "$response" | tr -d " " | grep \"error\":0 >/dev/null; then
    _err "Error"
    return 1
  fi

  # get dns records list
  _dns_record_list=$( echo "$response" | cut -d'[' -f2 | cut -d']' -f1 | sed 's/,\?"/ /g' )
  _debug _dns_record_list "$_dns_record_list"

  for _dns_record in $_dns_record_list; do
    _shellrent_rest GET "/dns_record/details/$_domain_id/$_dns_record"
    _dns_record_type=$( echo "$response" | sed 's/type/#/g' | cut -d"#" -f2 | cut -d"\"" -f3 )
    _debug _dns_record_type "$_dns_record_type"
    _dns_record_prefix=$( echo "$response" | sed 's/host/#/g' | cut -d"#" -f2 | cut -d"\"" -f3 )
    _debug _dns_record_prefix "$_dns_record_prefix"
    _dns_record_destination=$( echo "$response" | sed 's/destination/#/g' | cut -d"#" -f2 | cut -d"\"" -f3 )
    _debug _dns_record_destination "$_dns_record_destination"
    if [ "$_dns_record_type" = "TXT" ] && [ "$_dns_record_prefix" = "$_prefix" ] && [ "$_dns_record_destination" = "$txtvalue" ]; then
      _info "Remove Record With ID $_dns_record"
      _shellrent_rest DELETE "/dns_record/remove/$_domain_id/$_dns_record"
      if ! echo "$response" | tr -d " " | grep \"error\":0 >/dev/null; then
        _err "Error on Record Delete"
        return 1
      fi
      return 0
    fi
  done

  _err "Del txt record error."
  return 1
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
# _domain_id=sdjkglgdfewsdfg
_get_root() {
  _domain=$1

  # Use Zone ID directly if provided
  if [ "$SH_Domain_ID" ]; then
    if ! _shellrent_rest GET "/domain/details/$SH_Domain_ID"; then
      return 1
    else
      if echo "$response" | grep \"error\":0 >/dev/null; then
        _dom=$(echo "$response" | cut -d":" -f8 | cut -d"," -f1 | sed 's/"//g')
        if [ "$_dom" ]; then
          _sub_domain=$( echo "$_domain" | sed "s/$_dom//g" | sed 's/.$//g')
          _domain="$_dom"
          _domain_id=$SH_Domain_ID
          _debug _domain "$_domain"
          _debug _sub_domain "$_sub_domain"
          return 0
        else
          return 1
        fi
      else
        return 1
      fi
    fi
  fi

  _shellrent_rest GET "/purchase"

  # get puchase list
  _purchases_list=$( echo "$response" | cut -d'[' -f2 | cut -d']' -f1 | sed 's/,\?"/ /g' )
  _debug _purchases_list "$_purchases_list"

  for _purchase in $_purchases_list; do
    _shellrent_rest GET "/purchase/details/$_purchase"
    # if the purchse have the domain_id value, is a domain
    if [ "$(echo "$response" | grep -c domain_id )" -eq 1 ]; then
      _debug _is_domain "true"
      _domain_id=$( echo "$response" | sed 's/domain_id/#/g' | cut -d"#" -f2 | sed 's/"\?://g' | sed 's/}//g' )
      _debug _domain_id "$_domain_id"
      # get the domain details
      _shellrent_rest GET "/domain/details/$_domain_id"
      _api_domain_name=$( echo "$response" | cut -d":" -f8 | cut -d"," -f1 | sed 's/"//g' )
      _debug _api_domain_name "$_api_domain_name"
      # first check if _domain partially match with the purchase domain
      if _contains "$_domain" "$_api_domain_name" ; then
        _debug _domain_found "maybe"
        _i=1
        _dom="$_domain"
        #wal thru "point" to get the domain and the subdomain
        while [ -n "$_dom" ]; do
          _dom=$(echo "$_domain" | cut -d . -f $_i-100)
          _debug _dom "$_dom"
          if [ "$_dom" = "$_api_domain_name" ]; then
            _sub_domain=$( echo "$_domain" | sed "s/$_dom//g" | sed 's/.$//g')
            _domain="$_dom"
            _debug _domain_found "true"
            _debug _domain "$_domain"
            _debug _sub_domain "$_sub_domain"
            _saveaccountconf_mutable SH_Domain_ID "$_domain_id"
            return 0
          fi
          _i=$(_math "$_i" + 1)
        done
      else
        _debug _domain_found "false"
      fi
    else
      _debug _is_domain "false"
    fi
  done

  return 1
}

_shellrent_rest() {
  m=$1
  ep="$2"
  data="$3"
  _debug "$ep"

  export _H1="Content-Type: application/json"

  export _H2="Authorization: $SH_Username.$SH_Token"


  if [ "$m" != "GET" ]; then
    _debug data "$data"
    response="$(_post "$data" "$SH_Api$ep" "" "$m")"
    _response_result=$?
  else
    response="$(_get "$SH_Api$ep")"
    _response_result=$?
  fi

  if [ "$_response_result" != "0" ]; then
    _err "error $ep"
    return 1
  fi
  _debug2 response "$response"
  return 0
}
