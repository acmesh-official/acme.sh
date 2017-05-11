FROM alpine

RUN apk update -f \
  && apk --no-cache add -f \
  openssl \
  curl \
  netcat-openbsd

ENV LE_CONFIG_HOME /acme.sh

ENV AUTO_UPGRADE 1

#Install
RUN mkdir -p /install_acme.sh/
ADD ./ /install_acme.sh/
RUN cd /install_acme.sh && ([ -f /install_acme.sh/acme.sh ] && /install_acme.sh/acme.sh --install || curl https://get.acme.sh | sh)
RUN rm -rf /install_acme.sh/

RUN ln -s  /root/.acme.sh/acme.sh  /usr/local/bin/acme.sh

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
  ; do \
    printf -- "%b" "#!/usr/bin/env sh\n/root/.acme.sh/acme.sh --${verb} --config-home /acme.sh \"\$@\"" >/usr/local/bin/--${verb} && chmod +x /usr/local/bin/--${verb} \
  ; done

RUN printf "%b" '#!'"/usr/bin/env sh\n \
if [ \"\$1\" = \"daemon\" ];  then \n \
 crond; tail -f /dev/null;\n \
else \n \
 /root/.acme.sh/acme.sh --config-home /acme.sh \"\$@\"\n \
fi" >/entry.sh && chmod +x /entry.sh

VOLUME /acme.sh

ENTRYPOINT ["/entry.sh"]
CMD ["--help"]
