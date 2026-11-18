#!/bin/zsh
# One-time: create a self-signed code-signing certificate in a dedicated keychain.
# The keychain has its own random password (stored in ~/.config/iqube-companion, mode 600), so signing
# never needs your login password. Nothing here is uploaded or shared.
set -euo pipefail

KC="$HOME/Library/Keychains/iqube-signing.keychain-db"
DIR="$HOME/.config/iqube-companion"
PWF="$DIR/signing-keychain-password"
IDENTITY="iQube Companion Local Signing"

if [[ -f "$KC" ]] && security find-certificate -c "$IDENTITY" "$KC" >/dev/null 2>&1; then
  echo "Signing identity already exists."; exit 0
fi

mkdir -p "$DIR" && chmod 700 "$DIR"
[[ -f "$PWF" ]] || { openssl rand -hex 24 > "$PWF"; chmod 600 "$PWF"; }
PW="$(cat "$PWF")"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cs.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cs.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:tmp 2>/dev/null \
  || openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:tmp

[[ -f "$KC" ]] || security create-keychain -p "$PW" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "$PW" "$KC"
security import "$TMP/id.p12" -k "$KC" -P tmp -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PW" "$KC" >/dev/null
security list-keychains -d user -s $(security list-keychains -d user | tr -d '"') "$KC"
echo "Created signing identity \"$IDENTITY\" in $KC"
