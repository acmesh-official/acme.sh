#!/usr/bin/env sh
# Regression test: --to-pkcs12 and --to-pkcs8 must fail when openssl fails.
#
# _toPkcs and _toPkcs8 used to end with `if [ "$?" = "0" ]; then`, so the exit
# status of a failed openssl run was replaced by the status of that if (0 when
# its body is not taken). Both the helpers and the public entry points then
# reported "Success" while nothing had been written.
#
# Usage, from the repository root:
#   sh test_pkcs_export_status.sh
#
# Exits 0 when both commands fail as they should, 1 otherwise.

set -u

_ACME_SH="$(cd "$(dirname "$0")" && pwd)/acme.sh"
if [ ! -f "$_ACME_SH" ]; then
  echo "Cannot find $_ACME_SH." >&2
  exit 1
fi

_work="$(mktemp -d)" || exit 1
trap 'rm -rf "$_work"' EXIT INT HUP TERM
_home="$_work/home"
_domain="no-such-cert.example.com"
mkdir -p "$_home/$_domain"

#the commands need no network: they only read the domain directory
#stdin is /dev/null so that nothing can wait for a prompt
_run() {
  sh "$_ACME_SH" --home "$_home" --config-home "$_home" "$1" -d "$_domain" </dev/null >"$_work/out" 2>&1
}

_fail=0
_check() {
  if [ "$2" -eq 0 ]; then
    echo "FAIL $1: exit status 0 although the export failed"
    _fail=1
  elif [ -f "$3" ]; then
    echo "FAIL $1: exit status $2 but $3 was created"
    _fail=1
  else
    echo "ok   $1: exit status $2 and no file was produced"
  fi
}

echo "=== --to-pkcs12 with no key or cert present ==="
_run --to-pkcs12
_pfx_rc=$?
sed 's/^/   | /' "$_work/out"
_check --to-pkcs12 "$_pfx_rc" "$_home/$_domain/$_domain.pfx"

echo "=== --to-pkcs8 with no key present ==="
_run --to-pkcs8
_pkcs8_rc=$?
sed 's/^/   | /' "$_work/out"
_check --to-pkcs8 "$_pkcs8_rc" "$_home/$_domain/$_domain.pkcs8"

if [ "$_fail" -ne 0 ]; then
  echo "FAILED"
  exit 1
fi
echo "PASSED"
