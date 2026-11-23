#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_acmedns_multi_info='acme-dns Server API (one account per domain)
 The acme-dns server stores only two TXT values per subdomain.
 This plugin keeps one small account file per domain, so a single
 certificate can cover many domains, each with its own subdomain.
 The first run for a domain registers an account and stops with the
 CNAME record to publish. Publish it, then run the same command again.
 With N new domains this run/publish/rerun cycle repeats N times, as
 the order only completes once every challenge name has a live CNAME.
Site: github.com/joohoi/acme-dns
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_acmedns_multi
Options:
 ACMEDNS_CONF_DIR Directory with one "<domain>.conf" per domain. Optional.
 ACMEDNS_BASE_URL Base URL. Default "https://auth.acme-dns.io".
 ACMEDNS_SUBDOMAIN Subdomain of a single shared account. Optional.
 ACMEDNS_USERNAME Username of a single shared account. Optional.
 ACMEDNS_PASSWORD Password of a single shared account. Optional.
 The subdomain, username and password of a per-domain account are read
 from its account file only, so the environment can never complete a
 partial file. The base URL is resolved as: account file > environment
 > account.conf (legacy ACMEDNS_UPDATE_URL) > default.
 ACMEDNS_UPDATE_URL is not an option: the update endpoint is always
 "<base URL>/update", so a stale value can never redirect an account.
'

########  Public functions #####################

#Usage: dns_acmedns_multi_add   _acme-challenge.www.domain.com   "XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs"
# Used to add txt record
dns_acmedns_multi_add() {
  fulldomain=$1
  txtvalue=$2
  _info "Using acme-dns (one account per domain)"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

  _acmedns_load "$fulldomain" || return 1

  if [ -z "$_acmedns_subdomain" ] || [ -z "$_acmedns_username" ] || [ -z "$_acmedns_password" ]; then
    # Never replace an existing account: the CNAME published for the old uuid
    # would stop matching and the order would fail in a confusing way.
    if [ -f "$_acmedns_file" ]; then
      _err "acme-dns: $_acmedns_file exists but is incomplete"
      _err "Fix the file, or delete it to register a new account (then update the CNAME)."
      return 1
    fi
    _acmedns_register "$fulldomain" || return 1
  fi

  export _H1="X-Api-User: $_acmedns_username"
  export _H2="X-Api-Key: $_acmedns_password"
  _acmedns_data="{\"subdomain\": \"$_acmedns_subdomain\", \"txt\": \"$txtvalue\"}"
  _acmedns_response="$(_post "$_acmedns_data" "$_acmedns_update_url" "" "POST" "application/json")"
  unset _H1
  unset _H2
  _debug response "$_acmedns_response"

  if ! _contains "$_acmedns_response" "$txtvalue"; then
    _err "acme-dns: the server rejected the update for $fulldomain"
    _err "Please check the account file: $_acmedns_file"
    return 1
  fi

  _info "acme-dns: TXT record added for $fulldomain"
  return 0
}

#Usage: fulldomain txtvalue
#Remove the txt record after validation.
dns_acmedns_multi_rm() {
  fulldomain=$1
  txtvalue=$2
  _info "Using acme-dns (one account per domain)"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"
  # The acme-dns API has no endpoint to delete a TXT value. The values expire
  # on their own: the served TXT records use a TTL of one second and the
  # server keeps at most two values per subdomain.
  return 0
}

####################  Private functions below ##################################

# domain from the challenge name: _acme-challenge.www.example.com -> www.example.com
_acmedns_domain() {
  _domain="${1#_acme-challenge.}"
  _domain="$(printf "%s" "$_domain" | _lower_case)"
  printf "%s" "${_domain%.}"
}

# Read a small env file in a subshell and print the four known values,
# one per line. Values may be quoted or unquoted.
_acmedns_read_conf() {
  _conf_file="$1"
  [ -f "$_conf_file" ] || return 1
  # shellcheck disable=SC1090
  (
    # Only the file may contribute values: unset first, or exported shared
    # credentials would leak into a partial account file. "${VAR:-}" keeps a
    # partial file working under "set -u" without assigning in the subshell.
    unset ACMEDNS_BASE_URL ACMEDNS_SUBDOMAIN ACMEDNS_USERNAME ACMEDNS_PASSWORD
    set -a
    . "$_conf_file" >/dev/null 2>&1
    printf "%s\n%s\n%s\n%s\n" "${ACMEDNS_BASE_URL:-}" "${ACMEDNS_SUBDOMAIN:-}" "${ACMEDNS_USERNAME:-}" "${ACMEDNS_PASSWORD:-}"
  ) || return 1
}

# Old versions of dns_acmedns stored the update URL in account.conf. Honour it
# only when no base URL is known, and strip the "/update" suffix.
_acmedns_legacy_base_url() {
  _legacy_update_url="$(_readaccountconf_mutable ACMEDNS_UPDATE_URL)"
  printf "%s" "${_legacy_update_url%/update}"
}

# Resolve a directory to an absolute path. A relative override must not be
# resolved again by a later run from a different working directory.
_acmedns_abs_dir() {
  case "$1" in
  /*) _acmedns_abs="$1" ;;
  *) _acmedns_abs="$(pwd)/$1" ;;
  esac
  _acmedns_abs="$(printf "%s" "$_acmedns_abs" | sed 's|/\./|/|g')"
  if [ -d "$_acmedns_abs" ]; then
    (cd "$_acmedns_abs" && pwd -P)
  else
    printf "%s" "$_acmedns_abs"
  fi
}

# Resolve the account for one challenge name.
# Priority: per-domain file > environment > account.conf > default base url.
# The account file wins on purpose: the environment must not be able to point
# a private account at another server (the official dns_acmedns lets it).
_acmedns_load() {
  _acmedns_fulldomain="$1"
  _acmedns_domain_name="$(_acmedns_domain "$_acmedns_fulldomain")"
  # A custom directory must survive the next cron run, which does not have
  # the environment of the current shell.
  _acmedns_saved_dir="$(_readaccountconf_mutable ACMEDNS_CONF_DIR)"
  _acmedns_dir="${ACMEDNS_CONF_DIR:-$_acmedns_saved_dir}"
  if [ -z "$_acmedns_dir" ]; then
    _acmedns_dir="${LE_CONFIG_HOME:-$LE_WORKING_DIR}/acmedns"
  fi
  # Cron runs from another working directory, so resolve the override here and
  # store it absolutely: a relative value such as "./accounts" would otherwise
  # point somewhere else on renewal, miss the account file and register a
  # replacement account whose CNAME is not published.
  _acmedns_dir="$(_acmedns_abs_dir "$_acmedns_dir")"
  if [ "$ACMEDNS_CONF_DIR" ] && [ "$_acmedns_dir" != "$_acmedns_saved_dir" ]; then
    _saveaccountconf_mutable ACMEDNS_CONF_DIR "$_acmedns_dir"
  fi
  _acmedns_file="$_acmedns_dir/$_acmedns_domain_name.conf"
  _acmedns_from_env=0
  _acmedns_from_file=0

  _acmedns_base_url=""
  _acmedns_subdomain=""
  _acmedns_username=""
  _acmedns_password=""

  if [ -f "$_acmedns_file" ]; then
    if ! _acmedns_values="$(_acmedns_read_conf "$_acmedns_file")"; then
      _err "acme-dns: cannot read the account file $_acmedns_file"
      return 1
    fi
    _debug "Read the account file" "$_acmedns_file"
    _acmedns_from_file=1
    _acmedns_base_url="$(printf "%s\n" "$_acmedns_values" | sed -n '1p')"
    _acmedns_subdomain="$(printf "%s\n" "$_acmedns_values" | sed -n '2p')"
    _acmedns_username="$(printf "%s\n" "$_acmedns_values" | sed -n '3p')"
    _acmedns_password="$(printf "%s\n" "$_acmedns_values" | sed -n '4p')"

    # The account file is self-contained and authoritative: shared credentials
    # from the environment or from account.conf must not fill in missing
    # fields, or they would be sent to whatever instance this file names.
    if [ -z "$_acmedns_base_url" ]; then
      _acmedns_base_url="${ACMEDNS_BASE_URL:-$(_readaccountconf_mutable ACMEDNS_BASE_URL)}"
    fi
    if [ -z "$_acmedns_base_url" ]; then
      _acmedns_base_url="$(_acmedns_legacy_base_url)"
    fi
    if [ -z "$_acmedns_base_url" ]; then
      _acmedns_base_url="https://auth.acme-dns.io"
    fi
    _acmedns_update_url="$_acmedns_base_url/update"
    return 0
  fi

  _acmedns_subdomain="${ACMEDNS_SUBDOMAIN:-$(_readaccountconf_mutable ACMEDNS_SUBDOMAIN)}"
  if [ "$_acmedns_subdomain" ]; then
    _acmedns_from_env=1
  fi
  _acmedns_username="${ACMEDNS_USERNAME:-$(_readaccountconf_mutable ACMEDNS_USERNAME)}"
  _acmedns_password="${ACMEDNS_PASSWORD:-$(_readaccountconf_mutable ACMEDNS_PASSWORD)}"
  _acmedns_base_url="${ACMEDNS_BASE_URL:-$(_readaccountconf_mutable ACMEDNS_BASE_URL)}"
  if [ -z "$_acmedns_base_url" ]; then
    _acmedns_base_url="$(_acmedns_legacy_base_url)"
  fi
  if [ -z "$_acmedns_base_url" ]; then
    _acmedns_base_url="https://auth.acme-dns.io"
  fi

  # The update endpoint always follows the base URL: ACMEDNS_UPDATE_URL is not
  # an option of dns_acmedns and must never redirect an account elsewhere.
  _acmedns_update_url="$_acmedns_base_url/update"

  # A shared account given on the command line must survive the next cron run.
  if [ "$_acmedns_from_env" = "1" ] && [ "$_acmedns_from_file" = "0" ]; then
    _saveaccountconf_mutable ACMEDNS_BASE_URL "$_acmedns_base_url"
    _saveaccountconf_mutable ACMEDNS_SUBDOMAIN "$_acmedns_subdomain"
    _saveaccountconf_mutable ACMEDNS_USERNAME "$_acmedns_username"
    _saveaccountconf_mutable ACMEDNS_PASSWORD "$_acmedns_password"
  fi
  return 0
}

# Wait for the account file written by a parallel run and load it.
_acmedns_wait_for_file() {
  _acmedns_try=0
  while [ "$_acmedns_try" -lt 5 ]; do
    if _acmedns_load "$_acmedns_fulldomain" &&
      [ -n "$_acmedns_subdomain" ] &&
      [ -n "$_acmedns_username" ] &&
      [ -n "$_acmedns_password" ]; then
      return 0
    fi
    _acmedns_try=$(_math "$_acmedns_try" + 1)
    _sleep 1
  done
  return 1
}

# Register a new acme-dns account for this challenge name, store it and stop
# with the CNAME record the user has to publish before the next run.
_acmedns_register() {
  _acmedns_reg_url="$_acmedns_base_url/register"
  _info "acme-dns: no account for $_acmedns_domain_name, requesting a new one"
  _acmedns_register_response="$(_post "" "$_acmedns_reg_url" "" "POST")"
  _secure_debug2 register "$_acmedns_register_response"

  _acmedns_subdomain="$(printf "%s" "$_acmedns_register_response" | sed -n 's/.*"subdomain"[ ]*:[ ]*"\([^"]*\)".*/\1/p')"
  _acmedns_username="$(printf "%s" "$_acmedns_register_response" | sed -n 's/.*"username"[ ]*:[ ]*"\([^"]*\)".*/\1/p')"
  _acmedns_password="$(printf "%s" "$_acmedns_register_response" | sed -n 's/.*"password"[ ]*:[ ]*"\([^"]*\)".*/\1/p')"
  _acmedns_fulldomain_reg="$(printf "%s" "$_acmedns_register_response" | sed -n 's/.*"fulldomain"[ ]*:[ ]*"\([^"]*\)".*/\1/p')"

  if [ -z "$_acmedns_subdomain" ] || [ -z "$_acmedns_username" ] || [ -z "$_acmedns_password" ]; then
    _err "acme-dns: could not register an account at $_acmedns_reg_url"
    return 1
  fi

  if [ ! -d "$_acmedns_dir" ]; then
    (umask 077 && mkdir -p "$_acmedns_dir") || {
      _err "acme-dns: cannot create the account directory $_acmedns_dir"
      return 1
    }
  fi

  # Create the file exclusively: a parallel run may have registered another
  # account for the same challenge name in the meantime. That account is the
  # one whose CNAME the user was told to publish, so never truncate it.
  if ! (set -C && umask 077 && : >"$_acmedns_file") 2>/dev/null; then
    _info "acme-dns: another run saved an account for $_acmedns_domain_name, reusing it"
    _acmedns_wait_for_file || {
      _err "acme-dns: $_acmedns_file exists but is not readable yet, please run again"
      return 1
    }
    return 0
  fi
  printf "# acme-dns account for %s\n" "$_acmedns_domain_name" >>"$_acmedns_file" || {
    _err "acme-dns: cannot write the account file $_acmedns_file"
    return 1
  }
  if ! _save_conf "$_acmedns_file" ACMEDNS_BASE_URL "$_acmedns_base_url" ||
    ! _save_conf "$_acmedns_file" ACMEDNS_SUBDOMAIN "$_acmedns_subdomain" ||
    ! _save_conf "$_acmedns_file" ACMEDNS_USERNAME "$_acmedns_username" ||
    ! _save_conf "$_acmedns_file" ACMEDNS_PASSWORD "$_acmedns_password"; then
    _err "acme-dns: cannot write the account file $_acmedns_file"
    return 1
  fi
  if ! chmod 600 "$_acmedns_file"; then
    _err "acme-dns: cannot restrict the permissions of $_acmedns_file"
    return 1
  fi
  _debug "Saved the new account to" "$_acmedns_file"

  _err "acme-dns: a new account was created for $_acmedns_domain_name"
  _err "Add this record to your DNS zone:"
  # Print the exact name acme.sh asked us to validate: with --domain-alias it
  # is the alias name, not "_acme-challenge.<domain>".
  _err "  $_acmedns_fulldomain.  CNAME  $_acmedns_fulldomain_reg."
  _err "Then run the same command again. Every new domain in the order needs"
  _err "this run/publish/rerun cycle once, because the order stops at the"
  _err "first challenge name that has no account file yet."
  return 1
}
