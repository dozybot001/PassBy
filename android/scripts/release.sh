#!/bin/bash
# Builds PassBy for Android and signs it with the app signing key. It does not publish anything.
# Product standard 15.6.4 and 15.6.7.
#
# Signing happens here and not in Gradle, so the password never reaches the Gradle daemon or a build
# file. Without the real key this stops; it never falls back to another key.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/signing-common.sh"

PACKAGE="cn.tenonai.apps.passby"
[ -f "$KEYSTORE" ] || fail "找不到正式签名密钥：$KEYSTORE。没有它不出正式包。"
[ -f "$FINGERPRINT_FILE" ] || fail "找不到登记的证书指纹：$FINGERPRINT_FILE"
EXPECTED="$(tr -d '[:space:]' < "$FINGERPRINT_FILE")"

cd "$ANDROID_DIR"
[ -z "$(git status --porcelain -- . ../docs/export-vectors.json)" ] || fail "android/ 里有没提交的改动。发布的包要对得上一个提交。"
VERSION="$(sed -n 's/^ *versionName = "\(.*\)"$/\1/p' app/build.gradle.kts)"
[ -n "$VERSION" ] || fail "读不到版本号"

./gradlew --console=plain clean :app:testDebugUnitTest :app:lintRelease :app:assembleRelease
UNSIGNED="app/build/outputs/apk/release/app-release-unsigned.apk"
[ -f "$UNSIGNED" ] || fail "没有生成未签名的正式包：$UNSIGNED"

OUT_DIR="$ANDROID_DIR/build/release"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
APK="$OUT_DIR/PassBy-$VERSION.apk"

# Signature schemes v2 and v3 only: the app needs Android 8.0, which does not use v1.
load_keystore_password
"$BUILD_TOOLS/apksigner" sign \
    --ks "$KEYSTORE" --ks-type PKCS12 --ks-key-alias "$KEY_ALIAS" --ks-pass env:PASSBY_KS_PASS \
    --min-sdk-version 26 \
    --v1-signing-enabled false --v2-signing-enabled true --v3-signing-enabled true --v4-signing-enabled false \
    --out "$APK" "$UNSIGNED"
unset PASSBY_KS_PASS

# 1. The certificate in the package is the registered one, or the package is thrown away.
VERIFY="$("$BUILD_TOOLS/apksigner" verify --verbose --print-certs --min-sdk-version 26 "$APK")"
# Older build tools print "Signer #1 certificate SHA-256 digest", newer ones "V3.0 Signer: certificate SHA-256 digest".
ACTUAL="$(printf '%s\n' "$VERIFY" | sed -n 's/^.*Signer.*certificate SHA-256 digest: //p' | sort -u | tr 'a-f' 'A-F')"
printf '%s\n' "$VERIFY" | grep -q '^Number of signers: 1$' || { rm -f "$APK"; fail "签名者不是恰好一个"; }
if [ "$ACTUAL" != "$EXPECTED" ]; then
    rm -f "$APK"
    fail "签名证书的 SHA-256 是 $ACTUAL，登记的是 $EXPECTED。已删除这个包。"
fi
printf '%s\n' "$VERIFY" | grep -q '^Verified using v1 scheme (JAR signing): false' || { rm -f "$APK"; fail "包里有 v1 签名"; }
printf '%s\n' "$VERIFY" | grep -q '^Verified using v2 scheme (APK Signature Scheme v2): true' || { rm -f "$APK"; fail "包里没有 v2 签名"; }
printf '%s\n' "$VERIFY" | grep -q '^Verified using v3 scheme (APK Signature Scheme v3): true' || { rm -f "$APK"; fail "包里没有 v3 签名"; }

# 2. The package is the app, is not debuggable, and asks for no network permission.
BADGING="$("$BUILD_TOOLS/aapt2" dump badging "$APK")"
PERMISSIONS="$("$BUILD_TOOLS/aapt2" dump permissions "$APK")"
printf '%s\n' "$BADGING" | grep -q "^package: name='$PACKAGE' " || { rm -f "$APK"; fail "包名不是 $PACKAGE"; }
printf '%s\n' "$BADGING" | grep -q "versionName='$VERSION'" || { rm -f "$APK"; fail "版本号不是 $VERSION"; }
if printf '%s\n' "$BADGING" | grep -q 'application-debuggable'; then rm -f "$APK"; fail "这个包可以调试"; fi
if printf '%s\n' "$PERMISSIONS" | grep -E -q 'INTERNET|NETWORK|WIFI'; then rm -f "$APK"; fail "这个包申请了网络相关的权限"; fi

( cd "$OUT_DIR" && shasum -a 256 "$(basename "$APK")" > SHA256SUMS )

echo
echo "正式包：$APK"
echo "提交：$(git rev-parse HEAD)"
echo "证书 SHA-256：$ACTUAL（和登记的一致）"
echo "权限："
printf '%s\n' "$PERMISSIONS" | sed 's/^/  /'
echo "SHA256SUMS："
sed 's/^/  /' "$OUT_DIR/SHA256SUMS"
echo
echo "这一步没有发布任何东西。放到 Releases 要等仓库公开、备份和恢复演练做完，并由创始人确认。"
