#!/usr/bin/env sh

# support local mail app



mail_send() {
  _subject="$1"
  _content="$2"
  _statusCode="$3" #0: success, 1: error 2($RENEW_SKIP): skipped

  _err "Not implemented yet."
  return 1
}

