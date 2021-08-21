#!/usr/bin/env sh

_exists() {
  cmd="$1"
  if [ -z "$cmd" ] ; then
    echo "Usage: _exists cmd"
    return 1
  fi
  if type command >/dev/null 2>&1 ; then
    command -v $cmd >/dev/null 2>&1
  else
    type $cmd >/dev/null 2>&1
  fi
  ret="$?"
  return $ret
}

if [ -z "$BRANCH" ]; then
  BRANCH="master"
fi

#format "email=my@example.com"
_email="$1"

if [ "$_email" ]; then
  shift
  _email="--$(echo "$_email" | tr '=' ' ')"
fi

touch "$HOME/.bash_profile"

if _exists curl && [ "${ACME_USE_WGET:-0}" = "0" ]; then
  curl https://raw.githubusercontent.com/runapp/acme.sh/$BRANCH/acme.sh | sh -s -- --install-online $_email "$@"
elif _exists wget ; then
  wget -O -  https://raw.githubusercontent.com/runapp/acme.sh/$BRANCH/acme.sh | sh -s -- --install-online $_email "$@"
else
  echo "Sorry, you must have curl or wget installed first."
  echo "Please install either of them and try again."
fi
