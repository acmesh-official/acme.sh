#!/usr/bin/env sh

# Nearly Free Speech DNS API (https://www.nearlyfreespeech.net)
# Author: Travis Neely (https://github.com/Travisivart)
# Created: 2022-04-19

# Expected environment variables as such:
#
#    export NFS_ACCOUNT="your_nearly_free_speech_account"
#    export NFS_API_KEY="your_nearly_free_speech_api_key"
#

# Usage: dns_nfs_add _acme-challenge.domain.com "KjiayTfXPHmnHmOdevsOtJyzsU9AHw2T6R0lNVCl_oi"
dns_nfs_add() {
  FULLDOMAIN=$1
  ROOTDOMAIN=$(echo "$FULLDOMAIN" | awk -F '.' '{print $(NF-1)"."$NF}')
  SUBDOMAIN=$(echo "$FULLDOMAIN" | sed 's/.'"$ROOTDOMAIN"'//g')

  if [ "$SUBDOMAIN" = "$FULLDOMAIN" ]; then
    unset SUBDOMAIN
  fi

  _nfs_rest "/dns/$ROOTDOMAIN/addRR" "name=$SUBDOMAIN" 'type=TXT' "data=$2"
}

# Usage: dns_nfs_rm domain.com "KjiayTfXPHmnHmOdevsOtJyzsU9AHw2T6R0lNVCl_oi"
dns_nfs_rm() {
  FULLDOMAIN=$1
  ROOTDOMAIN=$(echo "$FULLDOMAIN" | awk -F '.' '{print $(NF-1)"."$NF}')
  SUBDOMAIN=$(echo "$FULLDOMAIN" | sed 's/.'"$ROOTDOMAIN"'//g')

  if [ "$SUBDOMAIN" = "$FULLDOMAIN" ]; then
    unset SUBDOMAIN
  fi

  _nfs_rest "/dns/$ROOTDOMAIN/removeRR" "name=$SUBDOMAIN" 'type=TXT' "data=$2"
}

####################  Private functions below ##################################
# Usage    add: _nfs_rest "/dns/domain.com/addRR" "name=" 'type=TXT' "data=KjiayTfXPHmnHmOdevsOtJyzsU9AHw2T6R0lNVCl_oi"
#       remove: _nfs_rest "/dns/domain.com/removeRR" "name=www" 'type=TXT' "data=KjiayTfXPHmnHmOdevsOtJyzsU9AHw2T6R0lNVCl_oi"
_nfs_rest() {

  # Make sure NFS_ACCOUNT is set else exit
  if [ -z "$NFS_ACCOUNT" ]; then
    echo "NFS_ACCOUNT is not set, run 'export NFS_ACCOUNT=\"your_nearly_free_speech_account\" and rerun."
    exit 1
  fi

  # Make sure NFS_API_KEY is set else exit
  if [ -z "$NFS_API_KEY" ]; then
    echo "NFS_API_KEY is not set, run 'export NFS_API_KEY=\"your_nearly_free_speech_api_key\" and rerun."
    exit 1
  fi

  TIMESTAMP=$(date +%s)
  SALT=$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 16)
  REQUEST_URI="$1"

  if [ "$#" -gt "1" ]; then
    PARAMETERS="$2"
  fi

  COUNT=3
  while test $COUNT -le $#; do
    eval "PARAMETER=\$$COUNT"
    # shellcheck disable=SC2153
    PARAMETERS="$PARAMETERS&$PARAMETER"
    COUNT=$((COUNT + 1))
  done

  BODY=$PARAMETERS
  BODY_HASH=$(printf "%s" "$BODY" | sha1sum | awk '{print $1}')
  HASH_STRING=$(printf "%s" "$NFS_ACCOUNT;$TIMESTAMP;$SALT;$NFS_API_KEY;$REQUEST_URI;$BODY_HASH")
  HASH=$(printf "%s" "$HASH_STRING" | sha1sum | awk '{print $1}')

  printf "%s" "$(curl -s -o - -k -X POST -H "X-NFSN-Authentication: $NFS_ACCOUNT;$TIMESTAMP;$SALT;$HASH" -d "$BODY" "https://api.nearlyfreespeech.net$REQUEST_URI")"
}
