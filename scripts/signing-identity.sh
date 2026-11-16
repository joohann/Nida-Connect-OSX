#!/usr/bin/env bash
# Maakt eenmalig een lokaal, zelfondertekend code-signing-certificaat in de login-sleutelhanger,
# met de naam uit config.json (signing.identity). Daarmee heeft de app een vaste handtekening:
# de Sleutelhanger herkent hem na elke build en update, dus geen herhaalde wachtwoordvragen.
# Niet nodig met een Apple Developer ID.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh
NAME=$(cfg signing.identity)
[[ "$NAME" == "-" || "$NAME" == "Developer ID"* ]] && { echo "signing.identity is '$NAME', niets te doen."; exit 0; }
if security find-identity -p codesigning | grep -q "\"$NAME\""; then echo "'$NAME' bestaat al."; exit 0; fi

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
echo "Aangemaakt: '$NAME' (10 jaar geldig). Bewaar een export als back-up: zonder dezelfde sleutel"
echo "vraagt de Sleutelhanger na een update weer eenmalig om toestemming."
