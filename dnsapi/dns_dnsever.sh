#!/usr/bin/env bash

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
    DNSEVER_ID=""
    _err "You don't specify dnsever.com ID or PW yet."
    _err "Please create you key and try again."
    return 1
  fi

  #save the api key and email to the account conf file.
  _saveaccountconf DNSEVER_ID "$DNSEVER_ID"
  _saveaccountconf DNSEVER_PW "$DNSEVER_PW"


  dnsever_add_txt "$DNSEVER_ID" "$DNSEVER_PW" "$fulldomain" "$txtvalue"
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
  dnsever_delete_txt "$DNSEVER_ID" "$DNSEVER_PW" "$fulldomain" "$txtvalue"
  return $?
}

####################  Private functions below ##################################

dnsever_add_txt(){
  local login_id="$1"; local login_password="$2"; local fulldomain="$3"; local new_txt="$4"
  local n=$(echo $fulldomain |  grep -o '\.'  | wc -l)
  local f=$(seq 1 $(($n - 1)) | paste -d, -s -)
  local subname=$(echo $fulldomain | cut -f $f -d .)
  local user_domain=$(echo $fulldomain | cut -f $n,$(( $n + 1 )) -d .)

  curl -sS -k -c /tmp/dnsever.txt -d "login_id=$login_id" -d "login_password=$login_password" https://kr.dnsever.com/index.html > /tmp/dnsever.html
  local skey=$(curl -s -k -b /tmp/dnsever.txt https://kr.dnsever.com/start.html | grep skey | sed -n -e "s/^.*value=['\"]\(.*\)['\"].*/\1/p")

  _info "dnsever_add_txt skey=$skey user_domain=$user_domain selected_menu=edittxt command=add_txt subname=$subname new_txt=$new_txt"

  if [ -z "$skey" -o -z "$user_domain" -o -z "$subname" -o -z "$new_txt" ]; then
    _err "dnsever_add_txt ERROR skey or user_domain or subname or new_txt was empty"
    return 1
  fi

  curl -sS -k -b /tmp/dnsever.txt -d "skey=$skey" -d "user_domain=$user_domain" -d 'selected_menu=edittxt' \
  -d "subname=$subname" -d "new_txt=$new_txt" -d 'command=add_txt' \
  "https://kr.dnsever.com/start.html?user_domain=$user_domain&selected_menu=edittxt" > /tmp/dnsever.html
  return $?
}

dnsever_delete_txt(){
  local login_id="$1"; local login_password="$2"; local fulldomain="$3"; local txtvalue="$4"
  local n=$(echo $fulldomain |  grep -o '\.'  | wc -l)
  local f=$(seq 1 $(($n - 1)) | paste -d, -s -)
  local subname=$(echo $fulldomain | cut -f $f -d .)
  local user_domain=$(echo $fulldomain | cut -f $n,$(( $n + 1 )) -d .)


  curl -sS -k -c /tmp/dnsever.txt -d "login_id=$login_id" -d "login_password=$login_password" https://kr.dnsever.com/index.html > /tmp/dnsever.html
  curl -sS -k -b /tmp/dnsever.txt "https://kr.dnsever.com/start.html?user_domain=$user_domain&selected_menu=edittxt" > /tmp/dnsever.html

  local skey=$(cat /tmp/dnsever.html | grep skey | sed -n -e "s/^.*value=['\"]\(.*\)['\"].*/\1/p")

  _info "dnsever_delete_txt skey=$skey subname=$subname user_domain=$user_domain"

  if [ -z "$skey" -o -z "$user_domain" -o -z "$subname" ]; then
    _err "dnsever_delete_txt ERROR skey or user_domain or subname was empty"
    return 1
  fi

  local matched=$(grep "$fulldomain" /tmp/dnsever.html | sed -n -e "s/^.*name=['\"]\(.*\)['\"].*value.*$/\1/p" | sed 's/domain_for_txt_//g')
  local n; local checked; local input;
  for n in $matched; do
    local seq=$(cat /tmp/dnsever.html | grep seq_$n | sed -n -e "s/^.*value=['\"]\(.*\)['\"].*/\1/p")
    local old_txt=$(cat /tmp/dnsever.html | grep old_txt_$n | sed -n -e "s/^.*value=['\"]\(.*\)['\"].*id=.*$/\1/p")
    if [ "$txtvalue" != "$old_txt" ]; then
      _info "dnsever_delete_txt skip deleting seq=$seq fulldomain=$fulldomain due to old_txt=$old_txt was different from txtvalue=$txtvalue skip"
      continue
    fi
    checked="$checked,$n"
    input="$input -d domain_for_txt_$n=$fulldomain -d seq_$n=$seq -d old_txt_$n=$old_txt"
  done
  local check=$(echo "$checked" | sed 's/^,//')

  _info "dnsever_delete_txt skey=$skey user_domain=$user_domain selected_menu=edittxt command=delete_txt check[]=$check $input"

  if [ -z "$skey" -o -z "$user_domain" -o -z "$check" -o -z "$input" ]; then
    _err "dnsever_delete_txt ERROR skey or user_domain or check[] or other parameters was empty. Maybe $fulldomain=$txtvalue was not found."
    return 1
  fi

  curl -sS -k -b /tmp/dnsever.txt -d "skey=$skey" -d "user_domain=$user_domain" -d 'selected_menu=edittxt' \
  -d "check[]=$check" $input -d 'command=delete_txt' \
  "https://kr.dnsever.com/start.html?user_domain=$user_domain&selected_menu=edittxt" > /tmp/dnsever.html
  return $?
}
