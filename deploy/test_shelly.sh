#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

export LE_WORKING_DIR="$TMPDIR"

# Generate a test ECC certificate (mimics Let's Encrypt)
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 \
  -keyout "$TMPDIR/key.pem" -out "$TMPDIR/cert.pem" \
  -days 1 -nodes -subj "/CN=test.local" 2>/dev/null
cp "$TMPDIR/cert.pem" "$TMPDIR/fullchain.pem"

echo "Test cert: $(wc -c < "$TMPDIR/fullchain.pem") bytes"
echo "Test key:  $(wc -c < "$TMPDIR/key.pem") bytes"
echo ""

# Source acme.sh to get utility functions
cd "$REPO_DIR"
. ./acme.sh >/dev/null 2>&1 || true

# Override _post to capture calls instead of sending real HTTP requests
_post() {
  _POST_BODY="$1"
  _POST_URL="$2"
  _POST_CONTENT_TYPE="$5"
  echo "[MOCK] _post: $_POST_URL" >&2
  response='{"id":1,"result":{"restart_required":true}}'
  return 0
}

# Source the deploy hook
. ./deploy/shelly.sh

failures=0

# --- Test 1: _json_encode ---
echo "=== Test 1: _json_encode ==="
encoded="$(_json_encode < "$TMPDIR/fullchain.pem")"
echo "Encoded length: ${#encoded}"
if printf '%s' "$encoded" | od -A n -t x1 | grep -q '0a'; then
  echo "FAIL: encoded output contains raw 0x0a byte"
  ((failures++))
else
  echo "PASS: no raw newlines (0x0a)"
fi
echo ""

# --- Test 2: RPC body without auth ---
echo "=== Test 2: RPC body (no auth) ==="
_shelly_ha1=""
SHELLY_HOST="192.0.2.10"
_method="Test.Method"
_params='{"key":"value"}'
_body='{"id":1,"method":"'"$_method"'","params":'"$_params"'}'
echo "Body: $_body"
if echo "$_body" | python3 -m json.tool >/dev/null 2>&1; then
  echo "PASS: valid JSON"
else
  echo "FAIL: invalid JSON"
  ((failures++))
fi
if echo "$_body" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); sys.exit(0 if 'auth' not in d else 1)"; then
  echo "PASS: no auth object present"
else
  echo "FAIL: auth object unexpectedly present"
  ((failures++))
fi
echo ""

# --- Test 3: RFC 7616 Digest auth hashes ---
echo "=== Test 3: RFC 7616 Digest auth ==="
SHELLY_USER="admin"
_shelly_realm="shellypro4pm-f008d1d8b8b8"
_shelly_nonce="dGVzdG5vbmNlMTIz"
SHELLY_PASSWORD="testpass"
_shelly_qop="auth"

_shelly_ha1="$(printf '%s' "${SHELLY_USER}:${_shelly_realm}:${SHELLY_PASSWORD}" | _digest sha256 hex)"
_shelly_cnonce="a1b2c3d4e5f6a7b8"
_shelly_nc=1
_nc_hex="$(printf '%08x' "$_shelly_nc")"
_ha2="$(printf '%s' 'POST:/rpc' | _digest sha256 hex)"
_resp="$(printf '%s' "${_shelly_ha1}:${_shelly_nonce}:${_nc_hex}:${_shelly_cnonce}:${_shelly_qop}:${_ha2}" | _digest sha256 hex)"

[ "${#_shelly_ha1}" = "64" ] && echo "PASS: ha1 is 64 hex chars" || { echo "FAIL: ha1 wrong length (${#_shelly_ha1})"; ((failures++)); }
[ "${#_resp}" = "64" ] && echo "PASS: response is 64 hex chars" || { echo "FAIL: response wrong length (${#_resp})"; ((failures++)); }

_auth_header="Digest username=\"${SHELLY_USER}\", realm=\"${_shelly_realm}\", nonce=\"${_shelly_nonce}\", uri=\"/rpc\", qop=${_shelly_qop}, nc=${_nc_hex}, cnonce=\"${_shelly_cnonce}\", response=\"${_resp}\", algorithm=SHA-256"
echo "Auth header: $_auth_header"

# Validate header via Python (pipe to stdin)
printf '%s\n' "$_auth_header" | python3 -c "
import sys, re
data = sys.stdin.read().strip()
parts = dict(re.findall(r'(\w+)=\"?([^\",]+)\"?', data))
ok = True
for field, expected in [
    ('username', 'admin'),
    ('realm', 'shellypro4pm-f008d1d8b8b8'),
    ('nonce', 'dGVzdG5vbmNlMTIz'),
    ('uri', '/rpc'),
    ('qop', 'auth'),
    ('nc', '00000001'),
    ('algorithm', 'SHA-256'),
]:
    actual = parts.get(field, '')
    if actual == expected:
        print('  PASS: %s = %s' % (field, actual))
    else:
        print('  FAIL: %s expected=\"%s\" got=\"%s\"' % (field, expected, actual))
        ok = False
if data.split()[0] == 'Digest':
    print('  PASS: starts with Digest')
else:
    print('  FAIL: does not start with Digest')
    ok = False
if len(parts.get('response', '')) == 64:
    print('  PASS: response is 64 chars')
else:
    print('  FAIL: response wrong length')
    ok = False
sys.exit(0 if ok else 1)
"
rc=$?
if [ "$rc" -ne 0 ]; then ((failures++)); fi
echo ""

# --- Test 3b: _shelly_build_auth_header function ---
echo "=== Test 3b: _shelly_build_auth_header function ==="
SHELLY_USER="admin"
_shelly_realm="shellytest-f008d1d8b8b8"
_shelly_nonce="dGVzdG5vbmNl"
SHELLY_PASSWORD="pass123"
_shelly_qop="auth"
_shelly_nc=5

_shelly_ha1="$(printf '%s' "${SHELLY_USER}:${_shelly_realm}:${SHELLY_PASSWORD}" | _digest sha256 hex)"
_shelly_cnonce="deadbeefcafebabe"

_shelly_build_auth_header

echo "Generated header: $_shelly_auth_header"

if echo "$_shelly_auth_header" | grep -q '^Digest username='; then
  echo "PASS: starts with Digest username="
else
  echo "FAIL: wrong header format"
  ((failures++))
fi

printf '%s\n' "$_shelly_auth_header" | python3 -c "
import sys, re
data = sys.stdin.read().strip()
parts = dict(re.findall(r'(\w+)=\"?([^\",]+)\"?', data))
checks = [
    ('username', 'admin'),
    ('realm', 'shellytest-f008d1d8b8b8'),
    ('nonce', 'dGVzdG5vbmNl'),
    ('uri', '/rpc'),
    ('qop', 'auth'),
    ('nc', '00000005'),
    ('cnonce', 'deadbeefcafebabe'),
    ('algorithm', 'SHA-256'),
]
all_ok = True
for field, expected in checks:
    actual = parts.get(field, '')
    if actual == expected:
        print('  PASS: %s = %s' % (field, actual))
    else:
        print('  FAIL: %s expected=\"%s\" got=\"%s\"' % (field, expected, actual))
        all_ok = False
if len(parts.get('response', '')) == 64:
    print('  PASS: response is 64 chars')
else:
    print('  FAIL: response wrong length')
    all_ok = False
sys.exit(0 if all_ok else 1)
"
rc=$?
if [ "$rc" -ne 0 ]; then ((failures++)); fi
echo ""

# --- Test 4: Cert upload body ---
echo "=== Test 4: Cert upload body ==="
_cert_data="$(_json_encode < "$TMPDIR/fullchain.pem")"
_cert_body='{"id":1,"method":"Shelly.PutHTTPServerCert","params":{"data":"'"$_cert_data"'"}}'
echo "Body length: ${#_cert_body}"
if echo "$_cert_body" | python3 -m json.tool >/dev/null 2>&1; then
  echo "PASS: valid JSON"
else
  echo "FAIL: invalid JSON"
  ((failures++))
fi
python3 -c "
import json, sys
body = json.loads(sys.stdin.read())
decoded = body['params']['data']
with open('$TMPDIR/fullchain.pem') as f:
    original = f.read()
if decoded == original:
    print('PASS: round-trip matches (%d bytes)' % len(original))
else:
    print('FAIL: round-trip mismatch (orig=%dB, decoded=%dB)' % (len(original), len(decoded)))
    sys.exit(1)
" <<< "$_cert_body" || ((failures++))
echo ""

# --- Test 5: Clear cert body ---
echo "=== Test 5: Clear cert body ==="
_clear_body='{"id":1,"method":"Shelly.PutHTTPServerCert","params":{"data":null}}'
echo "$_clear_body" | python3 -m json.tool >/dev/null 2>&1 && echo "PASS: valid JSON" || { echo "FAIL"; ((failures++)); }
echo "$_clear_body" | python3 -c "
import json, sys
d = json.loads(sys.stdin.read())
assert d['params']['data'] is None, 'data should be null'
print('PASS: data is null')
" || ((failures++))
echo ""

# --- Test 6: Key upload body ---
echo "=== Test 6: Key upload body ==="
_key_data="$(_json_encode < "$TMPDIR/key.pem")"
_key_body='{"id":1,"method":"Shelly.PutHTTPServerKey","params":{"data":"'"$_key_data"'"}}'
echo "$_key_body" | python3 -m json.tool >/dev/null 2>&1 && echo "PASS: valid JSON" || { echo "FAIL"; ((failures++)); }
python3 -c "
import json, sys
body = json.loads(sys.stdin.read())
decoded = body['params']['data']
with open('$TMPDIR/key.pem') as f:
    original = f.read()
assert decoded == original, 'key round-trip mismatch'
print('PASS: key round-trip matches (%d bytes)' % len(original))
" <<< "$_key_body" || ((failures++))
echo ""

# --- Test 7: Full deploy dry-run (no auth) ---
echo "=== Test 7: Full deploy dry-run (no auth) ==="
SHELLY_HOST="192.0.2.10"
SHELLY_PASSWORD=""
SHELLY_USER="admin"
SHELLY_REBOOT="0"
_shelly_auth_header=""
_shelly_ha1=""
_shelly_nc=1

if shelly_deploy "test.local" "$TMPDIR/key.pem" "$TMPDIR/cert.pem" "$TMPDIR/cert.pem" "$TMPDIR/fullchain.pem"; then
  echo "PASS: shelly_deploy returned 0"
else
  echo "FAIL: shelly_deploy returned non-zero"
  ((failures++))
fi
echo ""

# --- Test 8: Full deploy dry-run (with auth) ---
echo "=== Test 8: Full deploy dry-run (with auth) ==="
SHELLY_HOST="192.0.2.10"
SHELLY_PASSWORD="mysecret"
SHELLY_USER="admin"
SHELLY_REBOOT="0"
_shelly_auth_header=""
_shelly_ha1=""
_shelly_nc=1

if shelly_deploy "test.local" "$TMPDIR/key.pem" "$TMPDIR/cert.pem" "$TMPDIR/cert.pem" "$TMPDIR/fullchain.pem"; then
  echo "PASS: shelly_deploy returned 0"
else
  echo "FAIL: shelly_deploy returned non-zero"
  ((failures++))
fi
echo ""

# --- Results ---
echo "========================================="
if [ "$failures" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "$failures TEST(S) FAILED"
fi
exit $failures