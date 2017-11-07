#!/usr/bin/env sh

# kapper.net domain api
# for further questions please contact: support@kapper.net
# https://kapper.net (c) 2017 mm
#
# 20171107 - v1: initial version uploaded to GitHub Project Neilpang/acme.sh


#KAPPERNETDNS_Key="yourKAPPERNETapikey"
#KAPPERNETDNS_Secret="yourKAPPERNETapisecret"
KAPPERNETDNS_Api="https://dnspanel.kapper.net/API/1.1?APIKey=$KAPPERNETDNS_Key&APISecret=$KAPPERNETDNS_Secret"

###############################################################################
# called with
# fullhostname: something.example.com
# txtvalue:     someacmegenerated string
dns_kappernet_add()
{
        fullhostname=$1
        txtvalue=$2

        if [ -z "$KAPPERNETDNS_Key" ] || [ -z "$KAPPERNETDNS_Secret" ]; then
                KAPPERNETDNS_Key=""
                KAPPERNETDNS_Secret=""
                _err "You haven't defined kapper.net api key and secret yet."
                _err "Please send us mail to get your and secret."
        return 1
        fi

#store the api key and email to the account conf file.
        _saveaccountconf KAPPERNETDNS_Key "$KAPPERNETDNS_Key"
        _saveaccountconf KAPPERNETDNS_Secret "$KAPPERNETDNS_Secret"
        _debug "Checking the Domain/Pruefe die Domainn"
                if ! _get_root "$fullhostname"; then
                        _err "invalid domain"
                return 1
        fi
        _debug _sub_domain "SUBDOMAIN: $_sub_domain"
        _debug _domain "DOMAIN: $_domain"

        _info "typing to add the TXT Record/versuche den TXT Record einzufuegen"
        data="%7B%22name%22%3A%22$fullhostname%22%2C%22type%22%3A%22TXT%22%2C%22content%22%3A%22$txtvalue%22%2C%22ttl%22%3A%223600%22%2C%22prio%22%3A%22%22%7D"
        if _kappernet_api GET "action=new&subject=$_domain&data=$data"; then
#               if [ "$response" = "{\"OK\":true,\"info\":0,\"data\":\"\"}" ]; then
                if _contains "$response" "{\"OK\":true" ; then
#                       _info "schlafe 10 sekunden"
#                       _sleep 10
                        return 0
                else
                        _err "Error creating a TXT Record/Fehler beim Anlegen des Records: $fullhostname TXT $txtvalue"
                        _err "Error Message: $response"
                        return 1
                fi
        fi
        _err "Error creating a TXT Record/Fehler beim Anlegen eines TXT Records"
}

###############################################################################
# called with
# fullhostname: something.example.com
dns_kappernet_rm()
{
        fullhostname=$1
        txtvalue=$2

        if [ -z "$KAPPERNETDNS_Key" ] || [ -z "$KAPPERNETDNS_Secret" ]; then
                KAPPERNETDNS_Key=""
                KAPPERNETDNS_Secret=""
                _err "You haven't defined kapper.net api key and secret yet."
                _err "Please send us mail to get your and secret."
                return 1
        fi

#store the api key and email to the account conf file.
        _saveaccountconf KAPPERNETDNS_Key "$KAPPERNETDNS_Key"
        _saveaccountconf KAPPERNETDNS_Secret "$KAPPERNETDNS_Secret"

        _info "Trying to remove the TXT Record/Versuchee den TXT Record zu entfernen: $fullhostname"

        if _kappernet_api GET "action=del&subject=$fullhostname"; then
#               if [ "$response" = "{\"OK\":true,\"info\":0,\"data\":\"\"}" ]; then
                if _contains "$response"  "{\"OK\":true"; then
#                       _info "schlafe 10 sekunden"
#                       _sleep 10
                        return 0
                else
                        _err "Error deleting the Record/Fehler beim Entfernen des Records: $fullhostname"
                        _err "Problem: $response"
                        return 1
                fi
        fi
        _err "Problem creating the TXT record/Fehler beim Anlegen eines TXT records"
}
