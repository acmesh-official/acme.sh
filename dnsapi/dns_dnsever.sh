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

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_dnsever_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using dnsever"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if [ -z "$DNSEVER_ID" ] || [ -z "$DNSEVER_PW" ]; then
    DNSEVER_ID=""
    DNSEVER_PW=""
    _err "You don't specify dnsever.com ID or PW yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf DNSEVER_ID "$DNSEVER_ID"
  _saveaccountconf DNSEVER_PW "$DNSEVER_PW"

  dnsever_txt "add" "$DNSEVER_ID" "$DNSEVER_PW" "$fulldomain" "$txtvalue"
  return $?
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_dnsever_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using dnsever"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if [ -z "$DNSEVER_ID" ] || [ -z "$DNSEVER_PW" ]; then
    DNSEVER_ID=""
    DNSEVER_PW=""
    _err "You don't specify dnsever.com ID or PW yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf DNSEVER_ID "$DNSEVER_ID"
  _saveaccountconf DNSEVER_PW "$DNSEVER_PW"

  dnsever_txt "delete" "$DNSEVER_ID" "$DNSEVER_PW" "$fulldomain" "$txtvalue"
  return $?
}

####################  Private functions below ##################################

dnsever_txt(){
  action="$1"; login_id="$2"; login_password="$3"; fulldomain="$4"; txt="$5"

  _inithttp

  if [ "$_ACME_CURL" ] && [ "${ACME_USE_WGET:-0}" = "0" ]; then
    httpmethod_save="POST -c /tmp/dnsever.txt"
    httpmethod_load="POST -b /tmp/dnsever.txt"
  else
    httpmethod_save="POST --load-cookies /tmp/dnsever.txt"
    httpmethod_load="POST --save-cookies /tmp/dnsever.txt"
  fi

  response=$(_post "login_id=$login_id&login_password=$login_password" "https://kr.dnsever.com/index.html" "" "$httpmethod_save")
  if [ $? != 0 -o -z "$response" ]; then
    _err "dnsever_txt:$action ERROR login failed. Please check https://kr.dnsever.com/index.html with login_id=$login_id login_password=$login_password"
    dnsever_logout "" "$httpmethod_load"
    return 1
  fi

  response=$(_post "" "https://kr.dnsever.com/start.html" "" "$httpmethod_load")
  if [ $? != 0 -o -z "$response" ]; then
    _err "dnsever_txt:$action ERROR login failed. Please check https://kr.dnsever.com/start.html after login"
    dnsever_logout "" "$httpmethod_load"
    return 1
  fi
 
  skey=$(printf "%s\n" "$response" | grep skey | sed -n -e "s/^.*value=['\"]\(.*\)['\"].*/\1/p")
  if [ -z "$skey" ]; then
    _err "dnsever_txt:$action ERROR login failed with login_id=$login_id login_password=$login_password"
    dnsever_logout "$skey" "$httpmethod_load"
    return 1
  fi

  user_domain=$(dnsever_select_user_domain "$fulldomain" "$response")

  if [ -z "$user_domain" ]; then
    _err "dnsever_txt:$action ERROR no matching domain in DNSEver"
    dnsever_logout "$skey" "$httpmethod_load"
    return 1
  fi

  if [ "$action" = "add" ]; then

    subname=$(echo $fulldomain | sed "s/\.$user_domain\$//")

    if [ -z "$subname" -o -z "$txt" ]; then
      _err "dnsever_txt ERROR subname=$subname or txt=$txt is empty"
      dnsever_logout "$skey" "$httpmethod_load"
      return 1
    fi

    _info "dnsever_txt:$action skey=$skey user_domain=$user_domain selected_menu=edittxt command=add_txt subname=$subname txt=$txt"

    response=$(_post "skey=$skey&user_domain=$user_domain&selected_menu=edittxt" "https://kr.dnsever.com/start.html" "" "$httpmethod_load")
    if [ $? != 0 -o -z "$response" ]; then
      _err "dnsever_txt:$action ERROR failed to get TXT records from DNSEver"
      dnsever_logout "$skey" "$httpmethod_load"
      return 1
    fi

    check=$(dnsever_check "$fulldomain" "$txt" "$response")
    if [ $? = 0 -o -n "$check" ]; then
      _err "dnsever_txt:$action ERROR $fulldomain=$txt already exists"
      dnsever_logout "$skey" "$httpmethod_load"
      return 1
    fi

    response=$(_post "skey=$skey&user_domain=$user_domain&selected_menu=edittxt&command=add_txt&subname=$subname&new_txt=$txt" "https://kr.dnsever.com/start.html" "" "$httpmethod_load")
    if [ $? != 0 -o -z "$response" ]; then
      _err "dnsever_txt:$action ERROR failed to add_text $fulldomain=$txt"
      dnsever_logout "$skey" "$httpmethod_load"
      return 1
    fi

    check=$(dnsever_check "$fulldomain" "$txt" "$response")
    if [ $? != 0 -o -z "$check" ]; then
      _err "dnsever_txt:$action ERROR failed to get newly added $fulldomain=$txt"
      dnsever_logout "$skey" "$httpmethod_load"
    fi

  elif [ "$action" = "delete" ]; then

    response=$(_post "skey=$skey&user_domain=$user_domain&selected_menu=edittxt" "https://kr.dnsever.com/start.html" "" "$httpmethod_load")
    if [ $? != 0 -o -z "$response" ]; then
      _err "dnsever_txt:$action ERROR failed to get TXT records from DNSEver"
      dnsever_logout "$skey" "$httpmethod_load"
      return 1
    fi

    check=$(dnsever_check "$fulldomain" "$txt" "$response")
    if [ $? != 0 -o -z "$check" ]; then
      _err "dnsever_txt:$action ERROR $fulldomain=$txt does not exists"
      dnsever_logout "$skey" "$httpmethod_load"
      return 1
    fi

    _info "dnsever_txt:$action skey=$skey user_domain=$user_domain selected_menu=edittxt command=delete_txt$(echo $check|sed 's/\&/ /g')"

    response=$(_post "skey=$skey&user_domain=$user_domain&selected_menu=edittxt&command=delete_txt&$check" "https://kr.dnsever.com/start.html" "" "$httpmethod_load")
    if [ $? != 0 -o -z "&response" ]; then
      _err "dnsever_txt:$action ERROR failed to delete $fulldomain=$txt from DNSEver"
      dnsever_logout "$skey" "$httpmethod_load"
      return 1
    fi
  
    response=$(_post "skey=$skey&user_domain=$user_domain&selected_menu=edittxt" "https://kr.dnsever.com/start.html" "" "$httpmethod_load")
    if [ $? != 0 -o -z "&response" ]; then
      _err "dnsever_txt:$action ERROR failed to get $fulldomain=$txt from DNSEver"
      dnsever_logout "$skey" "$httpmethod_load"
      return 1
    fi

    check=$(dnsever_check "$fulldomain" "$txt" "$response")
    if [ $? = 0 -a -n "$check" ]; then
      _err "dnsever_txt:$action ERROR $fulldomain=$txt still exists"
      dnsever_logout "$skey" "$httpmethod_load"
      return 1
    fi

  else
    _err "dnsever_txt:$action action should be add or delete"
  fi

  dnsever_logout "$skey" "$httpmethod_load"
  return 0 
}

dnsever_logout(){
  skey="$1"; httpmethod_load="$2"

  if [ -n "$skey" -a -n "$httpmethod_load" ]; then
    response=$(_post "skey=$skey" "https://kr.dnsever.com/logout.php" "" "$httpmethod_load")  
  fi
  if [ -e /tmp/dnsever.txt ]; then
    rm -f /tmp/dnsever.txt
  fi
}

dnsever_select_user_domain(){
  fulldomain="$1"; response="$2"

  domains=$(printf "%s\n" "$response" | grep OPTION | sed -n -e "s/^.*value=['\"]\(.*\)['\"].*/\1/p" | grep -v "^$")
  nmax=0; selected=""
  for domain in $domains; do
    if echo "$fulldomain" | grep -q "$domain\$"; then
      n=$(echo $domain |  wc -c)
      if [ $n -gt $nmax ]; then
        nmax=$n
        selected="$domain"
      fi
    fi
  done
  echo "$selected"
}

dnsever_check(){
  fulldomain="$1"
  old_txt="$1"
  response="$3"

  matched=$(printf "%s\n" "$response" | grep "$fulldomain" | sed -n -e "s/^.*name=['\"]\(.*\)['\"].*value.*$/\1/p" | sed 's/domain_for_txt_//g')

  check=""
  for n in $matched; do
    seq=$(printf "%s\n" "$response" | grep seq_$n | sed -n -e "s/^.*value=['\"]\(.*\)['\"].*/\1/p")
    old_txt=$(printf "%s\n" "$response" | grep old_txt_$n | sed -n -e "s/^.*value=['\"]\(.*\)['\"].*id=.*$/\1/p")
    if [ "$txtvalue" != "$old_txt" ]; then
      _info "dnsever_check skip deleting seq=$seq fulldomain=$fulldomain due to old_txt=$old_txt was different from txtvalue=$txtvalue skip"
      continue
    fi
    check="$input&check[]=$n&domain_for_txt_$n=$fulldomain&seq_$n=$seq&old_txt_$n=$old_txt"
  done

  if [ -z "$check" ]; then
    return 1
  fi

  echo "$check"
  return 0
}
