#!/usr/bin/env sh
#
# Here is a script to deploy cert to minio server. This script can be called
# directly to test its configuration and see if its dependencies are installed.
# It requires the environment variable MINIO_CERTS_PATH to be set to the path
# where minio stores its certificates (--certs-dir). These must be supported by
# go. The documentation has recommendations under #supported-tls-cipher-suites,
# see: https://min.io/docs/minio/linux/operations/network-encryption.html
#
#
# MINIO_CERTS_PATH defaults to:
# * FreeBSD: /usr/local/etc/minio/certs/
# * Linux: ${HOME}/.minio/certs
#
## public functions ####################

minio_test() {
	test "$MINIO_CERTS_PATH" ||
		(echo 'environment variable MINIO_CERTS_PATH is required.' && kill $$)

	test -x "$(which openssl)" ||
		(echo 'no openssl installed, but required.' && kill $$)

	echo "All tests ok."
}

# $1=domain $2=keyfile $3=certfile $4=cafile $5=fullchain
minio_deploy() {
	openssl x509 \
		-in "$3" \
		-outform PEM \
		-out "$MINIO_CERTS_PATH/public.crt" ||
		return 1

	openssl ec \
		-in "$2" \
		-out "$MINIO_CERTS_PATH/private.key" ||
		return 1

	return 0
}

minio_test
