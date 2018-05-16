#!/usr/bin/env sh
#developed by linux-insideDE

NC_Apikey="${NC_Apikey:-$(_readaccountconf_mutable NC_Apikey)}"
NC_Apipw="${NC_Apipw:-$(_readaccountconf_mutable NC_Apipw)}"
NC_CID="${NC_CID:-$(_readaccountconf_mutable NC_CID)}"
end="https://ccp.netcup.net/run/webservice/servers/endpoint.php?JSON"
client=""

dns_netcup_add() {
	login
	if [ "$NC_Apikey" = "" ] || [ "$NC_Apipw" = "" ] || [ "$NC_CID" = "" ]; then
		_err "No Credentials given"
		return 1
	fi
	_saveaccountconf_mutable NC_Apikey  "$NC_Apikey"
	_saveaccountconf_mutable NC_Apipw  "$NC_Apipw"
	_saveaccountconf_mutable NC_CID  "$NC_CID"	
	fulldomain=$1
	txtvalue=$2
	tld=""
	domain=""
	exit=0	
	i=20	
	while [ "$i" -gt 0 ];
	do 
		tmp=$(echo "$fulldomain" | cut -d'.' -f$i)		
		if [ "$tmp" != "" ]; then
			if [ "$tld" = "" ]; then
				tld=$tmp						
			else
				domain=$tmp
				exit=$i
				break;
			fi
		fi		
		i=$(_math "$i" - 1)
	done	
	inc=""
	i=1	
	while [ "$i" -lt "$exit" ];
	do
		if [ "$((exit-1))" = "$i" ]; then
			inc="$inc$i"
			break;
		else
			if [ "$inc" = "" ]; then
				inc="$i,"
			else
				inc="$inc$i,"			
			fi			
		fi	
		i=$(_math "$i" + 1)
	done
	
	tmp=$(echo "$fulldomain" | cut -d'.' -f$inc)
	msg=$(_post "{\"action\": \"updateDnsRecords\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\",\"clientrequestid\": \"$client\" , \"domainname\": \"$domain.$tld\", \"dnsrecordset\": { \"dnsrecords\": [ {\"id\": \"\", \"hostname\": \"$tmp\", \"type\": \"TXT\", \"priority\": \"\", \"destination\": \"$txtvalue\", \"deleterecord\": \"false\", \"state\": \"yes\"} ]}}}" "$end" "" "POST")
	_debug "$msg"
	if [ "$(_getfield "$msg" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
		_err "$msg"
		return 1
	fi
	logout
}

dns_netcup_rm() {
	login
	fulldomain=$1
	txtvalue=$2
	tld=""
	domain=""
	exit=0	
	i=20
	while [ "$i" -gt 0 ];
	do
		tmp=$(echo "$fulldomain" | cut -d'.' -f$i)		
		if [ "$tmp" != "" ]; then
			if [ "$tld" = "" ]; then
				tld=$tmp						
			else
				domain=$tmp
				exit=$i
				break;
			fi
		fi
		i=$(_math "$i" - 1)
	done
	inc=""	
	i=1	
	while [ "$i" -lt "$exit" ];
	do
		if [ "$((exit-1))" = "$i" ]; then
			inc="$inc$i"
			break;
		else
			if [ "$inc" = "" ]; then
				inc="$i,"
			else
				inc="$inc$i,"
			fi
		fi
		i=$(_math "$i" + 1)
	done
	tmp=$(echo "$fulldomain" | cut -d'.' -f$inc)	
	doma="$domain.$tld"
	rec=$(getRecords "$doma")
	
	ida=0000
	idv=0001
	ids=0000000000	
	i=1
	while [ "$i" -ne 0 ];
	do
		specrec=$(_getfield "$rec" "$i" ";")
		idv="$ida"
		ida=$(_getfield "$specrec" "1" "," | sed 's/\"id\":\"//g' | sed 's/\"//g')
		txtv=$(_getfield "$specrec" "5" "," | sed 's/\"destination\":\"//g' | sed 's/\"//g')			 
		i=$(_math "$i" + 1)
		if [ "$txtvalue" = "$txtv" ]; then
			i=0
			ids="$ida"
		fi	
		if [ "$ida" = "$idv" ]; then
			i=0
		fi
	done	
	msg=$(_post "{\"action\": \"updateDnsRecords\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\",\"clientrequestid\": \"$client\" , \"domainname\": \"$doma\", \"dnsrecordset\": { \"dnsrecords\": [ {\"id\": \"$ids\", \"hostname\": \"$tmp\", \"type\": \"TXT\", \"priority\": \"\", \"destination\": \"$txtvalue\", \"deleterecord\": \"TRUE\", \"state\": \"yes\"} ]}}}" "$end" "" "POST")
	_debug "$msg"
	if [ "$(_getfield "$msg" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
		_err "$msg"
		return 1
	fi
	logout
}

login() {
	tmp=$(_post "{\"action\": \"login\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apipassword\": \"$NC_Apipw\", \"customernumber\": \"$NC_CID\"}}" "$end" "" "POST")	
	sid=$(_getfield "$tmp" "8" | sed s/\"responsedata\":\{\"apisessionid\":\"//g | sed 's/\"\}\}//g')
	_debug "$tmp"
	if [ "$(_getfield "$msg" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
		_err "$msg"
		return 1
	fi
}
logout() {
	tmp=$(_post "{\"action\": \"logout\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\"}}" "$end" "" "POST")
	_debug "$tmp"
	if [ "$(_getfield "$msg" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
		_err "$msg"
		return 1
	fi
}
getRecords() {	
	tmp2=$(_post "{\"action\": \"infoDnsRecords\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\", \"domainname\": \"$1\"}}" "$end" "" "POST")
	out=$(echo "$tmp2" | sed 's/\[//g' | sed 's/\]//g' | sed 's/{\"serverrequestid\".*\"dnsrecords\"://g' | sed 's/},{/};{/g' | sed 's/{//g' | sed 's/}//g')
	echo "$out"
	_debug "$tmp2"
	if [ "$(_getfield "$msg" "4" | sed s/\"status\":\"//g | sed s/\"//g)" != "success" ]; then
		_err "$msg"
		return 1
	fi
}
