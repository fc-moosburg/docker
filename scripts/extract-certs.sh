#!/bin/sh
# ./export-traefik-v2-certificate.sh DOMAIN

set -e # abort on errors
set -u # abort on unset variables

# adjust these variables according to your setup
TRAEFIK_CERT_STORE="acme.json"
TRAEFIK_RESOLVER="mytlschallenge"
OUTPUT_DIR=${2:-/opt/services/bbb/certs}

# get acme file
docker cp traefik:/letsencrypt/acme.json $TRAEFIK_CERT_STORE

DOMAIN="$1"
if [ -z "$DOMAIN" ]; then
    echo "No domain given"
    exit 1
fi

# minor sanity checks
if [ ! -r "$TRAEFIK_CERT_STORE" ]; then
    echo "File $TRAEFIK_CERT_STORE not readable!"
    exit 1
fi
if ! grep "\"${DOMAIN}\"" "$TRAEFIK_CERT_STORE" > /dev/null; then
    echo "Domain $DOMAIN not found in $TRAEFIK_CERT_STORE"
    exit 1
fi

KEY_FILE="${OUTPUT_DIR}/${DOMAIN}.key"
CERT_FILE="${OUTPUT_DIR}/${DOMAIN}.crt"

# create new files with strict permissions (mktemp defaults to 600)
NEW_KEY_FILE="$(mktemp --tmpdir XXXXX.key.new)"
NEW_CERT_FILE="$(mktemp --tmpdir XXXXX.crt.new)"

# allow ssl-cert group to read certificates (for Debian systems)
chown root:root "$NEW_CERT_FILE" "$NEW_KEY_FILE"
chmod 640 "$NEW_CERT_FILE" "$NEW_KEY_FILE"

# extract certificate
cat "$TRAEFIK_CERT_STORE" | jq -r ".${TRAEFIK_RESOLVER}.Certificates[] | select(.domain.main==\"${DOMAIN}\") | .certificate" | base64 -d > "$NEW_CERT_FILE"

# extract private key
cat "$TRAEFIK_CERT_STORE" | jq -r ".${TRAEFIK_RESOLVER}.Certificates[] | select(.domain.main==\"${DOMAIN}\") | .key" | base64 -d > "$NEW_KEY_FILE"

# check if the contents changed
if ! diff -N "$NEW_CERT_FILE" "$CERT_FILE" > /dev/null; then
    # certificate changed, rotate files
    echo "Certificate $DOMAIN updated"
    mv "$NEW_CERT_FILE" "$CERT_FILE"
    mv "$NEW_KEY_FILE" "$KEY_FILE"
else
    # certificate unchanged, delete temporary files
    echo "Certificate $DOMAIN unchanged"
    rm -f "$NEW_CERT_FILE" "$NEW_KEY_FILE"
fi

rm -rf $TRAEFIK_CERT_STORE

exit 0
