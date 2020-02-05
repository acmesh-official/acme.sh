#!/usr/bin/env sh

# This API is a wrapper for other API so that you
# are able to put your TXT record to multiple providers.
# The functionality is in the responsibility of the respective API
# therefore please check if your used APIs work.
# e.g. for using NS1 and AWS Route53, use:
# OCTODNS_PROVIDERS=nsone_aws
# --dns octodns
#
# Author: Josef Vogt
#
########  Public functions #####################
dns_octodns_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Creating DNS entries via octoDNS"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  if [ -z "$OCTODNS_PROVIDERS" ]; then
    OCTODNS_PROVIDERS=""
    _err "You didn't specify OCTODNS_PROVIDERS yet."
    _err "Please specifiy your providers and try again."
    return 1
  fi

  #save the providers list to the account conf file.
  _saveaccountconf OCTODNS_PROVIDERS "$OCTODNS_PROVIDERS"

  for element in $(echo "$OCTODNS_PROVIDERS" | tr "_" ' '); do
    _debug element "$element"
    sourcecommand="$_SUB_FOLDER_DNSAPI/dns_${element}.sh"

    # shellcheck disable=SC1090
    if ! . "$sourcecommand"; then
      _err "Load file $sourcecommand error. Please check your api file and try again."
      return 1
    fi

    addcommand="dns_${element}_add"
    _debug addcommand "$addcommand"
    $addcommand "$fulldomain" "$txtvalue"
  done

  _info "Finished adding records via octoDNS API"

  return 0
}

#Remove the txt record after validation.
dns_octodns_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Removing DNS entries via octoDNS"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  if [ -z "$OCTODNS_PROVIDERS" ]; then
    OCTODNS_PROVIDERS=""
    _err "You didn't specify OCTODNS_PROVIDERS yet."
    _err "Please specifiy your providers and try again."
    return 1
  fi

  for element in $(echo "$OCTODNS_PROVIDERS" | tr "_" ' '); do
    _debug element "$element"
    sourcecommand="$_SUB_FOLDER_DNSAPI/dns_${element}.sh"

    # shellcheck disable=SC1090
    if ! . "$sourcecommand"; then
      _err "Load file $sourcecommand error. Please check your api file and try again."
      return 1
    fi

    rmcommand="dns_${element}_rm"
    _debug rmcommand "$rmcommand"
    $rmcommand "$fulldomain" "$txtvalue"
  done

  _info "Finished deleting records via octoDNS API"

  return 0
}
