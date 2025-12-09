#!/usr/bin/env sh

#Here is a sample custom api script.
#This file name is "dns_myapi.sh"
#So, here must be a method   dns_myapi_add()
#Which will be called by acme.sh to add the txt record to your api system.
#returns 0 means success, otherwise error.
#
#Author: Neilpang
#Report Bugs here: https://github.com/Neilpang/acme.sh
#
########  Public functions #####################

# Please Read this guide first: https://github.com/Neilpang/acme.sh/wiki/DNS-API-Dev-Guide

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dnsever_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using dnsever add"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  DNSEVER_ID="${DNSEVER_ID:-$(_readaccountconf_mutable DNSEVER_ID)}"
  DNSEVER_PW="${DNSEVER_PW:-$(_readaccountconf_mutable DNSEVER_PW)}"

  if [ "$DNSEVER_ID" ]; then
    _saveaccountconf_mutable DNSEVER_ID "$DNSEVER_ID"
    _saveaccountconf_mutable DNSEVER_PW "$DNSEVER_PW"

  else
    if [ -z "$DNSEVER_ID" ] || [ -z "$DNSEVER_PW" ]; then
      DNSEVER_ID=""
      DNSEVER_PW=""
      _err "You didn't specify a DNSEVER ID and PW yet."
      return 1
    fi

  fi
  dnsever_domain_txt "add" "$DNSEVER_ID" "$DNSEVER_PW" "$fulldomain" "$txtvalue"

  #save the api key and email to the account conf file.

  return $?
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_dnsever_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using dnsever remove"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  DNSEVER_ID="${DNSEVER_ID:-$(_readaccountconf_mutable DNSEVER_ID)}"
  DNSEVER_PW="${DNSEVER_PW:-$(_readaccountconf_mutable DNSEVER_PW)}"

  if [ -z "$DNSEVER_ID" ] || [ -z "$DNSEVER_PW" ]; then
    DNSEVER_ID=""
    DNSEVER_PW=""
    return 1
  fi

  dnsever_domain_txt "del" "$DNSEVER_ID" "$DNSEVER_PW" "$fulldomain" "$txtvalue"

  return $?
}

####################  Private functions below ##################################

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com

_get_root() {
  domain=$1
  i=2
  p=1
  while true; do
    h=$(printf "%s" "$domain" | cut -d . -f $i-100)
    if [ -z "$h" ]; then
      #not valid
      return 1
    fi

    #<OPTION value="flywithu.com" selected>flywithu.com</OPTION>
    domains=$(printf "%s\n" "$response" | _egrep_o "OPTION value=\".+\"" | tr -d '\n')
    _debug2 "h" "$h"
    _debug2 "domains" "$domains"

    if _contains "$domains" "$h"; then
      _sub_domain=$(printf "%s" "$domain" | cut -d . -f 1-$p)
      _domain="$h"
      return 0
    fi
    p=$i
    i=$(_math "$i" + 1)
  done
  return 1
}

_get_check_count() {
  domain=$1
  _err "res" "$response"
}

dnsever_domain_txt() {
  action="$1"
  login_id="$2"
  login_password="$3"
  domain_name="$4"
  domain_txt="$5"

  response=$(_post "login_id=$login_id&login_password=$login_password" "https://kr.dnsever.com/index.html")
  result=$?
  if [ $result != 0 ] || [ -z "$response" ]; then
    _err "dnsever_txt:$action ERROR login failed. Please check https://kr.dnsever.com/index.html with login_id=$login_id login_password=$login_password"
    return 1
  fi

  _H1="$(grep PHPSESSID "$HTTP_HEADER" | sed s/^Set-//)"
  export _H1

  response=$(_post "" "https://kr.dnsever.com/start.html")
  result=$?
  if [ $result != 0 ] || [ -z "$response" ]; then

    _err "dnsever_txt:$action ERROR login failed. Please check https://kr.dnsever.com/start.html after login"
    return 1
  fi

  #  newhref=$(echo "$response" | sed -E "s/.*\'(.*)\'<.*/\1/")
  newhref=$(printf "%s\n" "$response" | _egrep_o "'.+'" | cut -d\' -f2)

  response=$(_post "" "$newhref")
  result=$?
  if [ $result != 0 ] || [ -z "$response" ]; then
    _err "dnsever_txt:$action ERROR login failed. Please check https://kr.dnsever.com/start.html after login"
    return 1
  fi

  #  newhref=$(echo "$response" | sed -E "s/.*action=\"(.*)\" .*/\1/")
  newhref=$(printf "%s\n" "$response" | _egrep_o "https.+\" " | cut -d\" -f1)
  response=$(_post "" "$newhref")
  result=$?
  if [ $result != 0 ] || [ -z "$response" ]; then
    _err "dnsever_txt:$action ERROR login failed. Please check https://kr.dnsever.com/start.html after login"
    return 1
  fi

  response=$(_post "" "https://kr.dnsever.com/start.html")
  result=$?
  if [ $result != 0 ] || [ -z "$response" ]; then
    _err "dnsever_txt:$action ERROR login failed. Please check https://kr.dnsever.com/start.html after login"
    return 1
  fi

  skey=$(printf "%s\n" "$response" | _egrep_o "name=\"skey\" value=\".+\"" | cut -f3 -d= | tr -d \")
  _debug skey "$skey"

  if [ -z "$skey" ]; then
    _err "dnsever_txt:$action ERROR login failed with login_id=$login_id login_password=$login_password"
    response=$(_post "skey=$skey" "https://kr.dnsever.com/logout.php")
    return 1
  fi
  _get_root "$domain_name"

  _debug2 "fulldomain" "$domain_name"
  _debug2 "domain" "$_domain"
  _debug2 "subdomain" "$_sub_domain"
  _debug2 "txt" "$domain_txt"

  if [ "$action" = "add" ]; then
    ##https://kr.dnsever.com/start.html?user_domain=flywithu.com&selected_menu=edittxt&skey=flywithu:f80f523d2254f1e2c56462ace327f256
    #   subname=$(echo "$domain_name" | sed "s/\.$user_domain\$//")

    response=$(_post "skey=$skey&user_domain=$_domain&selected_menu=edittxt&command=add_txt&subname=$_sub_domain&new_txt=$domain_txt" "https://kr.dnsever.com/start.html")

    result=$?
    if [ $result != 0 ] || [ -z "$response" ]; then
      _err "dnsever_txt:$action ERROR failed to add_text $domain_name=$domain_txt"
      response=$(_post "skey=$skey" "https://kr.dnsever.com/logout.php")

    fi
  elif [ "$action" = "del" ]; then
    #https://kr.dnsever.com/start.html?user_domain=flywithu.com&selected_menu=edittxt&skey=flywithu:41e3390a9b7aee2cce36c0012bb042b6
    response=$(_post "skey=$skey&user_domain=$_domain&selected_menu=edittxt" "https://kr.dnsever.com/start.html")
    #    _debug2 "response" "$response" |cut -d\" -f1
    seq_1=$(printf "%s\n" "$response" | _egrep_o "name=\"seq_1\" value=\".+\"" | cut -f3 -d= | tr -d \")

    response=$(_post "skey=$skey&user_domain=$_domain&selected_menu=edittxt&command=delete_txt&domain_for_txt_1=$domain_name&old_txt_1=$domain_txt&txt_1=$domain_txt&check[]=1&seq_1=$seq_1&subname=&new_txt=" "https://kr.dnsever.com/start.html")
    result=$?
    if [ $result != 0 ] || [ -z "$response" ]; then

      _err "dnsever_txt:$action ERROR failed to delete $domain_name=$domain_txt from DNSEver"
      response=$(_post "skey=$skey" "https://kr.dnsever.com/logout.php")

      return 1
    fi

  fi

  return 0
}
