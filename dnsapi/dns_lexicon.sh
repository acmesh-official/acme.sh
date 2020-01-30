#!/usr/bin/env sh

# dns api wrapper of lexicon for acme.sh

# https://github.com/AnalogJ/lexicon
lexicon_cmd="lexicon"

wiki="https://github.com/acmesh-official/acme.sh/wiki/How-to-use-lexicon-dns-api"

_lexicon_init() {
  if ! _exists "$lexicon_cmd"; then
    _err "Please install $lexicon_cmd first: $wiki"
    return 1
  fi

  PROVIDER="${PROVIDER:-$(_readdomainconf PROVIDER)}"
  if [ -z "$PROVIDER" ]; then
    PROVIDER=""
    _err "Please define env PROVIDER first: $wiki"
    return 1
  fi

  _savedomainconf PROVIDER "$PROVIDER"
  export PROVIDER

  # e.g. busybox-ash does not know [:upper:]
  # shellcheck disable=SC2018,SC2019
  Lx_name=$(echo LEXICON_"${PROVIDER}"_USERNAME | tr 'a-z' 'A-Z')
  eval "$Lx_name=\${$Lx_name:-$(_readaccountconf_mutable "$Lx_name")}"
  Lx_name_v=$(eval echo \$"$Lx_name")
  _secure_debug "$Lx_name" "$Lx_name_v"
  if [ "$Lx_name_v" ]; then
    _saveaccountconf_mutable "$Lx_name" "$Lx_name_v"
    eval export "$Lx_name"
  fi

  # shellcheck disable=SC2018,SC2019
  Lx_token=$(echo LEXICON_"${PROVIDER}"_TOKEN | tr 'a-z' 'A-Z')
  eval "$Lx_token=\${$Lx_token:-$(_readaccountconf_mutable "$Lx_token")}"
  Lx_token_v=$(eval echo \$"$Lx_token")
  _secure_debug "$Lx_token" "$Lx_token_v"
  if [ "$Lx_token_v" ]; then
    _saveaccountconf_mutable "$Lx_token" "$Lx_token_v"
    eval export "$Lx_token"
  fi

  # shellcheck disable=SC2018,SC2019
  Lx_password=$(echo LEXICON_"${PROVIDER}"_PASSWORD | tr 'a-z' 'A-Z')
  eval "$Lx_password=\${$Lx_password:-$(_readaccountconf_mutable "$Lx_password")}"
  Lx_password_v=$(eval echo \$"$Lx_password")
  _secure_debug "$Lx_password" "$Lx_password_v"
  if [ "$Lx_password_v" ]; then
    _saveaccountconf_mutable "$Lx_password" "$Lx_password_v"
    eval export "$Lx_password"
  fi

  # shellcheck disable=SC2018,SC2019
  Lx_domaintoken=$(echo LEXICON_"${PROVIDER}"_DOMAINTOKEN | tr 'a-z' 'A-Z')
  eval "$Lx_domaintoken=\${$Lx_domaintoken:-$(_readaccountconf_mutable "$Lx_domaintoken")}"
  Lx_domaintoken_v=$(eval echo \$"$Lx_domaintoken")
  _secure_debug "$Lx_domaintoken" "$Lx_domaintoken_v"
  if [ "$Lx_domaintoken_v" ]; then
    _saveaccountconf_mutable "$Lx_domaintoken" "$Lx_domaintoken_v"
    eval export "$Lx_domaintoken"
  fi

  # shellcheck disable=SC2018,SC2019
  Lx_api_key=$(echo LEXICON_"${PROVIDER}"_API_KEY | tr 'a-z' 'A-Z')
  eval "$Lx_api_key=\${$Lx_api_key:-$(_readaccountconf_mutable "$Lx_api_key")}"
  Lx_api_key_v=$(eval echo \$"$Lx_api_key")
  _secure_debug "$Lx_api_key" "$Lx_api_key_v"
  if [ "$Lx_api_key_v" ]; then
    _saveaccountconf_mutable "$Lx_api_key" "$Lx_api_key_v"
    eval export "$Lx_api_key"
  fi
}

########  Public functions #####################

#Usage: dns_lexicon_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_lexicon_add() {
  fulldomain=$1
  txtvalue=$2

  if ! _lexicon_init; then
    return 1
  fi

  domain=$(printf "%s" "$fulldomain" | cut -d . -f 2-999)

  _secure_debug LEXICON_OPTS "$LEXICON_OPTS"
  _savedomainconf LEXICON_OPTS "$LEXICON_OPTS"

  # shellcheck disable=SC2086
  $lexicon_cmd "$PROVIDER" $LEXICON_OPTS create "${domain}" TXT --name="_acme-challenge.${domain}." --content="${txtvalue}"

}

#Usage: dns_lexicon_rm   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
dns_lexicon_rm() {
  fulldomain=$1
  txtvalue=$2

  if ! _lexicon_init; then
    return 1
  fi

  domain=$(printf "%s" "$fulldomain" | cut -d . -f 2-999)

  # shellcheck disable=SC2086
  $lexicon_cmd "$PROVIDER" $LEXICON_OPTS delete "${domain}" TXT --name="_acme-challenge.${domain}." --content="${txtvalue}"

}
