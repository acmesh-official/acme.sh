#!/usr/bin/env sh

#Requirments: jq
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
		i=$((i - 1))
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
		i=$((i + 1))
	done
	
	tmp=$(echo "$fulldomain" | cut -d'.' -f$inc)
	msg=$(_post "{\"action\": \"updateDnsRecords\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\",\"clientrequestid\": \"$client\" , \"domainname\": \"$domain.$tld\", \"dnsrecordset\": { \"dnsrecords\": [ {\"id\": \"\", \"hostname\": \"$tmp\", \"type\": \"TXT\", \"priority\": \"\", \"destination\": \"$txtvalue\", \"deleterecord\": \"false\", \"state\": \"yes\"} ]}}}" "$end" "" "POST")
	_debug "$msg"
	if [ "$(echo "$msg" | jq -r .status)" != "success" ]; then
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
		i=$((i - 1))
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
		i=$((i + 1))
	done
	tmp=$(echo "$fulldomain" | cut -d'.' -f$inc)	
	doma="$domain.$tld"
	rec=$(getRecords "$doma")
	ids=$(echo "$rec" | jq -r ".[]|select(.destination==\"$txtvalue\")|.id")
	msg=$(_post "{\"action\": \"updateDnsRecords\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\",\"clientrequestid\": \"$client\" , \"domainname\": \"$doma\", \"dnsrecordset\": { \"dnsrecords\": [ {\"id\": \"$ids\", \"hostname\": \"$tmp\", \"type\": \"TXT\", \"priority\": \"\", \"destination\": \"$txtvalue\", \"deleterecord\": \"TRUE\", \"state\": \"yes\"} ]}}}" "$end" "" "POST")
	_debug "$msg"
	if [ "$(echo "$msg" | jq -r .status)" != "success" ]; then
		_err "$msg"
		return 1
	fi
	logout
}

login() {
	tmp=$(_post "{\"action\": \"login\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apipassword\": \"$NC_Apipw\", \"customernumber\": \"$NC_CID\"}}" "$end" "" "POST")
	sid=$(echo "$tmp" | jq -r .responsedata.apisessionid)
	_debug "$tmp"
	if [ "$(echo "$tmp" | jq -r .status)" != "success" ]; then
		_err "$tmp"
		return 1
	fi
}
logout() {
	tmp=$(_post "{\"action\": \"logout\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\"}}" "$end" "" "POST")
	_debug "$tmp"
	if [ "$(echo "$tmp" | jq -r .status)" != "success" ]; then
		_err "$tmp"
		return 1
	fi
}
getRecords() {	
	tmp2=$(_post "{\"action\": \"infoDnsRecords\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\", \"domainname\": \"$1\"}}" "$end" "" "POST")
	xxd=$(echo "$tmp2" | jq -r ".responsedata.dnsrecords" | tr '[' ' ' | tr ']' ' ')
	xcd=$(echo "$xxd" | sed 's/}\s{/},{/g')
	echo "[ $xcd ]"
	_debug "$tmp2"
	if [ "$(echo "$tmp2" | jq -r .status)" != "success" ]; then
		_err "$tmp2"
		return 1
	fi
}
