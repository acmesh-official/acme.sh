#!/usr/bin/env sh

# Author: Janos Lenart <janos@lenart.io>

########  Public functions #####################

# Usage: dns_gcloud_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_gcloud_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using gcloud"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _dns_gcloud_find_zone || return $?

  # Add an extra RR
  _dns_gcloud_start_tr || return $?
  _dns_gcloud_get_rrdatas || return $?
  echo "$rrdatas" | _dns_gcloud_remove_rrs || return $?
  printf "%s\n%s\n" "$rrdatas" "\"$txtvalue\"" | grep -v '^$' | _dns_gcloud_add_rrs || return $?
  _dns_gcloud_execute_tr || return $?

  _info "$fulldomain record added"
}

# Usage: dns_gcloud_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Remove the txt record after validation.
dns_gcloud_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using gcloud"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _dns_gcloud_find_zone || return $?

  # Remove one RR
  _dns_gcloud_start_tr || return $?
  _dns_gcloud_get_rrdatas || return $?
  echo "$rrdatas" | _dns_gcloud_remove_rrs || return $?
  echo "$rrdatas" | grep -F -v "\"$txtvalue\"" | _dns_gcloud_add_rrs || return $?
  _dns_gcloud_execute_tr || return $?

  _info "$fulldomain record added"
}

####################  Private functions below ##################################

_dns_gcloud_start_tr() {
  if ! trd=$(mktemp -d); then
    _err "_dns_gcloud_start_tr: failed to create temporary directory"
    return 1
  fi
  tr="$trd/tr.yaml"
  _debug tr "$tr"

  if ! gcloud dns record-sets transaction start \
    --transaction-file="$tr" \
    --zone="$managedZone"; then
    rm -r "$trd"
    _err "_dns_gcloud_start_tr: failed to execute transaction"
    return 1
  fi
}

_dns_gcloud_execute_tr() {
  if ! gcloud dns record-sets transaction execute \
    --transaction-file="$tr" \
    --zone="$managedZone"; then
    _debug tr "$(cat "$tr")"
    rm -r "$trd"
    _err "_dns_gcloud_execute_tr: failed to execute transaction"
    return 1
  fi
  rm -r "$trd"

  for i in $(seq 1 120); do
    if gcloud dns record-sets changes list \
      --zone="$managedZone" \
      --filter='status != done' \
      | grep -q '^.*'; then
      _info "_dns_gcloud_execute_tr: waiting for transaction to be comitted ($i/120)..."
      sleep 5
    else
      return 0
    fi
  done

  _err "_dns_gcloud_execute_tr: transaction is still pending after 10 minutes"
  rm -r "$trd"
  return 1
}

_dns_gcloud_remove_rrs() {
  if ! xargs -r gcloud dns record-sets transaction remove \
    --name="$fulldomain." \
    --ttl="$ttl" \
    --type=TXT \
    --zone="$managedZone" \
    --transaction-file="$tr"; then
    _debug tr "$(cat "$tr")"
    rm -r "$trd"
    _err "_dns_gcloud_remove_rrs: failed to remove RRs"
    return 1
  fi
}

_dns_gcloud_add_rrs() {
  ttl=60
  if ! xargs -r gcloud dns record-sets transaction add \
    --name="$fulldomain." \
    --ttl="$ttl" \
    --type=TXT \
    --zone="$managedZone" \
    --transaction-file="$tr"; then
    _debug tr "$(cat "$tr")"
    rm -r "$trd"
    _err "_dns_gcloud_add_rrs: failed to add RRs"
    return 1
  fi
}

_dns_gcloud_find_zone() {
  # Prepare a filter that matches zones that are suiteable for this entry.
  # For example, _acme-challenge.something.domain.com might need to go into something.domain.com or domain.com;
  # this function finds the longest postfix that has a managed zone.
  part="$fulldomain"
  filter="dnsName=( "
  while [ "$part" != "" ]; do
    filter="$filter$part. "
    part="$(echo "$part" | sed 's/[^.]*\.*//')"
  done
  filter="$filter)"
  _debug filter "$filter"

  # List domains and find the zone with the deepest sub-domain (in case of some levels of delegation)
  if ! match=$(gcloud dns managed-zones list \
    --format="value(name, dnsName)" \
    --filter="$filter" \
    | while read -r dnsName name; do
      printf "%s\t%s\t%s\n" "$(echo "$name" | awk -F"." '{print NF-1}')" "$dnsName" "$name"
    done \
      | sort -n -r | _head_n 1 | cut -f2,3 | grep '^.*'); then
    _err "_dns_gcloud_find_zone: Can't find a matching managed zone! Perhaps wrong project or gcloud credentials?"
    return 1
  fi

  dnsName=$(echo "$match" | cut -f2)
  _debug dnsName "$dnsName"
  managedZone=$(echo "$match" | cut -f1)
  _debug managedZone "$managedZone"
}

_dns_gcloud_get_rrdatas() {
  if ! rrdatas=$(gcloud dns record-sets list \
    --zone="$managedZone" \
    --name="$fulldomain." \
    --type=TXT \
    --format="value(ttl,rrdatas)"); then
    _err "_dns_gcloud_get_rrdatas: Failed to list record-sets"
    rm -r "$trd"
    return 1
  fi
  ttl=$(echo "$rrdatas" | cut -f1)
  rrdatas=$(echo "$rrdatas" | cut -f2 | sed 's/","/"\n"/g')
}
