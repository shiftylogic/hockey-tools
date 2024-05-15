#/usr/bin/env bash

# This script needs to be able to make a DNS TXT change on a specific domain
# Also, need a cleanup script that deletes it when complete.

# $CERTBOT_VALIDATION contains the validation string
# '_acme-challenge.DOMAIN_YOU_OWN' as a TXT record containing above
# $CERTBOT_DOMAIN contains the DOMAIN that you are attempting.

