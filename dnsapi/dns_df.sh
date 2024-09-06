#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_df_info='DynDnsFree.de
Domains: dynup.de
Site: DynDnsFree.de
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_df
Options:
 DF_user Username
 DF_password Password
Issues: github.com/acmesh-official/acme.sh/issues/2897
Author: Thilo Gass <thilo.gass@gmail.com>
'

dyndnsfree_api="https://dynup.de/acme.php"

dns_df_add() {
  fulldomain=$1
  txt_value=$2
  _info "Using DNS-01 dyndnsfree.de hook"

  DF_user="${DF_user:-$(_readaccountconf_mutable DF_user)}"
  DF_password="${DF_password:-$(_readaccountconf_mutable DF_password)}"
  if [ -z "$DF_user" ] || [ -z "$DF_password" ]; then
    DF_user=""
    DF_password=""
    _err "No auth details provided. Please set user credentials using the \$DF_user and \$DF_password environment variables."
    return 1
  fi
  #save the api user and password to the account conf file.
  _debug "Save user and password"
  _saveaccountconf_mutable DF_user "$DF_user"
  _saveaccountconf_mutable DF_password "$DF_password"

  domain="$(printf "%s" "$fulldomain" | cut -d"." -f2-)"

  get="$dyndnsfree_api?username=$DF_user&password=$DF_password&hostname=$domain&add_hostname=$fulldomain&txt=$txt_value"

  if ! erg="$(_get "$get")"; then
    _err "error Adding $fulldomain TXT: $txt_value"
    return 1
  fi

  if _contains "$erg" "success"; then
    _info "Success, TXT Added, OK"
  else
    _err "error Adding $fulldomain TXT: $txt_value erg: $erg"
    return 1
  fi

  _debug "ok Auto $fulldomain TXT: $txt_value erg: $erg"
  return 0
}

dns_df_rm() {

  fulldomain=$1
  txtvalue=$2
  _info "TXT enrty in $fulldomain is deleted automatically"
  _debug fulldomain "$fulldomain"
  _debug txtvalue "$txtvalue"

}
