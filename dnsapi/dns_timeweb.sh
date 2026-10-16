#!/usr/bin/env sh
# shellcheck disable=SC2034
dns_timeweb_info='Timeweb.Cloud
Site: Timeweb.Cloud
Docs: github.com/acmesh-official/acme.sh/wiki/dnsapi2#dns_timeweb
Options:
 TW_Token API JWT token. Get it from the control panel at https://timeweb.cloud/my/api-keys
Issues: github.com/acmesh-official/acme.sh/issues/5140
Author: Aleksandr <@augin>
'
# Timeweb Cloud DNS API v2 — Proxmox ACME DNS plugin

TW_API="https://api.timeweb.cloud/api/v2"

########### PUBLIC FUNCTIONS ###########

dns_timeweb_add() {
    FQDN="$1"
    TXT_VALUE="$2"

    _debug "ADD: FQDN=$FQDN TXT=$TXT_VALUE"

    _load_token || return 1
    _add_txt_record "$FQDN" "$TXT_VALUE" || return 1

    # Сохраняем ID записи для удаления
    echo "$RECORD_ID" > "/tmp/timeweb_${FQDN}.id"

    return 0
}

dns_timeweb_rm() {
    FQDN="$1"
    TXT_VALUE="$2"

    _debug "RM: FQDN=$FQDN TXT=$TXT_VALUE"

    _load_token || return 1

    ID_FILE="/tmp/timeweb_${FQDN}.id"

    if [ ! -f "$ID_FILE" ]; then
        echo "Record ID file not found: $ID_FILE" >&2
        return 1
    fi

    RECORD_ID="$(cat "$ID_FILE")"

    _delete_record "$FQDN" "$RECORD_ID" || return 1

    rm -f "$ID_FILE"

    return 0
}

########### INTERNAL HELPERS ###########

_load_token() {
    if [ -z "$TW_Token" ]; then
        echo "TW_Token not set" >&2
        return 1
    fi
    return 0
}

_debug() {
    echo "[timeweb] $1"
}

_add_txt_record() {
    DOMAIN="$1"
    VALUE="$2"

    BODY=$(printf '{"type":"TXT","value":"%s","ttl":300}' "$VALUE")

    RESP="$(curl -s -X POST \
        -H "Authorization: Bearer $TW_Token" \
        -H "Content-Type: application/json" \
        -d "$BODY" \
        "$TW_API/domains/$DOMAIN/dns-records")"

    RECORD_ID="$(echo "$RESP" | grep -o '"id":[0-9]*' | head -n1 | cut -d: -f2)"

    if [ -z "$RECORD_ID" ]; then
        echo "Failed to add TXT record" >&2
        echo "Response: $RESP" >&2
        return 1
    fi

    _debug "TXT added, id=$RECORD_ID"
    return 0
}

_delete_record() {
    DOMAIN="$1"
    ID="$2"

    curl -s -X DELETE \
        -H "Authorization: Bearer $TW_Token" \
        "$TW_API/domains/$DOMAIN/dns-records/$ID" >/dev/null

    _debug "Deleted TXT id=$ID"
    return 0
}
