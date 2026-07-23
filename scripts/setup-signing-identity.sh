#!/bin/bash
# Creates a stable, self-signed code-signing identity in the login keychain so that
# PromptBoard keeps the same code signature across rebuilds. macOS ties the
# Accessibility permission to the signature, so a stable identity means the grant
# persists — unlike ad-hoc signing, which changes identity on every build.
#
# One-time. macOS may prompt for your login password to import/trust the certificate.
set -euo pipefail

IDENTITY_NAME="PromptBoard Local Signing"

if security find-certificate -c "$IDENTITY_NAME" >/dev/null 2>&1; then
    echo "Signing identity '$IDENTITY_NAME' already exists — nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/req.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $IDENTITY_NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/req.cnf" >/dev/null 2>&1

# macOS `security import` needs a legacy-encrypted PKCS12 (3DES + SHA1 MAC); OpenSSL 3
# defaults to AES/SHA256 which fails to import. The fallback covers LibreSSL (no -legacy).
openssl pkcs12 -export -legacy -macalg sha1 -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY_NAME" -out "$TMP/identity.p12" -passout pass:promptboard >/dev/null 2>&1 \
  || openssl pkcs12 -export -macalg sha1 -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$IDENTITY_NAME" -out "$TMP/identity.p12" -passout pass:promptboard >/dev/null 2>&1

echo "Importing '$IDENTITY_NAME' into your login keychain…"
security import "$TMP/identity.p12" -P promptboard -T /usr/bin/codesign -A

echo "Trusting it for code signing (a password prompt here is normal)…"
security add-trusted-cert -r trustRoot -p codeSign "$TMP/cert.pem" 2>/dev/null \
    || echo "  (could not set trust automatically — if 'make app' later fails to sign, trust '$IDENTITY_NAME' for Code Signing in Keychain Access)"

echo "Done. '$IDENTITY_NAME' is ready — 'make app' will sign with it."
