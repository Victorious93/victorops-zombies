#!/usr/bin/env bash
# Re-sign an exported APK with v2 + v3 schemes and verify. Secrets come from env, never from the repo.
# Usage: tools/sign_apk.sh <apk>   env: VOZ_KEYSTORE_PATH VOZ_KEYSTORE_PASSWORD VOZ_KEY_ALIAS VOZ_KEY_PASSWORD ANDROID_HOME
set -euo pipefail
APK="$1"
BT="$(ls -d "$ANDROID_HOME"/build-tools/* | sort -V | tail -1)"
"$BT/apksigner" sign --ks "$VOZ_KEYSTORE_PATH" --ks-key-alias "$VOZ_KEY_ALIAS" \
  --ks-pass env:VOZ_KEYSTORE_PASSWORD --key-pass env:VOZ_KEY_PASSWORD \
  --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true "$APK"
"$BT/apksigner" verify --verbose --print-certs "$APK" | grep -E "Verified using v[23] |certificate SHA-256|Number of signers"
"$BT/apksigner" verify --verbose "$APK" | grep -q "v2 scheme (APK Signature Scheme v2): true"
"$BT/apksigner" verify --verbose "$APK" | grep -q "v3 scheme (APK Signature Scheme v3): true"
"$BT/aapt2" dump badging "$APK" | grep -E "^package:|minSdkVersion|targetSdkVersion|native-code|application-label:"
