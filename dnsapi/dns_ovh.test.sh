#!/usr/bin/env sh
# shellcheck disable=SC2034
# Offline replay test for dns_ovh.sh, no network access needed.
# The invalid credential responses replayed here are quoted from the
# issue #7386 report.

_TEST_DIR=$(dirname "$0")
# shellcheck disable=SC1090,SC1091
. "${_TEST_DIR}/dns_ovh.sh"

OVH_AK="test-application-key"
OVH_AS="test-application-secret"
OVH_CK="test-consumer-key"
OVH_END_POINT="ovh-eu"

_test_response=""

_err() {
  printf '%s\n' "$*" >&2
}

_info() {
  printf '%s\n' "$*" >&2
}

_debug() {
  :
}

_debug2() {
  :
}

_debug3() {
  :
}

_secure_debug() {
  :
}

_sleep() {
  :
}

__green() {
  printf '%s' "$1"
}

_digest() {
  printf '%s' "0123456789abcdef"
}

_contains() {
  printf '%s' "$1" | grep -F -- "$2" >/dev/null 2>&1
}

_readaccountconf() {
  :
}

_readaccountconf_mutable() {
  :
}

_saveaccountconf() {
  :
}

_saveaccountconf_mutable() {
  :
}

_clearaccountconf() {
  :
}

_clearaccountconf_mutable() {
  :
}

_get() {
  case "$1" in
  */auth/time)
    printf '%s' "1700000000"
    ;;
  *)
    printf '%s' "$_test_response"
    ;;
  esac
}

_post() {
  printf '%s' "$_test_response"
}

_fail() {
  printf '%s\n' "FAILED: $1" >&2
  exit 1
}

_expect_ok() {
  _desc="$1"
  _out=$(_initAuth 2>&1)
  _rc=$?
  [ "$_rc" = "0" ] || _fail "$_desc: expected success, got exit code $_rc"
  printf '%s' "$_out" | grep -F "Consumer key is ok." >/dev/null || _fail "$_desc: consumer key is not reported as ok"
  printf '%s\n' "ok - $_desc"
}

_expect_error() {
  _desc="$1"
  _out=$(_initAuth 2>&1)
  _rc=$?
  [ "$_rc" != "0" ] || _fail "$_desc: expected failure, got success"
  printf '%s' "$_out" | grep -F "Consumer key is ok." >/dev/null && _fail "$_desc: consumer key must not be reported as ok"
  printf '%s\n' "ok - $_desc"
}

_test_response='{"class":"Client::Forbidden","message":"This credential is not valid"}'
_expect_error "invalid credential response from issue #7386 is rejected"

_test_response='{"httpCode":"403","errorCode":"INVALID_CREDENTIAL","message":"Invalid credential"}'
_expect_error "legacy INVALID_CREDENTIAL response is rejected"

_test_response='["example.com","example.net"]'
_expect_ok "successful domain list response is accepted"

_test_response='{"class":"Client::Forbidden","message":"This credential is not valid"}'
_ovh_rest GET "domain/zone/example.com" >/dev/null 2>&1
_rc=$?
[ "$_rc" != "0" ] || _fail "_ovh_rest must reject the invalid credential response"
printf '%s\n' "ok - _ovh_rest rejects the invalid credential response"

_test_response='{"class":"Client::Forbidden","message":"This call has not been granted"}'
_ovh_rest GET "domain/zone/example.com" >/dev/null 2>&1
_rc=$?
[ "$_rc" = "0" ] || _fail "_ovh_rest must keep tolerating other forbidden responses for zone detection"
printf '%s\n' "ok - _ovh_rest still tolerates not granted forbidden responses"

printf '%s\n' "All dns_ovh replay tests passed."
