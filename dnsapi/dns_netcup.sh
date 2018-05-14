#!/usr/bin/env sh

#Requirments: jq

NC_Apikey="${NC_Apikey:-$(_readaccountconf_mutable NC_Apikey)}"
NC_Apipw="${NC_Apipw:-$(_readaccountconf_mutable NC_Apipw)}"
NC_CID="${NC_CID:-$(_readaccountconf_mutable NC_CID)}"
end=https://ccp.netcup.net/run/webservice/servers/endpoint.php?JSON
client=""

dns_netcup_add() {
	login
	if [ "$NC_Apikey" = "" ] || [ "$NC_Apipw" = "" ] || [ "$NC_CID" = "" ]; then
		_err "No Credentials given"
		return 1
	fi
	fulldomain=$1
	txtvalue=$2
	tld=""
	domain=""
	exit=0
	for (( i=20; i>0; i--))
	do
		tmp=$(cut -d'.' -f$i <<< $fulldomain)		
		if [ "$tmp" != "" ]; then
			if [ "$tld" = "" ]; then
				tld=$tmp						
			else
				domain=$tmp
				exit=$i
				break;
			fi
		fi
	done
	inc=""
	for (( i=1; i<($exit); i++))
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
	done
	tmp=$(cut -d'.' -f$inc <<< $fulldomain)
	msg=$(_post "{\"action\": \"updateDnsRecords\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\",\"clientrequestid\": \"$client\" , \"domainname\": \"$domain.$tld\", \"dnsrecordset\": { \"dnsrecords\": [ {\"id\": \"\", \"hostname\": \"$tmp\", \"type\": \"TXT\", \"priority\": \"\", \"destination\": \"$txtvalue\", \"deleterecord\": \"false\", \"state\": \"yes\"} ]}}}" $end "" "POST")
	_debug "$msg"
	if [ $(echo $msg | jq -r .status) != "success" ]; then
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
	for (( i=20; i>0; i--))
	do
		tmp=$(cut -d'.' -f$i <<< $fulldomain)		
		if [ "$tmp" != "" ]; then
			if [ "$tld" = "" ]; then
				tld=$tmp						
			else
				domain=$tmp
				exit=$i
				break;
			fi
		fi
	done
	inc=""
	for (( i=1; i<($exit); i++))
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
	done
	tmp=$(cut -d'.' -f$inc <<< $fulldomain)	
	doma="$domain.$tld"
	rec=$(getRecords $doma)
	ids=$(echo $rec | jq -r ".[]|select(.destination==\"$txtvalue\")|.id")
	msg=$(_post "{\"action\": \"updateDnsRecords\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\",\"clientrequestid\": \"$client\" , \"domainname\": \"$doma\", \"dnsrecordset\": { \"dnsrecords\": [ {\"id\": \"$ids\", \"hostname\": \"$tmp\", \"type\": \"TXT\", \"priority\": \"\", \"destination\": \"$txtvalue\", \"deleterecord\": \"TRUE\", \"state\": \"yes\"} ]}}}" $end "" "POST")
	_debug "$msg"
	if [ $(echo $msg | jq -r .status) != "success" ]; then
		_err "$msg"
		return 1
	fi
	logout
}

login() {
	tmp=$(_post '{"action": "login", "param": {"apikey": "'$NC_Apikey'", "apipassword": "'$NC_Apipw'", "customernumber": "'$NC_CID'"}}' $end "" "POST")
	sid=$(echo ${tmp} | jq -r .responsedata.apisessionid)
	_debug "$tmp"
	if [ $(echo $tmp | jq -r .status) != "success" ]; then
		_err "$tmp"
		return 1
	fi
}
logout() {
	tmp=$(_post '{"action": "logout", "param": {"apikey": "'$NC_Apikey'", "apisessionid": "'$sid'", "customernumber": "'$NC_CID'"}}' $end "" "POST")
	_debug "$tmp"
	if [ $(echo $tmp | jq -r .status) != "success" ]; then
		_err "$tmp"
		return 1
	fi
}
getRecords() {	
	tmp2=$(_post "{\"action\": \"infoDnsRecords\", \"param\": {\"apikey\": \"$NC_Apikey\", \"apisessionid\": \"$sid\", \"customernumber\": \"$NC_CID\", \"domainname\": \"$1\"}}" $end "" "POST")
	xxd=$(echo ${tmp2} | jq -r '.responsedata.dnsrecords | .[]')
	xcd=$(echo $xxd | sed 's/} {/},{/g') 
	echo "[ $xcd ]"
	_debug "$tmp2"
	if [ $(echo $tmp2 | jq -r .status) != "success" ]; then
		_err "$tmp2"
		return 1
	fi
}
