#!/usr/bin/env bash

#This is a dns hook for cpanel
#This file name is "dns_cpanel.sh"
#This hook is compatible with cpdyndns from https://forums.cpanel.net/threads/can-cpanel-update-dynamic-ip-information-to-dns-records.261951/
# cpdyndns is not required, but this was designed to update a domain on a dd-wrt router to a cpanel hosted public domain. It may work elsewhere
# test and use at your own peril. 
#returns 0 means success, otherwise error.
#
#Author: smythe811
#Report Bugs here: https://github.com/Neilpang/acme.sh
#
#Tested on DD-WRT, Linux Mint 18
#
# This is released without ANY warranty or guarantee of use. USE THIS AT YOUR OWN RISK.
# Your use of this API signifies an agreement to hold blameless the developers for any results or damages that may occur to you or to others.
# Always backup your data files and cPanel zones prior to using any tool that you allow to make edits.

########  Public functions #####################

#Usage: dns_myapi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_cpanel_add() {
  fulldomain="$1"
  txtvalue="$2"
  _info "Using cPanel add"
  _debug fulldomain: "$fulldomain"
  _debug txtvalue: "$txtvalue"
  _get_root
  _setup_vars
  _setup_timeout
  _load_config
  _check_config
  _generate_auth_string
  
	REQUEST="GET /xml-api/cpanel?cpanel_xmlapi_module=ZoneEdit&cpanel_xmlapi_func=add_zone_record&cpanel_xmlapi_apiversion=2&domain=$_domain&name=$_sub_domain&type=TXT&txtdata=$txtvalue&ttl=300 HTTP/1.0\r\nConnection: close\r\nAuthorization: Basic $AUTH_STRING\r\nUser-Agent: $USERAGENT $VERSION\r\n\r\n\r\n"
	RESULT=`echo -e "$REQUEST" | openssl s_client -quiet -connect $CPANEL_SERVER:2083 2>&1`
	_check_results_for_error "$RESULT" "$REQUEST"
  _terminate
  return 1
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_cpanel_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using cpanel rm"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
   _get_root
  _setup_vars
  _setup_timeout
  _load_config
  _check_config
  _generate_auth_string
  
  _retreive_zone
  _parse_zone_lines
}

####################  Private functions below ##################################

#_acme-challenge.www.domain.com
#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
_debug "IN _get_root()"
  domain="$fulldomain"
  i=3
  p=2
  _domain=$(printf "$domain" | cut -d . -f $i-100)
  _sub_domain=$(printf "$domain" | cut -d . -f 1-$p)
  _debug domain "$_domain"
  _debug subdomain "$_sub_domain"	
_debug "OUT _get_root()"
}

# This loads a pre-existing config file from cpdyndns
# your config file should be located at ~/etc/cpdyndns.conf
# a proper file will contain:
#CONTACT_EMAIL="my_email_here@cpanel.net"
#CPANEL_SERVER="my_server_here.cpanel.net"
#DOMAIN="my_domain_here.tld"
#SUBDOMAIN="my_subdomain_here"
#CPANEL_USER="my_username_here"
#CPANEL_PASS="my_password_here"
_load_config ()
{
   if [ -e "/etc/$BASEDIR.conf" ]; then
      chmod 0600 /etc/$BASEDIR.conf
      . /etc/$BASEDIR.conf
      _debug "== /etc/$BASEDIR.conf is being used for configuration"
   else
      _debug "== /etc/$BASEDIR.conf does not exist"
   fi
   if [ -e "$HOMEDIR/etc/$BASEDIR.conf" ]; then
      chmod 0600 $HOMEDIR/etc/$BASEDIR.conf
      . $HOMEDIR/etc/$BASEDIR.conf
      _debug "== $HOMEDIR/etc/$BASEDIR.conf is being used for configuration"
   else
      _debug "== $HOMEDIR/etc/$BASEDIR.conf does not exist"
   fi
}

#Prime needed Variables
#These are meant to be compatible with cpdyndns/cpanel-dynamic-dns.sh
#You can use the CPANEL Values here, but this is designed to use a config file see _load_config()
_setup_vars ()
{
   USERAGENT="acme.sh/dns_cpanel.sh"
   VERSION="0.1"
   APINAME=""
   PARENTPID=$$
   HOMEDIR=`echo ~`
   TIMEOUT="300"
   BASEDIR="cpdyndns"
   CPANEL_SERVER=""
   CPANEL_USER=""
   CPANEL_PASS=""
}

_exit_timeout ()
{
   ALARMPID=""
   _err "Timeout while connecting to $LAST_CONNECT_HOST"
   exit
}

_setup_timeout ()
{
   (sleep $TIMEOUT; kill -ALRM $PARENTPID) &
   ALARMPID=$!
   trap exit_timeout SIGALRM
}

#Generate an Authentication String for cPanel
_generate_auth_string () {
   AUTH_STRING=`echo -n "$CPANEL_USER:$CPANEL_PASS" | openssl enc -base64`
}

#verify our configuration
_check_config () {
   if [ -z "$CPANEL_SERVER" ]; then
      _err "= Error: CPANEL_SERVER must be set in a configuration file"
      exit
   fi
   if [ -z "$CPANEL_USER" ]; then
      _err "= Error: CPANEL_USER must be set in a configuration file"
      exit
   fi
   if [ -z "$CPANEL_PASS" ]; then
      _err "= Error: CPANEL_PASS must be set in a configuration file"
      exit
   fi
}

_terminate () {
   if [ -z "$ALARMPID" ]; then
      kill $ALARMPID
   fi
   exit
}

_retreive_zone(){
	_info "In _retreive_zone"
	_debug "matching for: TXT $_sub_domain.$_domain."
   REQUEST="GET /xml-api/cpanel?cpanel_xmlapi_module=ZoneEdit&cpanel_xmlapi_func=fetchzone&cpanel_xmlapi_apiversion=2&domain=$DOMAIN HTTP/1.0\r\nConnection: close\r\nAuthorization: Basic $AUTH_STRING\r\nUser-Agent: cpanel-dynamic-dns.sh $VERSION\r\n\r\n\r\n"
   RECORD=""
   LINES=""
   INRECORD=0
   USETHISRECORD=0
   REQUEST_RESULTS=`echo -e "$REQUEST" | openssl s_client -quiet -connect $CPANEL_SERVER:2083 2>/dev/null`
   
   _check_results_for_error "$REQUEST_RESULTS" "$REQUEST"
   for LINE in $REQUEST_RESULTS
   do
	#_debug "$LINE"
      if [ "$LINE" == "<record>" ]; then
         INRECORD=1
         continue
      fi
      if [ "$LINE" == "</record>" ]; then
         INRECORD=0
         if [ "$USETHISRECORD" == "2" ]; then
            LINENUM=`echo -e "$RECORD" | grep '<Line>' | awk -F'<' '{print \$2}' | awk -F'>' '{print \$2}'`
            TXT=`echo -e "$RECORD" | grep -i '<txtdata>' | awk -F'<' '{print \$2}' | awk -F'>' '{print \$2}'`
            LINES="$LINES\n$LINENUM=$TXT"
         fi
         USETHISRECORD=0
         RECORD=""
         continue
      fi
      if [ "$LINE" == "<type>TXT</type>" ]; then
		_debug "Match TXT"
         USETHISRECORD=`expr $USETHISRECORD + 1`
      fi
      if [ "$LINE" == "<name>$_sub_domain.$_domain.</name>" ]; then
		_debug "Match Domain"
         USETHISRECORD=`expr $USETHISRECORD + 1`
      fi
      if [ "$INRECORD" == "1" ]; then
         RECORD="$RECORD\n$LINE"
      fi
   done
}

_parse_zone_lines(){
	#_info "In _parse_zone_lines"
	#_debug "$LINES"
   for LINE in `echo -e $LINES`
   do
	_debug "Removing Validation TXT"
	LINENUM=`echo $LINE | awk -F= '{print $1}'`
	REQUEST="GET /xml-api/cpanel?cpanel_xmlapi_module=ZoneEdit&cpanel_xmlapi_func=remove_zone_record&cpanel_xmlapi_apiversion=2&domain=$DOMAIN&line=$LINENUM HTTP/1.0\r\nConnection: close\r\nAuthorization: Basic $AUTH_STRING\r\nUser-Agent: cpanel-dynamic-dns.sh $VERSION\r\n\r\n\r\n"
	RESULT=`echo -e "$REQUEST" | openssl s_client -quiet -connect $CPANEL_SERVER:2083 2>&1`
	_check_results_for_error "$RESULT" "$REQUEST"
   done
}

_check_results_for_error ()
{
   REQUEST_RESULTS="$1"
   REQUEST="$2"
   if [ "`echo $REQUEST_RESULTS | grep '<status>1</status>'`" ]; then
      if [ "$QUIET" != "1" ]; then
         echo -n "success..."
      fi
   else
      INREASON=0
      INSTATUSMSG=0
      MSG=""
      STATUSMSG=""
      
      for LINE in $REQUEST_RESULTS
      do
         if [ "`echo $LINE | grep '<reason>'`" != "" ]; then
            INREASON=1
            INSTATUSMSG=0
            MSG=`echo $LINE | awk -F'>' '{print \$2}'`
            continue
         fi
         if [ "`echo $LINE | grep '</reason>'`" != "" ]; then
            INREASON=0
            MSGADD=`echo $LINE | awk -F'<' '{print \$1}'`
            MSG="$MSG $MSGADD"
            continue
         fi
         if [ "`echo $LINE | grep '<statusmsg>'`" != "" ]; then
            INSTATUSMSG=1
            INREASON=0
            STATUSMSG=`echo $LINE | awk -F'>' '{print \$2}'`
            continue
         fi
         if [ "`echo $LINE | grep '</statusmsg>'`" != "" ]; then
            INSTATUSMSG=0
            MSGADD=`echo $LINE | awk -F'<' '{print \$1}'`
            STATUSMSG="$STATUSMSG $MSGADD"
            continue
         fi
         if [ "$INREASON" -eq "1" ]; then
            MSG="$MSG $LINE"
         fi
         if [ "$INSTATUSMSG" -eq "1" ]; then
            STATUSMSG="$STATUSMSG $LINE"
         fi
         
      done
      
      if [ -z "$MSG" ]; then
         MSG="Unknown Error"
         if [ -z "$STATUSMSG" ]; then
            STATUSMSG="Please make sure you have the zoneedit, or simplezone edit permission on your account."
         fi
      fi

         _err "Request failed with error: $MSG ($STATUSMSG)"

      _terminate
   fi
}
