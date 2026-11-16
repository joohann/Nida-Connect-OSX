#!/usr/bin/env bash
# Creates, once, a local self-signed code signing certificate in the login keychain, named as in
# config.json (signing.identity). It gives the app a stable signature: the Keychain recognises it
# after every build and update, so it does not keep asking for your password.
# Not needed with an Apple Developer ID.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
NAME=$(cfg signing.identity)
[[ "$NAME" == "-" || "$NAME" == "Developer ID"* ]] && { echo "signing.identity is '$NAME', nothing to do."; exit 0; }
if security find-identity -p codesigning | grep -q "\"$NAME\""; then echo "'$NAME' already exists."; exit 0; fi

DIR=$(mktemp -d); chmod 700 "$DIR"; trap 'rm -rf "$DIR"' EXIT
cat > "$DIR/cfg.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CNF
/usr/bin/openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -nodes \
  -keyout "$DIR/key.pem" -out "$DIR/cert.pem" -config "$DIR/cfg.cnf" 2>/dev/null
PASS=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$DIR/key.pem" -in "$DIR/cert.pem" -name "$NAME" \
  -out "$DIR/id.p12" -passout "pass:$PASS" 2>/dev/null
security import "$DIR/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign -f pkcs12
echo "Created: '$NAME' (valid for 10 years). Keep an export as a backup: without the same key"
echo "the Keychain asks for permission once more after an update."
