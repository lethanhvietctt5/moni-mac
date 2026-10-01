#!/bin/bash
# Creates a stable self-signed code-signing identity, "MoniMac Self-Signed", in your login keychain.
#
# Why: ad-hoc signatures change on every build, so macOS forgets permissions granted to
# MoniMac (notifications, audio capture, location). A stable identity keeps them.
#
# After running, add this line to Config/Local.xcconfig (gitignored):
#     CODE_SIGN_IDENTITY = MoniMac Self-Signed
#
# macOS will ask for your login password to trust the certificate for code signing.
# On the first build with this identity, macOS asks whether codesign may use the key: choose "Always Allow".
set -euo pipefail

NAME="MoniMac Self-Signed"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
# Use the system LibreSSL: Homebrew's OpenSSL 3 writes .p12 files `security import` rejects.
OPENSSL=/usr/bin/openssl

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "\"$NAME\" already exists in your login keychain. Nothing to do."
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat >"$WORK/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$WORK/cert.cnf" -keyout "$WORK/key.pem" -out "$WORK/cert.pem"
"$OPENSSL" pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
    -name "$NAME" -passout pass:monimac -out "$WORK/cert.p12"

security import "$WORK/cert.p12" -k "$KEYCHAIN" -P monimac -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$WORK/cert.pem"

echo
security find-identity -v -p codesigning | grep "$NAME"
echo "Done. Now add to Config/Local.xcconfig:  CODE_SIGN_IDENTITY = $NAME"
echo "On the first build, macOS asks whether codesign may use the key: choose \"Always Allow\"."
