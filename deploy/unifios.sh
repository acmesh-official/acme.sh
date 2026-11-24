#!/usr/bin/env sh
# Deploy hook for UniFi OS, via the certificate REST API.
#
# Works against any UniFi OS whose management UI exposes
# /api/userCertificates. Confirmed on:
#   - UniFi OS Server (the separately-installed, self-hosted application)
#     on macOS and on Linux. Windows should also work (it runs under
#     WSL2), but has not been tested.
#         Tested on: Ubuntu 26.04 (remote) and macOS 26.6 (local).
#   - UniFi OS hardware: UDM Pro on UniFi OS 5.1.26, UCG Fiber on
#     UniFi OS 5.0.16 (user reports, see issues 7184 and 6916).
# No lower version bound is claimed -- if the UI has a certificate
# manager, this hook should work.
#
# `unifios` vs `unifi`: the split is the access method, not the product
# line. `unifi` writes files / a Java keystore and needs local or SSH
# access on the device; this hook drives the same REST API the web UI
# uses and works remotely. Use `unifi` where acme.sh runs on the device
# itself, this hook where it does not.
#
# The API is served on the management port, which differs per install:
# UniFi OS Server listens on 11443 (hence the default below), while
# UniFi OS hardware serves it on 443 -- set DEPLOY_UNIFIOS_HOST to
# "https://<host>" there.
#
# Endpoints used, all as the web UI itself calls them:
#   POST   /api/auth/login                  - session login (cookie + JWT)
#   GET    /api/userCertificates             - list uploaded certificates
#   POST   /api/userCertificates             - upload a new certificate
#   DELETE /api/userCertificates/{id}         - remove a certificate
#   PUT    /api/userCertificates/{id}/status  - activate/deactivate a certificate
#
# This was reverse-engineered from the browser's Network tab while using the
# real GUI upload/activate/delete flow -- it is undocumented but is the same
# code path the UI uses, so it's far more robust than editing settings.yaml,
# http/local-certs.conf, or the underlying Postgres user_certificates table
# directly (all of which are also touched by this API, but only as a result
# of the app's own internal logic, which handles cert parsing, active-cert
# bookkeeping, and nginx config regeneration correctly on its own).
#
# Auth: POST /api/auth/login returns a `TOKEN` cookie containing a JWT whose
# payload has a `csrfToken` claim. That value must be echoed back as the
# `x-csrf-token` header on every subsequent state-changing request (a classic
# double-submit CSRF pattern). No other cookies were found to be necessary.
#
# Uses core acme.sh helpers throughout (_post/_get, _json_encode,
# _durl_replace_base64, _dbase64, _egrep_o) rather than raw curl -k or
# python3, so the wget fallback, --debug tracing, and CA_BUNDLE are all
# honored the same as every other hook. The management API's cert may be
# self-signed -- it always is on a fresh install, and there is no reliable
# way to tell in advance whether an earlier run has already replaced it --
# so this hook sets HTTPS_INSECURE=1 itself, scoped to its own subshell (see
# acme.sh's per-hook sourcing in _deploy) -- it does not weaken TLS
# verification for the rest of the acme.sh run, e.g. the connection to the
# ACME CA.
#
# Design: This hook does not save a certificate ID between renewals. Each
# upload gets a name unique to that run: the domain name plus a timestamp.
# This name never collides with an entry from a previous deploy. This is
# true even if that entry is still active. The hook uploads and activates
# the new certificate before it removes any old entries. If a failure
# occurs during this process, the server still has a valid, active
# certificate. The hook removes old entries only after activation is
# complete. It removes only entries whose name starts with the domain name,
# because this is the hook's own naming convention. As a result, this step
# can only affect entries that this hook created for this domain. It can
# never affect a certificate that a user uploaded manually, and it can
# never affect a self-signed certificate.
#
# Settings:
#   DEPLOY_UNIFIOS_HOST - base URL of the management API
#     (default: "https://localhost:11443", i.e. a UniFi OS Server on the
#     same machine as acme.sh; set it to "https://<host>" for UniFi OS
#     hardware or any remote target)
#   DEPLOY_UNIFIOS_USERNAME - UniFi OS admin username (required)
#   DEPLOY_UNIFIOS_PASSWORD - UniFi OS admin password (required)
#
# Example:
#   export DEPLOY_UNIFIOS_USERNAME="acmeuser"
#   export DEPLOY_UNIFIOS_PASSWORD="xxxxx"
#   acme.sh --deploy -d example.com --deploy-hook unifios
#
# Please report bugs to https://github.com/acmesh-official/acme.sh/issues/7182

_uos_response_code() {
  # tr strips the trailing newline along with form feeds; re-terminate
  # before the second _egrep_o, whose sed fallback (used wherever egrep -o
  # is unavailable) drops an unterminated final line on some platforms.
  _uos_code="$(_egrep_o <"$HTTP_HEADER" "^HTTP[^ ]* .*$" | cut -d " " -f 2-100 | tr -d "\f\n")"
  printf '%s\n' "$_uos_code" | _egrep_o "^[0-9][0-9]*"
}

_uos_response_cookie() {
  # $1 = cookie name
  grep <"$HTTP_HEADER" -i "^Set-Cookie: *$1=" | _tail_n 1 | _egrep_o "$1=[^;]*" | _head_n 1
}

_uos_split_json() {
  # $1 = raw JSON list response
  #
  # _normalizeJson collapses the response to one line. This removes extra
  # space around colons. It also removes any CR or LF characters that the
  # server can add. However, _normalizeJson also removes the newline
  # character at the end of the line. If the line has no ending newline
  # character, some sed programs drop the last line of input. This code
  # adds the newline back before the split below, to prevent that problem.
  _uos_normalized="$(echo "$1" | _normalizeJson)"
  # A literal newline character splits the JSON into one object per line.
  # Grep can then match a single certificate entry at a time. This is not
  # the two-character "\n" sequence: GNU sed reads "\n" in the replacement
  # text as a newline character. POSIX does not define this behavior, and
  # BSD sed prints "\n" as two literal characters, not as a newline.
  printf '%s\n' "$_uos_normalized" | sed 's/},{/},\
{/g'
}

_uos_grep_literal() {
  # $1 = literal text to find, matched without a regex -- portable to
  # grep implementations with no -F flag (e.g. Solaris), and avoids "*"
  # or "." in a domain name being read as a regex metacharacter.
  while IFS= read -r _uos_line || [ -n "$_uos_line" ]; do
    case "$_uos_line" in
    *"$1"*) printf '%s\n' "$_uos_line" ;;
    esac
  done
}

unifios_deploy() {
  _cdomain="$1"
  _ckey="$2"
  _ccert="$3"
  _cca="$4"
  _cfullchain="$5"

  _debug _cdomain "$_cdomain"
  _debug _ckey "$_ckey"
  _debug _ccert "$_ccert"
  _debug _cca "$_cca"
  _debug _cfullchain "$_cfullchain"

  # Scoped to this hook's own subshell -- does not affect the rest of the
  # acme.sh run (e.g. the connection to the ACME CA).
  export HTTPS_INSECURE=1

  _getdeployconf DEPLOY_UNIFIOS_HOST
  DEPLOY_UNIFIOS_HOST="${DEPLOY_UNIFIOS_HOST:-https://localhost:11443}"
  _savedeployconf DEPLOY_UNIFIOS_HOST "$DEPLOY_UNIFIOS_HOST"
  _debug DEPLOY_UNIFIOS_HOST "$DEPLOY_UNIFIOS_HOST"

  _getdeployconf DEPLOY_UNIFIOS_USERNAME
  _getdeployconf DEPLOY_UNIFIOS_PASSWORD

  if [ -z "$DEPLOY_UNIFIOS_USERNAME" ] || [ -z "$DEPLOY_UNIFIOS_PASSWORD" ]; then
    _err "DEPLOY_UNIFIOS_USERNAME and DEPLOY_UNIFIOS_PASSWORD must be set."
    return 1
  fi
  _debug DEPLOY_UNIFIOS_USERNAME "$DEPLOY_UNIFIOS_USERNAME"
  _secure_debug DEPLOY_UNIFIOS_PASSWORD "$DEPLOY_UNIFIOS_PASSWORD"

  _info "Logging in to UniFi OS Server API at $DEPLOY_UNIFIOS_HOST..."

  # _json_encode always appends a trailing "\n" escape, even to input with
  # no trailing newline (it normalizes via `echo`, unconditionally adding
  # one). That's harmless for the key/cert file content below, which
  # legitimately ends in a real newline anyway, but wrong for these plain
  # strings -- strip the spurious escape it leaves behind.
  _uos_user_json="$(printf '%s' "$DEPLOY_UNIFIOS_USERNAME" | _json_encode)"
  _uos_user_json="${_uos_user_json%\\n}"
  _uos_pass_json="$(printf '%s' "$DEPLOY_UNIFIOS_PASSWORD" | _json_encode)"
  _uos_pass_json="${_uos_pass_json%\\n}"
  _login_body="{\"username\":\"$_uos_user_json\",\"password\":\"$_uos_pass_json\",\"token\":\"\",\"rememberMe\":false}"

  _login_json="$(_post "$_login_body" "$DEPLOY_UNIFIOS_HOST/api/auth/login" "" "POST" "application/json")"
  _login_code="$(_uos_response_code)"

  if [ "$_login_code" != "200" ]; then
    _err "Login failed (HTTP $_login_code)."
    _err "Response: $_login_json"
    return 1
  fi

  # Credentials are proven correct now -- save them, rather than only at the
  # very end, so a later step failing doesn't discard a working login.
  # base64-encoded: _save_conf wraps values in single quotes with no
  # escaping, so a literal "'" in the password would otherwise corrupt the
  # domain conf (see deploy/synology_dsm.sh for the same pattern).
  _savedeployconf DEPLOY_UNIFIOS_USERNAME "$DEPLOY_UNIFIOS_USERNAME" "base64"
  _savedeployconf DEPLOY_UNIFIOS_PASSWORD "$DEPLOY_UNIFIOS_PASSWORD" "base64"

  _uos_token="$(_uos_response_cookie TOKEN)"
  if [ -z "$_uos_token" ]; then
    _err "Login succeeded but no TOKEN cookie was returned."
    return 1
  fi

  _H1="Cookie: $_uos_token"
  export _H1

  _uos_jwt_payload="$(echo "$_uos_token" | cut -d '=' -f 2- | cut -d '.' -f 2)"
  _uos_csrf="$(_durl_replace_base64 "$_uos_jwt_payload" | _dbase64 | _egrep_o '"csrfToken":"[^"]*"' | cut -d '"' -f 4)"
  if [ -z "$_uos_csrf" ]; then
    _err "Could not extract csrfToken from session token."
    return 1
  fi

  _H2="x-csrf-token: $_uos_csrf"
  export _H2

  _info "Uploading new certificate..."
  # "name" is a purely cosmetic label -- the server never validates it
  # against the certificate's actual CN/SAN, and accepts arbitrary text
  # including spaces (confirmed: a cert for example.com served correctly
  # after being uploaded under the unrelated name "totally unrelated label").
  # The only constraint that matters here is uniqueness: the server rejects
  # a second entry with a name it already has, so a bare domain name would
  # collide with the previous deploy's entry on every renewal after the
  # first. A full human-readable timestamp would make that obvious in the
  # UI, but the certificate list's name column is fixed-width and doesn't
  # wrap (confirmed against the real UI: a long name overlaps the Expires
  # column and makes both unreadable), so keep the suffix short instead --
  # Unix epoch seconds are still unique enough for this purpose.
  #
  # This name includes the key type (rsa or ecdsa), to keep an RSA
  # deploy and an ECC deploy of the same domain from sharing this
  # prefix. Without the key type, the cleanup step for each deploy
  # removes the entry that the other deploy creates. `deploy/haproxy.sh`
  # and `deploy/lighttpd.sh` use the same `_isEccKey` check, for the same
  # reason.
  # shellcheck disable=SC2154 # Le_Keylength is set by acme.sh core, not this hook
  if _isEccKey "${Le_Keylength}"; then
    _uos_keytype="ecdsa"
  else
    _uos_keytype="rsa"
  fi
  _uos_name="$_cdomain $_uos_keytype $(_time)"
  _uos_key_json="$(_json_encode <"$_ckey")"
  _uos_cert_json="$(_json_encode <"$_cfullchain")"
  _create_body="{\"name\":\"$_uos_name\",\"key\":\"$_uos_key_json\",\"cert\":\"$_uos_cert_json\"}"

  _create_json="$(_post "$_create_body" "$DEPLOY_UNIFIOS_HOST/api/userCertificates" "" "POST" "application/json")"
  _create_code="$(_uos_response_code)"

  if [ "$_create_code" = "201" ]; then
    _new_id="$(echo "$_create_json" | _egrep_o '"id":"[^"]*"' | _head_n 1 | cut -d '"' -f 4)"
    if [ -z "$_new_id" ]; then
      _err "Could not determine new certificate ID from upload response."
      return 1
    fi
  elif [ "$_create_code" = "400" ] && echo "$_create_json" | grep -q "USER_CERTIFICATE_DUPLICATE"; then
    # HTTP 400 alone just means "bad request" -- it's the USER_CERTIFICATE_DUPLICATE
    # code in the response body, checked above, that actually confirms this.
    # The name above is unique to this run, so a duplicate here can only be
    # the server's other uniqueness constraint: this exact certificate (by
    # fingerprint) already exists as some other entry -- most likely a retry
    # after a prior run already uploaded it (a real renewal always produces a
    # new fingerprint, so this shouldn't happen in normal cron use). The
    # response body doesn't include the existing entry's id, so look it up
    # by fingerprint instead.
    # The API's own fingerprint field is SHA-1 (20 bytes), not SHA-256 --
    # confirmed against a real response, e.g.
    # "fingerprint":"FC:02:50:9C:3B:3F:B7:79:9D:CA:4D:7C:AC:92:E7:D5:EA:F1:3A:29"
    # (20 colon-separated groups). _fingerprint (core helper) strips the
    # colons that field has, so re-insert them rather than stripping the
    # JSON's own colons, which would also remove the ones separating every
    # key from its value.
    _uos_fingerprint="$(_fingerprint "$_cfullchain" sha1)"
    if [ -z "$_uos_fingerprint" ]; then
      _err "Could not compute the certificate's fingerprint."
      return 1
    fi
    _uos_fingerprint="$(echo "$_uos_fingerprint" | sed 's/\(..\)/\1:/g; s/:$//')"

    _list_json="$(_get "$DEPLOY_UNIFIOS_HOST/api/userCertificates")"
    _list_code="$(_uos_response_code)"
    if [ "$_list_code" != "200" ]; then
      _err "Failed to list existing certificates (HTTP $_list_code)."
      _err "Response: $_list_json"
      return 1
    fi
    _list_json="$(_uos_split_json "$_list_json")"
    _new_id="$(echo "$_list_json" | _uos_grep_literal "\"fingerprint\":\"$_uos_fingerprint\"" | _egrep_o '"id":"[^"]*"' | _head_n 1 | cut -d '"' -f 4)"
    if [ -z "$_new_id" ]; then
      _err "Certificate upload rejected as a duplicate (server reported USER_CERTIFICATE_DUPLICATE), but no existing entry matching this fingerprint was found."
      _err "Response: $_create_json"
      return 1
    fi
    # Reusing the existing entry rather than deleting it and re-uploading
    # under today's name+timestamp: the served content is identical either
    # way, so replacing it would only cost an extra delete+create round trip
    # for no functional benefit. The tradeoff is cosmetic -- this entry keeps
    # whatever name it was given whenever it was originally uploaded, so it
    # won't reflect today's date in the UI.
    _info "Certificate already present as entry $_new_id; reusing it."
  else
    _err "Certificate upload failed (HTTP $_create_code)."
    _err "Response: $_create_json"
    return 1
  fi

  _info "Activating certificate $_new_id..."
  _activate_json="$(_post '{"active":true}' "$DEPLOY_UNIFIOS_HOST/api/userCertificates/$_new_id/status" "" "PUT" "application/json")"
  _activate_code="$(_uos_response_code)"

  if [ "$_activate_code" != "200" ]; then
    _err "Failed to activate new certificate (HTTP $_activate_code)."
    _err "Response: $_activate_json"
    return 1
  fi

  # UniFi OS Server activation is exclusive server-wide. Tests against the
  # real API confirm this: activation of one entry deactivates whichever
  # other entry was active before, no matter its name or domain. As a
  # result, the server serves the certificate that this hook just activated.
  # This certificate is already live. If the removal of old entries below
  # fails, the hook logs the failure. The deploy does not fail because of
  # this.
  _info "Checking for old certificate entries to remove..."
  _list_json="$(_get "$DEPLOY_UNIFIOS_HOST/api/userCertificates")"
  _list_code="$(_uos_response_code)"
  if [ "$_list_code" != "200" ]; then
    _err "Failed to list certificates for cleanup (HTTP $_list_code) -- leaving old entries in place."
  else
    _list_json="$(_uos_split_json "$_list_json")"
    # The pattern below matches the domain name and key type, followed by
    # a space. If the space is missing, the pattern can also match a
    # different domain that starts with the same text as this domain.
    _old_ids="$(echo "$_list_json" | _uos_grep_literal "\"name\":\"$_cdomain $_uos_keytype " | _egrep_o '"id":"[^"]*"' | cut -d '"' -f 4 | grep -v "^$_new_id$")"
    for _old_id in $_old_ids; do
      _info "Removing old certificate entry $_old_id..."
      _del_json="$(_post "" "$DEPLOY_UNIFIOS_HOST/api/userCertificates/$_old_id" "" "DELETE")"
      _del_code="$(_uos_response_code)"
      if [ "$_del_code" != "204" ] && [ "$_del_code" != "200" ]; then
        _err "Failed to delete old certificate $_old_id (HTTP $_del_code) -- leaving it in place."
        _err "Response: $_del_json"
      fi
    done
  fi

  _info "UniFi OS Server certificate deployed and activated successfully."
  return 0
}
