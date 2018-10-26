#!/bin/bash

########  Public functions #####################

#Usage: dns_nsupdate_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_vestacp_add() {
  fulldomain=$1
  txtvalue=$2
  _debug $DOMAIN "========================================"
  _debug $DOMAIN "=                VESTA                 ="
  _debug $DOMAIN "========================================"
  _debug $DOMAIN " REMEMBER: VESTA RESPONSE EMPTY == GOOD "
  _debug $DOMAIN "            ADD DNS VESTACP             "
  _debug $DOMAIN "----------------------------------------"
  _debug $DOMAIN "ADD ACME CHALLENGE:"
  _debug $DOMAIN "DATA:"
  _debug $DOMAIN "USER:$VESTA_USER"
  _debug $DOMAIN "DOMAIN:$DOMAIN"
  _debug $DOMAIN "RECORD:_acme-challenge"
  _debug $DOMAIN "TYPE:TXT"
  _debug $DOMAIN "VALUE:$txtvalue"
  exists_dns_record=$($VESTA/bin/v-exists-dns-record "$VESTA_USER" "$DOMAIN" "_acme-challenge" "A");

  add_dns=$($VESTA/bin/v-add-dns-record "$VESTA_USER" "$DOMAIN" "_acme-challenge" "TXT" "\"$txtvalue\"");
  _debug $DOMAIN "RESULT ADD DNS: $add_dns";
  restart_dns=$($VESTA/bin/v-restart-dns)

  _debug $DOMAIN "CURRENT VESTA DNS RECORDS:"
  UPDATED=$($VESTA/bin/v-list-dns-records "$VESTA_USER" "$DOMAIN")
  _debug $DOMAIN "$UPDATED";

  _debug $DOMAIN echo "VESTA restart dns result: $restart_dns"
  _debug $DOMAIN "#########################################"
}

#Usage: dns_nsupdate_rm   _acme-challenge.www.domain.com
dns_vestacp_rm() {
  fulldomain=$1
  txtvalue="${txtvalue}";
  _debug $DOMAIN "========================================"
  _debug $DOMAIN "=                VESTA                 ="
  _debug $DOMAIN "========================================"
  _debug $DOMAIN " REMEMBER: VESTA RESPONSE EMPTY == GOOD "
  _debug $DOMAIN "          REMOVE DNS VESTACP            "
  _debug $DOMAIN "----------------------------------------"

  if [ -z "$VESTA_BYPASS_DELETE" ]; then
        VESTA_BYPASS_DELETE="0";
  fi;
  _debug $DOMAIN "VESTA - BYPASS RECORD REMOVAL: $VESTA_BYPASS_DELETE [VESTA_BYPASS_DELETE]"
  if [ "$VESTA_BYPASS_DELETE" = "1" ]; then
        record="-1";
  else
        record=$(_get_vestacp_dns_record_id)
  fi;

  _debug $DOMAIN "RECORD TO DELETE FROM VESTA: $record (-1 IS GOOB)"

  if [ "$record" != "-1" ]; then
        DNS=$($VESTA/bin/v-delete-dns-record "$VESTA_USER" "$DOMAIN" "$record" "1");
        _debug $DOMAIN "RESPONSE FROM VESTA API: $DNS"

        _debug $DOMAIN "THE !WHILE! CYCLE"

        while [[ "$record" != "-1" ]];
        do
                record=$(_get_vestacp_dns_record_id)
                _debug $DOMAIN "RECORD TO DELETE FROM VESTA: $record (-1 IS GOOD)"

                if [ "$record" != "-1" ]; then
                        DNS=$($VESTA/bin/v-delete-dns-record "$VESTA_USER" "$DOMAIN" "$record" "1");
                        _debug $DOMAIN "RESPONSE FROM VESTA API: $DNS"
                else
                        _debug $DOMAIN "NO MORE DNS FROM ACME"
                fi;
        done;
        _debug $DOMAIN "END #WHILE# CYCLE"
  fi;
  _debug $DOMAIN "CURRENT VESTA DNS RECORDS:"
  UPDATED=$($VESTA/bin/v-list-dns-records "$VESTA_USER" "$DOMAIN")
  _debug $DOMAIN "$UPDATED";

  DNS_UPDATE=$($VESTA/bin/v-restart-dns)
  _debug $DOMAIN "DNS UPDATE RESPONSE: $DNS_UPDATE"
  _debug $DOMAIN "#########################################"
}

####################  Private functions below ##################################

_get_vestacp_dns_record_id(){
        data=$($VESTA/bin/v-get-dns-record-id "$VESTA_USER" "$DOMAIN" "_acme-challenge");
        echo "$data";
}
