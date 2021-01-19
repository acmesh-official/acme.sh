FROM alpine:3.12

RUN apk update -f \
  && apk --no-cache add -f \
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
  && rm -rf /var/cache/apk/*

ENV LE_CONFIG_HOME /acme.sh
ENV UID 1000
ENV GID 1000
ARG AUTO_UPGRADE=1

ENV AUTO_UPGRADE $AUTO_UPGRADE

ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.1.12/supercronic-linux-amd64 \
    SUPERCRONIC=supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=048b95b48b708983effb2e5c935a1ef8483d9e3e

#Install
ADD ./ /home/acmesh/install_acme.sh/
RUN curl -fsSLO "$SUPERCRONIC_URL" \
 && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
 && chmod +x "$SUPERCRONIC" \
 && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
 && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic

RUN addgroup -S -g $GID acmesh && \
    adduser -S -u $UID -G acmesh -s /bin/sh acmesh && \
    mkdir /acme.sh && chown acmesh /acme.sh && \
    chown -R acmesh /home/acmesh/install_acme.sh

USER acmesh
RUN cd /home/acmesh/install_acme.sh && \
/bin/sh /home/acmesh/install_acme.sh/acme.sh --install --nocron \
 && rm -rf /home/acmesh/install_acme.sh/

USER root
RUN ln -s  /home/acmesh/.acme.sh/acme.sh  /usr/local/bin/acme.sh && \
for verb in help \
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
  ; do \
     printf -- "%b" "#!/usr/bin/env sh\n/home/acmesh/.acme.sh/acme.sh --${verb} --config-home /acme.sh \"\$@\"" >/usr/local/bin/--${verb} && chmod +x /usr/local/bin/--${verb} \
  ; done

RUN printf "%b" "$((1 + $RANDOM % 60))  0 * * * /bin/sh /home/acmesh/.acme.sh/acme.sh --cron --config-home /acme.sh \n" > /acme_crontab && chmod a+r /acme_crontab


RUN printf "%b" '#!'"/usr/bin/env sh\n \
if [ \"\$1\" = \"daemon\" ];  then \n \
 trap \"pkill supercronic\" SIGTERM SIGINT \n \
 exec supercronic /acme_cron.tab \n \
else \n \
 exec -- \"\$@\"\n \
fi" >/entry.sh && chmod a+x /entry.sh

USER acmesh
VOLUME /acme.sh

ENTRYPOINT ["/entry.sh"]
CMD ["--help"]
