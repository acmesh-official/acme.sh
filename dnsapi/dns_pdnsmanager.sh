#!/usr/bin/env sh
#
# PDNS Manager wrapper script for acme.sh
#
# Author: Olle Gustafsson <olle@dalnix.se>
# Report Bugs here: Just send an email, there are no bugs ;)
#
# https://pdnsmanager.org/
# https://www.powerdns.com/
#
# This script is using PDNS Manager's API to update TXT record since giving API
# access to PowerDNS API itself is not possible for a single domain (or record).
#
# Before first run; export these variables or failure is imminent.
#
# export PDNS_MANAGER_URL=https://pdnsmanager.domain.nx
# export PDNS_MANAGER_RECORDID=
# export PDNS_MANAGER_PASSWORD=
#
# Then run:
#
# acme.sh --issue --staging --dns dns_pdnsmanager -d domaintovalidate.nx
#
# Remember to remove --staging in production
#

# Usage: dns_pdnsmanager_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"

dns_pdnsmanager_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using PDNS Manager"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  PDNS_MANAGER_URL="${PDNS_MANAGER_URL:-$(_readaccountconf_mutable PDNS_MANAGER_URL)}"
  PDNS_MANAGER_RECORDID="${PDNS_MANAGER_RECORDID:-$(_readaccountconf_mutable PDNS_MANAGER_RECORDID)}"
  PDNS_MANAGER_PASSWORD="${PDNS_MANAGER_PASSWORD:-$(_readaccountconf_mutable PDNS_MANAGER_PASSWORD)}"
  if [ -z "$PDNS_MANAGER_URL" ] || [ -z "$PDNS_MANAGER_RECORDID" ] || [ -z "$PDNS_MANAGER_PASSWORD" ]; then
    PDNS_MANAGER_URL=""
    PDNS_MANAGER_RECORDID=""
    PDNS_MANAGER_PASSWORD=""
    _err "PDNS_MANAGER_URL, PDNS_MANAGER_RECORDID and/or PDNS_MANAGER_PASSWORD is missing!"
    _err "Please export these variables and try again."
    return 1
  fi

  _saveaccountconf_mutable PDNS_MANAGER_RECORDID "$PDNS_MANAGER_RECORDID"
  _saveaccountconf_mutable PDNS_MANAGER_PASSWORD "$PDNS_MANAGER_PASSWORD"

  _get "${PDNS_MANAGER_URL}/api/v1/remote/updatepw?record=${PDNS_MANAGER_RECORDID}&password=${PDNS_MANAGER_PASSWORD}&content=${txtvalue}"

  return 0
}

# Usage: fulldomain txtvalue
# Remove the txt record after validation.
#
# Not implemented since no new records will be created.
dns_pdnsmanager_rm() {
  fulldomain=$1
  txtvalue=$2
  # _info "Using PDNS Manager"
  # _debug fulldomain "$fulldomain"
  # _debug txtvalue "$txtvalue"
}
