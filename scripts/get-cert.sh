#!/usr/bin/env bash

SCRIPT_DIR=$(dirname $0)
AUTH_SCRIPT=$SCRIPT_DIR/cert-auth.sh

if [[ -z $CERT_DIR ]]
then
  CERT_DIR="./.cert"
fi

if [[ -z "$CERT_ADMIN" ]]
then
  echo "Must set 'CERT_ADMIN' environment variable"
  exit 1
fi

if [[ -z "$CERT_DOMAIN" ]]
then
  echo "Must set 'CERT_DOMAIN' environment variable"
  exit 1
fi


# All the certbot things are redirected into a local folder.
# Makes sure the correct sub-directories all exist.
mkdir -p $CERT_DIR/{config,logs,work}

# Trying to make this just work. You will still need to update
# the DNS record to complete this.
certbot certonly \
  --agree-tos \
  --email $CERT_ADMIN \
  --domain "$CERT_DOMAIN" \
  --cert-path $CERT_DIR \
  --key-path $CERT_DIR \
  --rsa-key-size 4096 \
  --config-dir "$CERT_DIR/config" \
  --logs-dir "$CERT_DIR/logs" \
  --work-dir "$CERT_DIR/work" \
  --manual \
  --preferred-challenges "dns"
#   --non-interactive \
#   --manual-auth-hook "$AUTH_SCRIPT"
