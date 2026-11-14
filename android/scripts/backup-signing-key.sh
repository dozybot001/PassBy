#!/bin/bash
# Backs up PassBy's Android signing key and proves the backup can be restored. Run on the day the key
# is created, with the founder present. Product standard 15.6.3.
#
# Usage: backup-signing-key.sh <folder in iCloud Drive> <folder on the USB drive>
#
# The backup is one AES-256 encrypted disk image holding the keystore, its password and a note of the
# fingerprints. The keystore password is written straight into the mounted image, so it never rests on
# the ordinary disk. The image's own passphrase is typed by the founder and exists nowhere on this Mac.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/signing-common.sh"

[ $# -eq 2 ] || fail "用法：backup-signing-key.sh <iCloud 云盘里的文件夹> <U 盘上的文件夹>"
ICLOUD_DIR="$1"
USB_DIR="$2"
[ -d "$ICLOUD_DIR" ] || fail "找不到 iCloud 云盘里的文件夹：$ICLOUD_DIR"
[ -d "$USB_DIR" ] || fail "找不到 U 盘上的文件夹：$USB_DIR"
[ -f "$KEYSTORE" ] || fail "找不到密钥库：$KEYSTORE"
[ -f "$FINGERPRINT_FILE" ] || fail "找不到登记的证书指纹：$FINGERPRINT_FILE"
EXPECTED="$(tr -d '[:space:]' < "$FINGERPRINT_FILE")"

IMAGE="$KEY_DIR/passby-android-signing-key-$(date +%Y%m%d).dmg"
[ ! -e "$IMAGE" ] || fail "今天的备份映像已经存在，不覆盖：$IMAGE"

echo "请在密码管理器里生成一个备份口令（不少于 20 个字符），存好，再抄一份到纸上。"
read -r -s -p "备份口令：" BACKUP_PASS; echo
read -r -s -p "再输一次：" BACKUP_PASS_AGAIN; echo
[ "$BACKUP_PASS" = "$BACKUP_PASS_AGAIN" ] || fail "两次输入的不一样"
[ "${#BACKUP_PASS}" -ge 20 ] || fail "备份口令不少于 20 个字符"
unset BACKUP_PASS_AGAIN

MOUNT="$(mktemp -d)"
DRILL="$(mktemp -d)"
cleanup() {
    hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
    hdiutil detach "$DRILL" >/dev/null 2>&1 || true
    rmdir "$MOUNT" "$DRILL" 2>/dev/null || true
}
trap cleanup EXIT

# 1. An empty encrypted image, then the three files written into it while it is mounted.
printf '%s' "$BACKUP_PASS" | hdiutil create -size 16m -fs APFS -volname PassBySigningKey -encryption AES-256 -stdinpass "$IMAGE" >/dev/null
printf '%s' "$BACKUP_PASS" | hdiutil attach "$IMAGE" -stdinpass -nobrowse -mountpoint "$MOUNT" >/dev/null

load_keystore_password
cp "$KEYSTORE" "$MOUNT/passby-release.p12"
printf '%s\n' "$PASSBY_KS_PASS" > "$MOUNT/keystore-password.txt"
cat > "$MOUNT/README.txt" <<NOTE
PassBy 安卓版的应用签名密钥。备份于 $(date '+%Y-%m-%d %H:%M')。

passby-release.p12      PKCS12 密钥库，别名 $KEY_ALIAS
keystore-password.txt   密钥库的口令

证书指纹：
SHA-256  $(certificate_fingerprint sha256)
SHA-1    $(certificate_fingerprint sha1)
MD5      $(certificate_fingerprint md5)

恢复：把 passby-release.p12 放回 ~/.tenon-keys/android/passby/（目录 0700，文件 0600），
把口令存进登录钥匙串（服务 $KEYCHAIN_SERVICE，账户 $KEYCHAIN_ACCOUNT），
再用 keytool -list -v 核对 SHA-256 指纹和上面一致。
NOTE
unset PASSBY_KS_PASS
hdiutil detach "$MOUNT" >/dev/null
chmod 600 "$IMAGE"

# 2. Restore drill: open the image again read-only, open the keystore with the password inside it,
#    and compare the certificate with the registered fingerprint.
printf '%s' "$BACKUP_PASS" | hdiutil attach "$IMAGE" -stdinpass -nobrowse -readonly -mountpoint "$DRILL" >/dev/null
unset BACKUP_PASS
PASSBY_KS_PASS="$(tr -d '\n' < "$DRILL/keystore-password.txt")"
export PASSBY_KS_PASS
RESTORED="$("$JAVA_HOME/bin/keytool" -exportcert -rfc -keystore "$DRILL/passby-release.p12" -storetype PKCS12 -alias "$KEY_ALIAS" -storepass:env PASSBY_KS_PASS \
    | openssl x509 -noout -fingerprint -sha256 | sed -e 's/^.*=//' -e 's/://g')"
unset PASSBY_KS_PASS
hdiutil detach "$DRILL" >/dev/null
[ "$RESTORED" = "$EXPECTED" ] || fail "恢复演练没有通过：备份里的证书指纹是 $RESTORED，登记的是 $EXPECTED。不要用这份备份。"
echo "恢复演练通过：从备份打开密钥库，证书 SHA-256 指纹是 $RESTORED，和登记的一致。"

# 3. The same image to both places.
cp "$IMAGE" "$ICLOUD_DIR/"
cp "$IMAGE" "$USB_DIR/"
for copy in "$ICLOUD_DIR/$(basename "$IMAGE")" "$USB_DIR/$(basename "$IMAGE")"; do
    cmp -s "$IMAGE" "$copy" || fail "复制出去的映像和原件不一样：$copy"
done
echo "备份映像：$(basename "$IMAGE")，SHA-256 $(shasum -a 256 "$IMAGE" | cut -d' ' -f1)"
echo "已复制到：$ICLOUD_DIR"
echo "已复制到：$USB_DIR"
echo "请推出 U 盘并收好。备份口令在密码管理器里，另有一份纸质的。"
