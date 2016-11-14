#!/usr/bin/env sh

# dns api wrapper of lexicon for acme.sh

lexicon_url="https://github.com/AnalogJ/lexicon"
lexicon_cmd="lexicon"

wiki="https://github.com/Neilpang/acme.sh/wiki/How-to-use-lexicon-dns-api"

########  Public functions #####################

#Usage: add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_lexicon_add() {
  fulldomain=$1
  txtvalue=$2

  domain=$(printf "%s" "$fulldomain" | cut -d . -f 2-999)

  if ! _exists "$lexicon_cmd"; then
    _err "Please install $lexicon_cmd first: $wiki"
    return 1
  fi

  if [ -z "$PROVIDER" ]; then
    PROVIDER=""
    _err "Please define env PROVIDER first: $wiki"
    return 1
  fi

  _savedomainconf PROVIDER "$PROVIDER"
  export PROVIDER

  Lx_name=$(echo LEXICON_"${PROVIDER}"_USERNAME | tr '[a-z]' '[A-Z]')
  Lx_name_v=$(eval echo \$"$Lx_name")
  _debug "$Lx_name" "$Lx_name_v"
  if [ "$Lx_name_v" ]; then
    _saveaccountconf "$Lx_name" "$Lx_name_v"
    eval export "$Lx_name"
  fi

  Lx_token=$(echo LEXICON_"${PROVIDER}"_TOKEN | tr '[a-z]' '[A-Z]')
  Lx_token_v=$(eval echo \$"$Lx_token")
  _debug "$Lx_token" "$Lx_token_v"
  if [ "$Lx_token_v" ]; then
    _saveaccountconf "$Lx_token" "$Lx_token_v"
    eval export "$Lx_token"
  fi

  Lx_password=$(echo LEXICON_"${PROVIDER}"_PASSWORD | tr '[a-z]' '[A-Z]')
  Lx_password_v=$(eval echo \$"$Lx_password")
  _debug "$Lx_password" "$Lx_password_v"
  if [ "$Lx_password_v" ]; then
    _saveaccountconf "$Lx_password" "$Lx_password_v"
    eval export "$Lx_password"
  fi

  Lx_domaintoken=$(echo LEXICON_"${PROVIDER}"_DOMAINTOKEN | tr '[a-z]' '[A-Z]')
  Lx_domaintoken_v=$(eval echo \$"$Lx_domaintoken")
  _debug "$Lx_domaintoken" "$Lx_domaintoken_v"
  if [ "$Lx_domaintoken_v" ]; then
    eval export "$Lx_domaintoken"
    _saveaccountconf "$Lx_domaintoken" "$Lx_domaintoken_v"
  fi

  $lexicon_cmd "$PROVIDER" create "${domain}" TXT --name="_acme-challenge.${domain}." --content="${txtvalue}"

}

#fulldomain
dns_lexicon_rm() {
  fulldomain=$1

}
