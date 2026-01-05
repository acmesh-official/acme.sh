#!/bin/sh
set -e

LE_WORKING_DIR=/acmebin

LE_CONFIG_HOME=/acme.sh

AUTO_UPGRADE=${AUTO_UPGRADE:-1}

# Install apk packages
apk --no-cache add -f openssl openssh-client coreutils bind-tools curl sed socat tzdata oath-toolkit-oathtool tar libidn jq yq-go cronie

# Install acme.sh
if [ -f /install_acme.sh/acme.sh ] ; then
  cd /install_acme.sh || exit 1
  /install_acme.sh/acme.sh --install
else
  curl https://get.acme.sh | sh
fi

# Create symlink and modify crontab
if ln -s $LE_WORKING_DIR/acme.sh /usr/local/bin/acme.sh ; then
  if crontab -l | grep acme.sh ; then
    crontab -l | grep acme.sh | sed 's#> /dev/null#> /proc/1/fd/1 2>/proc/1/fd/2#' | crontab -
  fi
fi

# Create command shortcuts
for verb in help version install uninstall upgrade issue signcsr deploy install-cert renew renew-all revoke remove list info showcsr install-cronjob uninstall-cronjob cron toPkcs toPkcs8 update-account register-account create-account-key create-domain-key createCSR deactivate deactivate-account set-notify set-default-ca set-default-chain; do
printf -- "%b" "#!/usr/bin/env sh\n$LE_WORKING_DIR/acme.sh --${verb} --config-home $LE_CONFIG_HOME \"\$@\"" >/usr/local/bin/--${verb} && chmod +x /usr/local/bin/--${verb};
done

# Create entry.sh and set permissions
cat >/entry.sh <<'EOF'
#!/usr/bin/env sh
if [ "$1" = "daemon" ];  then
 exec crond -n -s -m off
else
 exec -- "$@"
fi
EOF

chmod +x /entry.sh
chmod -R o+rwx $LE_WORKING_DIR
chmod -R o+rwx $LE_CONFIG_HOME

rm -rf /install_acme.sh/ || true