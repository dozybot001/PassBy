#!/bin/bash
# Backs up PassBy's Android signing key and proves the backup can be restored. Run with the founder
# present, before anything signed with the key is released or given to anyone else to install.
# Product standard 15.6.3.
#
# Usage: backup-signing-key.sh <first place> <second place>
#
# The two places are folders outside this Mac's own disk and apart from each other: a USB drive and
# a folder in iCloud Drive that is not shared, or two USB drives of which one is kept somewhere else.
#
# Run it in a terminal the founder types into. The image passphrase is read from the keyboard and
# must never be piped in, passed as an argument, or typed into a Claude session.
#
# The backup is one AES-256 encrypted disk image holding the keystore, its password and a note of the
# fingerprints. The keystore password is written straight into the mounted image, so it never rests on
# the ordinary disk. The image's own passphrase is typed by the founder and exists nowhere on this Mac.
set -euo pipefail
umask 077
source "$(dirname "${BASH_SOURCE[0]}")/signing-common.sh"

[ $# -eq 2 ] || fail "用法：backup-signing-key.sh <第一处的文件夹> <第二处的文件夹>"
FIRST_DIR="$1"
SECOND_DIR="$2"
[ -d "$FIRST_DIR" ] || fail "找不到第一处的文件夹：$FIRST_DIR"
[ -d "$SECOND_DIR" ] || fail "找不到第二处的文件夹：$SECOND_DIR"
[ "$(cd "$FIRST_DIR" && pwd -P)" != "$(cd "$SECOND_DIR" && pwd -P)" ] || fail "两处不能是同一个文件夹"
case "$(cd "$FIRST_DIR" && pwd -P)/" in "$HOME/.tenon-keys/"*) fail "第一处不能在放密钥的目录里" ;; esac
case "$(cd "$SECOND_DIR" && pwd -P)/" in "$HOME/.tenon-keys/"*) fail "第二处不能在放密钥的目录里" ;; esac
[ -f "$KEYSTORE" ] || fail "找不到密钥库：$KEYSTORE"
[ -f "$FINGERPRINT_FILE" ] || fail "找不到登记的证书指纹：$FINGERPRINT_FILE"
EXPECTED="$(tr -d '[:space:]' < "$FINGERPRINT_FILE")"

IMAGE="$KEY_DIR/passby-android-signing-key-$(date +%Y%m%d).dmg"
[ ! -e "$IMAGE" ] || fail "今天的备份映像已经存在，不覆盖：$IMAGE"

echo "请在密码管理器里生成一个备份口令（不少于 20 个字符），存好，再抄一份到纸上。"
# IFS is emptied so a space at either end of what is typed is kept.
IFS= read -r -s -p "备份口令：" BACKUP_PASS; echo
IFS= read -r -s -p "再输一次：" BACKUP_PASS_AGAIN; echo
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
# Worked out before the note is written: a command that fails inside a here-document does not stop the script.
NOTE_TIME="$(date '+%Y-%m-%d %H:%M')"
NOTE_SHA256="$(certificate_fingerprint sha256)"
NOTE_SHA1="$(certificate_fingerprint sha1)"
NOTE_MD5="$(certificate_fingerprint md5)"
[ "$NOTE_SHA256" = "$EXPECTED" ] || fail "这台 Mac 上的密钥库和登记的指纹对不上：${NOTE_SHA256}。不要备份它，先弄清楚。"
cp "$KEYSTORE" "$MOUNT/passby-release.p12"
printf '%s\n' "$PASSBY_KS_PASS" > "$MOUNT/keystore-password.txt"
cat > "$MOUNT/README.txt" <<NOTE
PassBy 安卓版的应用签名密钥。备份于 ${NOTE_TIME}。

passby-release.p12      PKCS12 密钥库，别名 $KEY_ALIAS
keystore-password.txt   密钥库的口令

证书指纹：
SHA-256  $NOTE_SHA256
SHA-1    $NOTE_SHA1
MD5      $NOTE_MD5

恢复：把 passby-release.p12 放回 ~/.tenon-keys/android/passby/（目录 0700，文件 0600），
把口令存进登录钥匙串（服务 ${KEYCHAIN_SERVICE}，账户 ${KEYCHAIN_ACCOUNT}），
再用 keytool -list -v 核对 SHA-256 指纹和上面一致。
NOTE
unset PASSBY_KS_PASS
hdiutil detach "$MOUNT" >/dev/null
chmod 600 "$IMAGE"

# 2. Restore drill: open the image again read-only and use what is inside it, both the certificate
#    and the private key. Reading the certificate alone would pass with a damaged private key.
printf '%s' "$BACKUP_PASS" | hdiutil attach "$IMAGE" -stdinpass -nobrowse -readonly -mountpoint "$DRILL" >/dev/null
unset BACKUP_PASS
PASSBY_KS_PASS="$(tr -d '\n' < "$DRILL/keystore-password.txt")"
export PASSBY_KS_PASS
RESTORED_CERT="$("$JAVA_HOME/bin/keytool" -exportcert -rfc -keystore "$DRILL/passby-release.p12" -storetype PKCS12 -alias "$KEY_ALIAS" -storepass:env PASSBY_KS_PASS)"
# The private key signs a certificate request.
REQUEST="$("$JAVA_HOME/bin/keytool" -certreq -keystore "$DRILL/passby-release.p12" -storetype PKCS12 -alias "$KEY_ALIAS" -storepass:env PASSBY_KS_PASS)"
unset PASSBY_KS_PASS
hdiutil detach "$DRILL" >/dev/null

RESTORED="$(printf '%s\n' "$RESTORED_CERT" | openssl x509 -noout -fingerprint -sha256 | sed -e 's/^.*=//' -e 's/://g')"
[ "$RESTORED" = "$EXPECTED" ] || fail "恢复演练没有通过：备份里的证书指纹是 ${RESTORED}，登记的是 ${EXPECTED}。不要用这份备份。"
# The request's signature has to verify. The system's openssl (LibreSSL) exits with 0 even when it
# does not, so the words it prints are what is checked.
REQUEST_CHECK="$(printf '%s\n' "$REQUEST" | openssl req -noout -verify 2>&1 || true)"
printf '%s\n' "$REQUEST_CHECK" | grep -q 'verify OK' || fail "恢复演练没有通过：备份里的私钥签出来的请求验签失败。不要用这份备份。"
# And the key that signed it has to be the one in the registered certificate.
REQUEST_KEY="$(printf '%s\n' "$REQUEST" | openssl req -noout -pubkey)"
CERT_KEY="$(printf '%s\n' "$RESTORED_CERT" | openssl x509 -noout -pubkey)"
[ -n "$REQUEST_KEY" ] && [ "$REQUEST_KEY" = "$CERT_KEY" ] || fail "恢复演练没有通过：备份里的私钥和证书不是一对。不要用这份备份。"
echo "恢复演练通过：从备份打开密钥库，用里面的私钥签名并验签成功；证书 SHA-256 指纹是 ${RESTORED}，和登记的一致。"

# 3. The same image to both places.
cp "$IMAGE" "$FIRST_DIR/"
cp "$IMAGE" "$SECOND_DIR/"
for copy in "$FIRST_DIR/$(basename "$IMAGE")" "$SECOND_DIR/$(basename "$IMAGE")"; do
    cmp -s "$IMAGE" "$copy" || fail "复制出去的映像和原件不一样：$copy"
done
echo "备份映像：$(basename "$IMAGE")，SHA-256 $(shasum -a 256 "$IMAGE" | cut -d' ' -f1)"
echo "已复制到：$FIRST_DIR"
echo "已复制到：$SECOND_DIR"
echo "请推出 U 盘并收好。备份口令在密码管理器里，另有一份纸质的。"
echo "纸质口令和 U 盘分开放。用了 iCloud 云盘的话，那个文件夹不要设成共享；用两个 U 盘的话，其中一个放到这台 Mac 不在的地方。"
