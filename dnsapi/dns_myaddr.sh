#!/usr/bin/env sh

dns_myaddr_add() {
  fulldomain=$1
  txtvalue=$2

  myaddr_key="${myaddr_key:-$(_readaccountconf_mutable myaddr_key)}"
  if [ -z "$myaddr_key" ]; then
    myaddr_key=""
    _err "You don't specify api key yet."
    _err "Please create your key and try again."
    return 1
  fi

  #save the credentials to the account conf file.
  _saveaccountconf_mutable myaddr_key "$myaddr_key"

  data="key=${myaddr_key}&acme_challenge=${txtvalue}"
  _post "${data}" 'https://myaddr.tools/update'

  if [ "$?" != "0" ]; then
    _err "Failed to send message"
  fi
}

dns_myaddr_rm() {
  #this is just to prevent an error in acme.sh, myaddr will automatic remove the txts after few minutes
  fulldomain=$1
}
