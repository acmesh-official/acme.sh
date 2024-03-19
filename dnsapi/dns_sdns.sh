#!/usr/bin/env sh

#  Usage to order a * certificate
#  ./acme.sh --issue -d '*.www.domain.com'  --dns dns_sdns --server letsencrypt --dnssleep 240

SDNS_API_URL="https://robot.s-dns.de:8488/"

# export SDNS_ZONE_KEY=your_zone_key

########  Public functions #####################

# Adds a txt record with the specified value. Does not remove an existing record
# Usage: dns_sdns_add  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_sdns_add() {
  fulldomain=$1
  txtvalue=$2
  _debug2 "dns_sdns_add() entered"
  SDNS_ZONE_KEY="${SDNS_ZONE_KEY:-$(_readaccountconf_mutable SDNS_ZONE_KEY)}"
  if [ -z "$SDNS_ZONE_KEY" ]; then
    SDNS_ZONE_KEY=""
    _err "You didn't specify your zone key yet. (export SDNS_ZONE_KEY=yourkey)"
    return 1
  fi
  _saveaccountconf_mutable SDNS_ZONE_KEY "$SDNS_ZONE_KEY"
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _payload="<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>
<zoneRequest>
  <zone name=\"$_domain\" action=\"ADDORUPDATERR\" ddnskey=\"$SDNS_ZONE_KEY\">
    <rr host=\"$_sub_domain\" type=\"TXT\" value=\"$txtvalue\" keepExisting=\"true\"/>
  </zone>
</zoneRequest>"
  _debug2 "$_payload"
  response=$(_post "$_payload" "$SDNS_API_URL")
  _debug2 "$response"
  if _contains "$response" "status=\"OK\""; then
    _debug "The TXT record has been added."
    return 0
  else
    _err "The attempt to add the TXT record has failed."
    return 1
  fi
}

# Removes a txt record with the specified value. This function does not remove resource records with the same name but a different values.
# Usage: dns_sdns_rm  _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_sdns_rm() {
  fulldomain=$1
  txtvalue=$2
  _debug2 "dns_sdns_rm() entered"
  SDNS_ZONE_KEY="${SDNS_ZONE_KEY:-$(_readaccountconf_mutable SDNS_ZONE_KEY)}"
  if [ -z "$SDNS_ZONE_KEY" ]; then
    SDNS_ZONE_KEY=""
    _err "You didn't specify your zone key yet. (export SDNS_ZONE_KEY=yourkey)"
    return 1
  fi
  _saveaccountconf_mutable SDNS_ZONE_KEY "$SDNS_ZONE_KEY"
  _debug "First detect the root zone"
  if ! _get_root "$fulldomain"; then
    _err "invalid domain"
    return 1
  fi
  _debug _sub_domain "$_sub_domain"
  _debug _domain "$_domain"
  _payload="<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>
<zoneRequest>
  <zone name=\"$_domain\" action=\"DELRR\"  ddnskey=\"$SDNS_ZONE_KEY\">
    <rr host=\"$_sub_domain\" type=\"TXT\" value=\"$txtvalue\" keepExisting=\"true\"/>
  </zone>
</zoneRequest>"
  _debug "$_payload"
  response=$(_post "$_payload" "$SDNS_API_URL")
  _debug "$response"
  if _contains "$response" "status=\"OK\""; then
    _debug "The TXT record has been deleted."
    return 0
  else
    _err "The attempt to delete the TXT record has failed."
    return 1
  fi
}

####################  Private functions below ##################################
#_acme-challenge.www.domain.com

#returns
# _sub_domain=_acme-challenge.www
# _domain=domain.com
_get_root() {
  fulldomain=$1
  _debug2 "_get_root() entered"
  SDNS_ZONE_KEY="${SDNS_ZONE_KEY:-$(_readaccountconf_mutable SDNS_ZONE_KEY)}"
  if [ -z "$SDNS_ZONE_KEY" ]; then
    SDNS_ZONE_KEY=""
    _err "You didn't specify your zone key yet. (export SDNS_ZONE_KEY=yourkey)"
    return 1
  fi
  _saveaccountconf_mutable SDNS_ZONE_KEY "$SDNS_ZONE_KEY"
  _payload="<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>
<zoneRequest action=\"getRootZone\" ddnskey=\"$SDNS_ZONE_KEY\">
  <hostname>$fulldomain</hostname>
</zoneRequest>"
  _debug2 "$_payload"
  response=$(_post "$_payload" "$SDNS_API_URL")
  _debug2 "$response"
  if _contains "$response" "status=\"found\""; then
    _debug "root domain is found"

    _domain=$(printf "%s\n" "$response" | _egrep_o "<zonename>(.*)</zonename>" | cut -d ">" -f 2 | cut -d "<" -f 1)
    _sub_domain=$(printf "%s\n" "$response" | _egrep_o "<hostname>(.*)</hostname>" | cut -d ">" -f 2 | cut -d "<" -f 1)

    _debug _domain "$_domain"
    _debug _sub_domain "$_sub_domain"
    return 0
  fi
}
