#!/bin/sh

dns_strato_add() {
  fulldomain=$1
  txtvalue=$2


  STRATO_Username="${STRATO_Username:-$(_readaccountconf_mutable STRATO_Username)}"
  STRATO_Password="${STRATO_Password:-$(_readaccountconf_mutable STRATO_Password)}"
  if [ -z "$STRATO_Username" ] || [ -z "$STRATO_Password" ]; then
    STRATO_Username=""
    STRATO_Password=""
    _err "You don't specify Strato account number and password yet."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable STRATO_Username "$STRATO_Username"
  _saveaccountconf_mutable STRATO_Password "$STRATO_Password"
  
  login="identifier=$STRATO_Username&passwd=$STRATO_Password&action_customer_login.x=Login"
  #Save Cookie
  res=$(wget --keep-session-cookies --save-cookies cookies.txt --post-data $login https://www.strato.de/apps/CustomerService -O - 2>&1 )
  code=$(echo $res | grep -Eo 'response... ([[:digit:]]{3})' | sed 's/response... //')
  if [[ $code -ne "200" ]]; then
	 _err "Can't save cookie"
    return 1
  fi
  echo "dns_strato: login"

  #Login with Cookie
  res=$(wget --keep-session-cookies --load-cookies cookies.txt --post-data $login https://www.strato.de/apps/CustomerService -O - 2>&1 )
  codes=$(echo $res | grep -Eo 'response... ([[:digit:]]{3})' | sed 's/response... //')
  if [[ $(echo $codes | cut -d ' ' -f1) != "302" ]] || [[ $(echo $codes | cut -d ' ' -f2) != "200" ]];then
	 _err "Login error $login"
    return 1
  fi
  echo "dns_strato: logged in successfully"
  
  sessionUrl=$(echo $res | sed -n 's/.*Location: \(\S*\)&.*/\1/p' | cut -d '&' -f1)
  
  #for each domain of full domain
  vhost=$(echo $fulldomain | sed -e 's/_acme-challenge.//')
  echo "dns_strato: changing _acme-challenge for $vhost"
  
  txtUrl=$sessionUrl"&cID=1&node=ManageDomains&action_show_txt_records&vhost="$vhost
  
  res=$(wget --keep-session-cookies --load-cookies cookies.txt $txtUrl -O - 2>&1 )
  code=$(echo $res | grep -Eo 'response... ([[:digit:]]{3})' | sed 's/response... //')
  if [[ $code -ne "200" ]]; then
	 _err "Can't load txt page"
    return 1
  fi
  echo "dns_strato: fetching existing TXT data"
  
  sessionID=$(echo $res | sed -n 's/.*sessionID : "\(\S*\)".*$/\1/p')
  cID=$(echo $res | sed -n 's/.*cID : "\(\S*\)".*$/\1/p')
  node=$(echo $res | sed -n 's/.*node : "\(\S*\)".*$/\1/p')
  vhost=$(echo $res | sed -n 's/.*vhost. value="\(\S*\)".*$/\1/p')
  spf_type=$(echo $res | sed -n 's/.*spf_type. value="\(\S*\)" checked.*$/\1/p')

  postBody="sessionID=$sessionID&cID=$cID&node=$node&vhost=$vhost&spf_type=$spf_type"
  
  prefix=$(echo $res | grep -Eo 'value="(\S+)" name="prefix"' | sed -n 's/value="\(\S*\)".*$/\1/p')
  type=$(echo $res | grep -Eo 'name="type"> <option value="(\S*)"' | sed -n 's/.*value="\(\S*\)".*$/\1/p')
  value=$(echo $res | grep -Eo 'name="value".{0,60}">\S+<' | sed -n 's/.*>\(\S*\)<.*$/\1/p')
  i=1;
  for j in $prefix
	do
		tPrefix=$j
		tType=$(echo $type | cut -d ' ' -f$i)
		tValue=$(echo $value | cut -d ' ' -f$i)
		
		if [[ $tPrefix == "_acme-challenge" ]];then
			tValue=$txtvalue
			echo "dns_strato: changing _acme-challenge for $vhost to $tValue"
		fi
		postBody=$postBody"&prefix=$tPrefix&type=$tType&value=$tValue"
		i=`expr $i + 1`
  done
  
  postBody=$postBody"&action_change_txt_records=Einstellung+übernehmen"
  #!/bin/sh
  
  res=$(wget --keep-session-cookies --load-cookies cookies.txt --post-data $postBody $txtUrl -O - 2>&1 )
  code=$(echo $res | grep -Eo 'response... ([[:digit:]]{3})' | sed 's/response... //')
  if [[ $code -ne "200" ]]; then
	  _err "Can't change TXT settings"
    return 1
  fi
  
  success=$(echo $res | grep -Eo '<div class="sf-status success">[a-zA-Z0-9.[:space:]]*')
   if [[ -z "$success" ]]; then
	  _err "Can't change TXT settings"
    return 1
  fi
  echo "dns_strato: TXT change successful: "$(echo $success | sed -n 's/.*> \(.*\)/\1/p')
  rm cookies.txt
}




