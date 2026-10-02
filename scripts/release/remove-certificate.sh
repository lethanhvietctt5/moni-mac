#!/bin/bash
# CI only. Deletes the temporary keychain import-certificate.sh made. The workflow runs it even after failures.
source "$(dirname "$0")/common.sh"
refuse_outside_ci

if [ -n "${RELEASE_KEYCHAIN:-}" ] && [ -e "$RELEASE_KEYCHAIN" ]; then
    security delete-keychain "$RELEASE_KEYCHAIN"
fi
