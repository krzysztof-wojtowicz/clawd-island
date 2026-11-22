#!/bin/bash
# Creates the self-signed "ClawdIsland" code-signing identity in the login keychain (ADR-0008). Run once.
# Trusting the certificate asks for your login password. Safe to re-run: it does nothing if the identity exists.
set -euo pipefail

name="ClawdIsland"
keychain="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$name\""; then
    echo "\"$name\" already exists and is valid; nothing to do."
    exit 0
fi

# Imported earlier but never trusted (for example, the password dialog was cancelled): only retry the trust step,
# so a second identity with the same name never makes `codesign -s` ambiguous.
if security find-identity -p codesigning | grep -q "\"$name\""; then
    cert="$(mktemp)"
    trap 'rm -f "$cert"' EXIT
    security find-certificate -c "$name" -p "$keychain" > "$cert"
    echo "Trusting the existing \"$name\" certificate for code signing; macOS will ask for your login password."
    security add-trusted-cert -p codeSign -k "$keychain" "$cert"
    security find-identity -v -p codesigning | grep -q "\"$name\"" \
        && echo "Done. scripts/bundle.sh now signs with \"$name\"." \
        || { echo "\"$name\" is still not valid; check it in Keychain Access." >&2; exit 1; }
    exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
password="$(uuidgen)" # only protects the temporary .p12

cat > "$work/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $name
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

# The system LibreSSL is used on purpose: its .p12 format imports into the keychain, newer OpenSSL 3 ones may not.
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$work/openssl.cnf" \
    -keyout "$work/key.pem" -out "$work/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" -name "$name" \
    -out "$work/id.p12" -passout "pass:$password"

security import "$work/id.p12" -k "$keychain" -P "$password" -T /usr/bin/codesign
echo "Trusting the certificate for code signing; macOS will ask for your login password."
security add-trusted-cert -p codeSign -k "$keychain" "$work/cert.pem"

if security find-identity -v -p codesigning | grep -q "\"$name\""; then
    echo "Done. scripts/bundle.sh now signs with \"$name\"."
    echo "The first signing may show a keychain prompt for codesign; choose \"Always Allow\"."
else
    echo "\"$name\" was imported but is not valid; check it in Keychain Access, then re-run this script." >&2
    exit 1
fi
