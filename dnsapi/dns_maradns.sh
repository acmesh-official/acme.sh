#!/usr/bin/env sh

#Usage: dns_maradns_add _acme-challenge.www.domain.com "token"
dns_maradns_add() {
  fulldomain="$1"
  txtvalue="$2"

  MARA_ZONE_FILE="${MARA_ZONE_FILE:-$(_readaccountconf_mutable MARA_ZONE_FILE)}"
  MARA_DUENDE_PID_PATH="${MARA_DUENDE_PID_PATH:-$(_readaccountconf_mutable MARA_DUENDE_PID_PATH)}"

  _check_zone_file "$MARA_ZONE_FILE" || return 1
  _check_duende_pid_path "$MARA_DUENDE_PID_PATH" || return 1

  _saveaccountconf_mutable MARA_ZONE_FILE "$MARA_ZONE_FILE"
  _saveaccountconf_mutable MARA_DUENDE_PID_PATH "$MARA_DUENDE_PID_PATH"

  printf "%s. TXT '%s' ~\n" "$fulldomain" "$txtvalue" >>"$MARA_ZONE_FILE"
  _reload_maradns "$MARA_DUENDE_PID_PATH" || return 1
}

#Usage: dns_maradns_rm _acme-challenge.www.domain.com "token"
dns_maradns_rm() {
  fulldomain="$1"
  txtvalue="$2"

  MARA_ZONE_FILE="${MARA_ZONE_FILE:-$(_readaccountconf_mutable MARA_ZONE_FILE)}"
  MARA_DUENDE_PID_PATH="${MARA_DUENDE_PID_PATH:-$(_readaccountconf_mutable MARA_DUENDE_PID_PATH)}"

  _check_zone_file "$MARA_ZONE_FILE" || return 1
  _check_duende_pid_path "$MARA_DUENDE_PID_PATH" || return 1

  _saveaccountconf_mutable MARA_ZONE_FILE "$MARA_ZONE_FILE"
  _saveaccountconf_mutable MARA_DUENDE_PID_PATH "$MARA_DUENDE_PID_PATH"

  _sed_i "/^$fulldomain.\+TXT '$txtvalue' ~/d" "$MARA_ZONE_FILE"
  _reload_maradns "$MARA_DUENDE_PID_PATH" || return 1
}

_check_zone_file() {
  zonefile="$1"
  if [ -z "$zonefile" ]; then
    _err "MARA_ZONE_FILE not passed!"
    return 1
  elif [ ! -w "$zonefile" ]; then
    _err "MARA_ZONE_FILE not writable: $zonefile"
    return 1
  fi
}

_check_duende_pid_path() {
  pidpath="$1"
  if [ -z "$pidpath" ]; then
    _err "MARA_DUENDE_PID_PATH not passed!"
    return 1
  fi
  if [ ! -r "$pidpath" ]; then
    _err "MARA_DUENDE_PID_PATH not readable: $pidpath"
    return 1
  fi
}

_reload_maradns() {
  pidpath="$1"
  kill -s HUP -- "$(cat "$pidpath")"
  if [ $? -ne 0 ]; then
    _err "Unable to reload MaraDNS, kill returned $?"
    return 1
  fi
}
