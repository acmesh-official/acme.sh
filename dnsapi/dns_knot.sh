#!/usr/bin/env sh

########  Public functions #####################

#Usage: dns_knot_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_knot_add() {
  fulldomain=$1
  txtvalue=$2
  _checkKey || return 1
  [ -n "${KNOT_SERVER}" ] || KNOT_SERVER="localhost"
  # save the dns server and key to the account.conf file.
  _saveaccountconf KNOT_SERVER "${KNOT_SERVER}"
  _saveaccountconf KNOT_KEY "${KNOT_KEY}"

  if ! _get_root "$fulldomain"; then
    _err "Domain does not exist."
    return 1
  fi

  _info "Adding ${fulldomain}. 60 TXT \"${txtvalue}\""

  knsupdate -y "${KNOT_KEY}" <<EOF
server ${KNOT_SERVER}
zone ${_domain}.
update add ${fulldomain}. 60 TXT "${txtvalue}"
send
quit
EOF

  if [ $? -ne 0 ]; then
    _err "Error updating domain."
    return 1
  fi

  _info "Domain TXT record successfully added."
  return 0
}

#Usage: dns_knot_rm   _acme-challenge.www.domain.com
dns_knot_rm() {
  fulldomain=$1
  _checkKey || return 1
  [ -n "${KNOT_SERVER}" ] || KNOT_SERVER="localhost"

  if ! _get_root "$fulldomain"; then
    _err "Domain does not exist."
    return 1
  fi

  _info "Removing ${fulldomain}. TXT"

  knsupdate -y "${KNOT_KEY}" <<EOF
server ${KNOT_SERVER}
zone ${_domain}.
update del ${fulldomain}. TXT
send
quit
EOF

  if [ $? -ne 0 ]; then
    _err "error updating domain"
    return 1
  fi

  _info "Domain TXT record successfully deleted."
  return 0
}

####################  Private functions below ##################################
# _acme-challenge.www.domain.com
# returns
# _domain=domain.com
_get_root() {
  ancestor="${1}."

  while true; do # loops over all ancestors of $1

    # count labels
    num_labels="$(echo "$ancestor" | tr '.' ' ' | wc -w)"

    # abort if empty
    if [ "$num_labels" -eq "0" ]; then
      # error: could not find SOA record anywhere
      _debug "no SOA record found in any ancestor of $1"
      return 1
    fi

    # query for SOA at current ancestor
    if [ -n "$(dig SOA +short "${ancestor}")" ]; then
      # found SOA record
      _info "found SOA at $ancestor"
      _domain="${ancestor%?}"
      return 0
    fi

    # cut one label from the left
    ancestor=$(printf "%s" "${ancestor}" | cut -d . -f 2-)
  done
}

_checkKey() {
  if [ -z "${KNOT_KEY}" ]; then
    _err "You must specify a TSIG key to authenticate the request."
    return 1
  fi
}
