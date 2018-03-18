#!/usr/bin/env sh

dns_maradns_add() {
	_checkZoneFile || return 1
	fulldomain="$1"
	txtvalue="$2"
	printf "%s. TXT '%s' ~\n" "$fulldomain" "$txtvalue" | tee -a "$MARA_ZONE_FILE" || return 1
	_try_reload_maradns
}

dns_maradns_rm() {
	_checkZoneFile || return 1
	fulldomain="$1"
	txtvalue="$2"
	sed -i "/^$fulldomain.\+TXT '$txtvalue' ~/d" "$MARA_ZONE_FILE"
	_try_reload_maradns
}

_checkZoneFile() {
	if [ -w "$MARA_ZONE_FILE" ]; then
		return 0
	fi
	_err "MARA_ZONE_FILE not set or not writable"
	return 1
}

_try_reload_maradns() {
	if [ -n "$MARA_DUENDE_PID" ]; then
		kill -s HUP -- "$MARA_DUENDE_PID"
		return $?
	fi
	if [ -r "$MARA_DUENDE_PID_PATH" ]; then
		kill -s HUP -- "$(cat $MARA_DUENDE_PID_PATH)"
		return $?
	fi
	_info "Reload MaraDNS manually (or provide MARA_DUENDE_PID or MARA_DUENDE_PID_PATH)"
}
