#!/bin/bash
# Creates PassBy's Android app signing key. Run once, on the development Mac, on a day the founder
# can make the backups (backup-signing-key.sh) straight afterwards. Product standard 15.6.
#
# The key cannot be replaced: an update signed with another key will not install over the app, and
# uninstalling erases a notebook that exists only on the phone.
#
# The password is generated here, goes straight into the login keychain and is never shown.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/signing-common.sh"

# The comma in the company name is escaped so keytool does not read " Ltd." as another field.
DNAME='CN=PassBy, O=Changsha Tenon Artificial Intelligence Technology Co.\, Ltd., L=Changsha, C=CN'

[ ! -e "$KEYSTORE" ] || fail "密钥库已经存在，不覆盖：$KEYSTORE"
security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" >/dev/null 2>&1 \
    && fail "钥匙串里已经有同名条目（服务 $KEYCHAIN_SERVICE，账户 $KEYCHAIN_ACCOUNT）。先弄清它是什么，不要覆盖。"

mkdir -p "$KEY_DIR"
chmod 700 "$HOME/.tenon-keys" "$HOME/.tenon-keys/android" "$KEY_DIR"

# 32 random bytes from the system, as 43 characters of URL-safe base64.
PASSBY_KS_PASS="$(openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n')"
[ "${#PASSBY_KS_PASS}" -eq 43 ] || fail "没有生成出口令"
export PASSBY_KS_PASS

# The password is stored before the key exists, so there is never a keystore whose password is lost.
# `security -i` takes the command on standard input and printf is part of the shell, so the password
# is not in any process's arguments.
printf 'add-generic-password -s %s -a %s -l "PassBy Android signing key" -w %s\n' \
    "$KEYCHAIN_SERVICE" "$KEYCHAIN_ACCOUNT" "$PASSBY_KS_PASS" | security -i
[ "$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w)" = "$PASSBY_KS_PASS" ] \
    || fail "口令没有存进钥匙串"

# RSA 4096, valid for 30 years. In a PKCS12 keystore the key uses the keystore's password.
"$JAVA_HOME/bin/keytool" -genkeypair \
    -keystore "$KEYSTORE" -storetype PKCS12 -alias "$KEY_ALIAS" \
    -keyalg RSA -keysize 4096 -sigalg SHA256withRSA -validity 10950 \
    -dname "$DNAME" -storepass:env PASSBY_KS_PASS
chmod 600 "$KEYSTORE"

SHA256="$(certificate_fingerprint sha256)"
SHA1="$(certificate_fingerprint sha1)"
MD5="$(certificate_fingerprint md5)"
unset PASSBY_KS_PASS

mkdir -p "$(dirname "$FINGERPRINT_FILE")"
umask 022
printf '%s\n' "$SHA256" > "$FINGERPRINT_FILE"

echo "密钥库：$KEYSTORE"
echo "证书主体：$DNAME"
echo "证书指纹（不是秘密，登记到 docs/android.md 和支持页）："
echo "  SHA-256  $SHA256"
echo "  SHA-1    $SHA1"
echo "  MD5      $MD5"
echo "已写入 $FINGERPRINT_FILE"
echo "下一步：马上运行 backup-signing-key.sh 做备份和恢复演练。"
