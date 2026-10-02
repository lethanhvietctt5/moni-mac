#!/bin/bash
# CI only. Imports the stable self-signed identity into a temporary keychain on the runner, trusts its
# certificate for code signing (as create-signing-cert.sh does on the maintainer's Mac), and exports
# SIGNING_IDENTITY (its SHA-1 hash) and RELEASE_KEYCHAIN to later steps. remove-certificate.sh deletes it.
#
# Needs: MONIMAC_CERT_P12 (the .p12, base64) and MONIMAC_CERT_PASSWORD (its export password).
# It refuses to run outside GitHub Actions, so it can never touch a developer's keychains.
source "$(dirname "$0")/common.sh"
refuse_outside_ci

[ -n "${MONIMAC_CERT_P12:-}" ] || die "the MONIMAC_CERT_P12 secret is empty"
[ -n "${MONIMAC_CERT_PASSWORD:-}" ] || die "the MONIMAC_CERT_PASSWORD secret is empty"

KEYCHAIN="$RUNNER_TEMP/monimac-release.keychain-db"
KEYCHAIN_PASSWORD="$(uuidgen)"
P12="$RUNNER_TEMP/monimac.p12"
CERT="$RUNNER_TEMP/monimac.pem"
trap 'rm -f "$P12" "$CERT"' EXIT

printf '%s' "$MONIMAC_CERT_P12" | base64 -D >"$P12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "$MONIMAC_CERT_PASSWORD" -f pkcs12 -T /usr/bin/codesign
# Lets codesign use the key without a GUI prompt.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# Put it first in the search list, keeping the runner's own keychains (their paths have no spaces).
# shellcheck disable=SC2046
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')

# A self-signed certificate isn't trusted by default; trust it for code signing on this runner only.
security find-certificate -a -p "$KEYCHAIN" >"$CERT"
sudo security add-trusted-cert -d -r trustRoot -p codeSign -k /Library/Keychains/System.keychain "$CERT"

IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk 'NR == 1 && $2 ~ /^[0-9A-F]{40}$/ { print $2 }')"
[ -n "$IDENTITY" ] || { security find-identity -p codesigning "$KEYCHAIN" >&2; die "no valid code-signing identity in the p12"; }
echo "Signing with $(security find-identity -v -p codesigning "$KEYCHAIN" | head -1)"
{
    echo "SIGNING_IDENTITY=$IDENTITY"
    echo "RELEASE_KEYCHAIN=$KEYCHAIN"
} >>"$GITHUB_ENV"
