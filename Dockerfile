FROM alpine:3.22

ARG AUTO_UPGRADE=1

ENV LE_WORKING_DIR=/acmebin

ENV LE_CONFIG_HOME=/acme.sh

ENV AUTO_UPGRADE=$AUTO_UPGRADE

#Install
COPY . /install_acme.sh/

RUN sh -x /install_acme.sh/build.sh

VOLUME /acme.sh

ENTRYPOINT ["/entry.sh"]
CMD ["--help"]
