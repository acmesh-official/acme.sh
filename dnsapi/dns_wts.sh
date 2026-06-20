#!/usr/bin/env sh

# Wärner Technologie Services – acme.sh DNS API Module
# https://waerner-techservices.de
#
# Author: Wärner Technologie Services <info@waerner-techservices.de>
# Repository: https://github.com/acmesh-official/acme.sh
#
# Usage:
#   export WTS_KEY="your-reselling-api-key"
#   export WTS_URL="https://api.reselling.services/api/v1"   # optional, default shown
#   ./acme.sh --issue --dns dns_wts -d example.com -d '*.example.com'
#
# Credentials are stored in ~/.acme.sh/account.conf after first use.
#
# Required DNS permissions on the API key:
#   - dns/zone/record/create
#   - dns/zone/record/delete
#   - domain/dns (read DNS records)

# API base URL (override via WTS_URL env variable)
WTS_API_DEFAULT="https://api.reselling.services/api/v1"

###############################################################################
# dns_wts_add  <fulldomain> <txtvalue>
#
# Called by acme.sh to add the ACME DNS-01 challenge TXT record.
# fulldomain  e.g. _acme-challenge.www.example.com
# txtvalue    e.g. XKrxpRBosdIKFzxW_CT3KLZNf6q0HG9i01zxXp5CPBs
###############################################################################
dns_wts_add() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Wärner Technologie Services DNS API – TXT record hinzufügen"
  _debug fulldomain "$fulldomain"
  _debug txtvalue   "$txtvalue"

  if ! _wts_load_credentials; then
    return 1
  fi

  # Root-Zone und Sub-Host ermitteln
  if ! _wts_get_root "$fulldomain"; then
    _err "Root-Zone konnte nicht ermittelt werden für: $fulldomain"
    return 1
  fi

  _debug "_domain  (zone)" "$_domain"
  _debug "_sub_domain"     "$_sub_domain"

  # TXT-Record anlegen
  _info "Erstelle TXT-Record: $_sub_domain IN TXT \"$txtvalue\" (Zone: $_domain)"

  _wts_api_post "/dns/zone/record/create" \
    "{\"zoneName\":\"${_domain}\",\"name\":\"${_sub_domain}\",\"type\":\"TXT\",\"content\":\"${txtvalue}\",\"ttl\":60}"

  if [ "$?" != "0" ]; then
    _err "TXT-Record konnte nicht erstellt werden."
    return 1
  fi

  # Prüfen ob API erfolgreich war
  if _contains "$response" '"status":"success"' || _contains "$response" '"status": "success"'; then
    _info "TXT-Record erfolgreich erstellt."
    return 0
  else
    _err "API-Fehler beim Erstellen des TXT-Records: $response"
    return 1
  fi
}

###############################################################################
# dns_wts_rm  <fulldomain> <txtvalue>
#
# Called by acme.sh to remove the ACME DNS-01 challenge TXT record.
###############################################################################
dns_wts_rm() {
  fulldomain="$1"
  txtvalue="$2"

  _info "Wärner Technologie Services DNS API – TXT record entfernen"
  _debug fulldomain "$fulldomain"
  _debug txtvalue   "$txtvalue"

  if ! _wts_load_credentials; then
    return 1
  fi

  # Root-Zone und Sub-Host ermitteln
  if ! _wts_get_root "$fulldomain"; then
    _err "Root-Zone konnte nicht ermittelt werden für: $fulldomain"
    return 1
  fi

  _debug "_domain  (zone)" "$_domain"
  _debug "_sub_domain"     "$_sub_domain"

  # DNS-Records der Zone laden
  _info "Lade DNS-Records für Zone: $_domain"
  _wts_api_get "/domain/dns?domainName=${_domain}"

  if [ "$?" != "0" ]; then
    _err "DNS-Records konnten nicht geladen werden."
    return 1
  fi

  # Record-ID für unseren TXT-Eintrag finden
  # JSON-Parsing via grep/sed (kein jq nötig)
  # Records haben Format: {"id":"...","name":"...","type":"TXT","content":"..."}
  _record_id=""

  # Extrahiere alle id+name+type+content Kombinationen
  # Verarbeite JSON zeilenweise nach dem Aufsplitten der Record-Objekte
  _records_raw=$(echo "$response" | tr ',' '\n' | tr '}' '\n')

  _current_id=""
  _current_name=""
  _current_type=""
  _current_content=""

  # Einfacher State-Machine-Parser für die flache JSON-Struktur
  while IFS= read -r line; do
    if echo "$line" | grep -q '"id"'; then
      _current_id=$(echo "$line" | sed 's/.*"id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    if echo "$line" | grep -q '"name"'; then
      _current_name=$(echo "$line" | sed 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    if echo "$line" | grep -q '"type"'; then
      _current_type=$(echo "$line" | sed 's/.*"type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    if echo "$line" | grep -q '"content"'; then
      _current_content=$(echo "$line" | sed 's/.*"content"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    fi
    # Wenn wir alle 4 Felder haben → prüfen
    if [ -n "$_current_id" ] && [ -n "$_current_type" ] && [ -n "$_current_content" ]; then
      _debug "Candidate record" "id=$_current_id name=$_current_name type=$_current_type content=$_current_content"
      if [ "$_current_type" = "TXT" ] && \
         [ "$_current_content" = "$txtvalue" ] && \
         { [ "$_current_name" = "$_sub_domain" ] || \
           [ "$_current_name" = "${_sub_domain}.${_domain}" ] || \
           [ "$_current_name" = "${_sub_domain}.${_domain}." ]; }; then
        _record_id="$_current_id"
        _debug "Passender Record gefunden" "id=$_record_id"
        break
      fi
      # Reset für nächsten Record
      _current_id=""
      _current_name=""
      _current_type=""
      _current_content=""
    fi
  done <<EOF
$_records_raw
EOF

  if [ -z "$_record_id" ]; then
    _warn "TXT-Record nicht gefunden (möglicherweise bereits gelöscht)."
    return 0
  fi

  # Record löschen
  _info "Lösche TXT-Record ID: $_record_id (Zone: $_domain)"

  _wts_api_delete "/dns/zone/record/delete" \
    "{\"zoneName\":\"${_domain}\",\"recordId\":\"${_record_id}\"}"

  if [ "$?" != "0" ]; then
    _err "TXT-Record konnte nicht gelöscht werden."
    return 1
  fi

  if _contains "$response" '"status":"success"' || _contains "$response" '"status": "success"'; then
    _info "TXT-Record erfolgreich gelöscht."
    return 0
  else
    _err "API-Fehler beim Löschen des TXT-Records: $response"
    return 1
  fi
}

###############################################################################
# Interne Hilfsfunktionen
###############################################################################

# Credentials aus Umgebung oder account.conf laden und speichern
_wts_load_credentials() {
  WTS_KEY="${WTS_KEY:-$(_readaccountconf_mutable WTS_KEY)}"
  WTS_URL="${WTS_URL:-$(_readaccountconf_mutable WTS_URL)}"

  if [ -z "$WTS_KEY" ]; then
    _err "WTS_KEY nicht gesetzt. Bitte exportiere: export WTS_KEY='dein-api-key'"
    _err "Den API-Key findest du im WTS-Kundenportal unter: Konto → API-Schlüssel"
    return 1
  fi

  # Standardwert setzen wenn WTS_URL fehlt
  if [ -z "$WTS_URL" ]; then
    WTS_URL="$WTS_API_DEFAULT"
  fi

  # Credentials persistent speichern für automatische Erneuerung
  _saveaccountconf_mutable WTS_KEY "$WTS_KEY"
  _saveaccountconf_mutable WTS_URL "$WTS_URL"

  _debug "WTS_URL" "$WTS_URL"
  _debug "WTS_KEY" "${WTS_KEY:0:8}..."
  return 0
}

# Root-Zone für eine Domain ermitteln
# Setzt $_domain (Zone) und $_sub_domain (Host-Teil)
# Beispiel: _acme-challenge.sub.example.com → _domain=example.com, _sub_domain=_acme-challenge.sub
_wts_get_root() {
  _full="$1"
  _domain=""
  _sub_domain=""

  # Domain-Teile aufsplitten
  _parts=$(echo "$_full" | tr '.' ' ')
  _count=$(echo "$_parts" | wc -w | tr -d ' ')

  if [ "$_count" -lt 2 ]; then
    _err "Ungültiger Domain-Name: $_full"
    return 1
  fi

  # Von rechts nach links testen welche Zone in der API existiert
  # z.B. _acme-challenge.www.example.co.uk → teste uk, co.uk, example.co.uk ...
  _i=2
  while [ "$_i" -le "$_count" ]; do
    # Letzten _i Teile als Zone-Kandidat
    _zone=$(echo "$_full" | rev | cut -d'.' -f1-"$_i" | rev)
    _debug "Teste Zone-Kandidat" "$_zone"

    # DNS-Zone in der API prüfen
    _wts_api_get "/domain/dns?domainName=${_zone}" 2>/dev/null
    if [ "$?" = "0" ] && (_contains "$response" '"status":"success"' || _contains "$response" '"status": "success"'); then
      _domain="$_zone"
      # Sub-Domain = alles vor der Zone
      _zone_len=$(echo "$_zone" | tr '.' '\n' | wc -l | tr -d ' ')
      _total_len=$(echo "$_full" | tr '.' '\n' | wc -l | tr -d ' ')
      _sub_parts=$((_total_len - _zone_len))
      if [ "$_sub_parts" -gt 0 ]; then
        _sub_domain=$(echo "$_full" | rev | cut -d'.' -f$((_zone_len + 1))-"$_total_len" | rev)
      else
        _sub_domain="@"
      fi
      _debug "Zone gefunden" "$_domain"
      _debug "Sub-Domain"   "$_sub_domain"
      return 0
    fi
    _i=$((_i + 1))
  done

  # Fallback: Letzten 2 Teile als Zone annehmen (TLD + SLD)
  _domain=$(echo "$_full" | rev | cut -d'.' -f1-2 | rev)
  _sub_domain=$(echo "$_full" | rev | cut -d'.' -f3- | rev)
  _warn "Zone nicht per API verifiziert, verwende Fallback: Zone='$_domain' Sub='$_sub_domain'"
  return 0
}

# HTTP GET gegen die WTS API
_wts_api_get() {
  _path="$1"
  _url="${WTS_URL}${_path}"

  export _H1="Authorization: Bearer ${WTS_KEY}"
  export _H2="Accept: application/json"

  response="$(_get "$_url")"
  _ret="$?"

  _debug "GET $_url"
  _debug "Response" "$response"

  return "$_ret"
}

# HTTP POST gegen die WTS API
_wts_api_post() {
  _path="$1"
  _data="$2"
  _url="${WTS_URL}${_path}"

  export _H1="Authorization: Bearer ${WTS_KEY}"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  response="$(_post "$_data" "$_url" "" "POST")"
  _ret="$?"

  _debug "POST $_url"
  _debug "Data"     "$_data"
  _debug "Response" "$response"

  return "$_ret"
}

# HTTP DELETE gegen die WTS API
_wts_api_delete() {
  _path="$1"
  _data="$2"
  _url="${WTS_URL}${_path}"

  export _H1="Authorization: Bearer ${WTS_KEY}"
  export _H2="Content-Type: application/json"
  export _H3="Accept: application/json"

  response="$(_post "$_data" "$_url" "" "DELETE")"
  _ret="$?"

  _debug "DELETE $_url"
  _debug "Data"     "$_data"
  _debug "Response" "$response"

  return "$_ret"
}
