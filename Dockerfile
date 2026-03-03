FROM alpine:3.22

RUN apk --no-cache add -f \
  openssl \
  openssh-client \
  coreutils \
  bind-tools \
  curl \
  sed \
  socat \
  tzdata \
  oath-toolkit-oathtool \
  tar \
  libidn \
  jq \
  yq-go \
  supercronic

ENV LE_WORKING_DIR=/acmebin

ENV LE_CONFIG_HOME=/acme.sh

ENV HOME=/acme.sh

ARG AUTO_UPGRADE=1

ENV AUTO_UPGRADE=$AUTO_UPGRADE

#Install
COPY ./acme.sh /install_acme.sh/acme.sh
COPY ./deploy /install_acme.sh/deploy
COPY ./dnsapi /install_acme.sh/dnsapi
COPY ./notify /install_acme.sh/notify

RUN addgroup -g 1000 acme && adduser -h $LE_CONFIG_HOME -s /bin/sh -G acme -D -H -u 1000 acme

RUN cd /install_acme.sh && ([ -f /install_acme.sh/acme.sh ] && /install_acme.sh/acme.sh --install || curl https://get.acme.sh | sh) && rm -rf /install_acme.sh/

RUN ln -s $LE_WORKING_DIR/acme.sh /usr/local/bin/acme.sh

RUN chown -R acme:acme $LE_CONFIG_HOME

RUN for verb in help \
  version \
  install \
  uninstall \
  upgrade \
  issue \
  signcsr \
  deploy \
  install-cert \
  renew \
  renew-all \
  revoke \
  remove \
  list \
  info \
  showcsr \
  install-cronjob \
  uninstall-cronjob \
  cron \
  toPkcs \
  toPkcs8 \
  update-account \
  register-account \
  create-account-key \
  create-domain-key \
  createCSR \
  deactivate \
  deactivate-account \
  set-notify \
  set-default-ca \
  set-default-chain \
  ; do \
    printf -- "%b" "#!/usr/bin/env sh\n$LE_WORKING_DIR/acme.sh --${verb} --config-home $LE_CONFIG_HOME \"\$@\"" >/usr/local/bin/--${verb} && chmod +x /usr/local/bin/--${verb} \
  ; done

RUN printf "%b" '#!'"/usr/bin/env sh\n \
if [ \"\$1\" = \"daemon\" ];  then \n \
  if [ ! -f \"\$LE_CONFIG_HOME/crontab\" ]; then \n \
     echo \"\$LE_CONFIG_HOME/crontab not found, generating one\" \n \
     time=\$(date -u \"+%s\") \n \
     random_minute=\$((\$time % 60)) \n \
     random_hour=\$((\$time / 60 % 24)) \n \
     echo \"\$random_minute \$random_hour * * * \\\"\$LE_WORKING_DIR\\\"/acme.sh --cron --home \\\"\$LE_WORKING_DIR\\\" --config-home \\\"\$LE_CONFIG_HOME\\\"\" > \"\$LE_CONFIG_HOME\"/crontab \n \
  fi \n \
  echo \"Running Supercronic using crontab at \$LE_CONFIG_HOME/crontab\" \n \
  exec -- /usr/bin/supercronic \"\$LE_CONFIG_HOME/crontab\" \n \
else \n \
 exec -- \"\$@\"\n \
fi\n" >/entry.sh && chmod +x /entry.sh && chmod -R o+rwx $LE_WORKING_DIR && chmod -R o+rwx $LE_CONFIG_HOME

VOLUME /acme.sh

ENTRYPOINT ["/entry.sh"]
CMD ["--help"]
