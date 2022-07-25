#!/usr/bin/env sh

if [ "$1" = "daemon" ]; then
  trap "echo stop && killall crond && exit 0" SIGTERM SIGINT
  crond && sleep infinity &
  wait
else
  exec -- "$@"
fi
