# Shared by the signing scripts. Sourced, not run.
# Nothing in these scripts prints the keystore password, and none of them passes it as a command
# argument: it goes from the login keychain into an environment variable of the one tool that needs it.

KEY_DIR="$HOME/.tenon-keys/android/passby"
KEYSTORE="$KEY_DIR/passby-release.p12"
KEY_ALIAS="passby"
KEYCHAIN_SERVICE="tenon-android-signing"
KEYCHAIN_ACCOUNT="passby"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANDROID_DIR="$(dirname "$SCRIPT_DIR")"
# The certificate's SHA-256 fingerprint, written when the key is created. It is public, and every
# release is checked against it.
FINGERPRINT_FILE="$ANDROID_DIR/release/signing-certificate.sha256"

export JAVA_HOME="${JAVA_HOME:-$(/usr/libexec/java_home -v 21)}"
SDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
BUILD_TOOLS="$SDK_DIR/build-tools/37.0.0"

fail() { echo "错误：$*" >&2; exit 1; }

# Puts the keystore password into PASSBY_KS_PASS for the commands that follow in this shell.
load_keystore_password() {
    PASSBY_KS_PASS="$(security find-generic-password -s "$KEYCHAIN_SERVICE" -a "$KEYCHAIN_ACCOUNT" -w 2>/dev/null)" \
        || fail "钥匙串里没有签名密钥的口令（服务 $KEYCHAIN_SERVICE，账户 $KEYCHAIN_ACCOUNT）"
    export PASSBY_KS_PASS
}

# Prints the certificate's fingerprint for one digest, upper-case hex without colons.
certificate_fingerprint() { # sha256 | sha1 | md5
    "$JAVA_HOME/bin/keytool" -exportcert -rfc -keystore "$KEYSTORE" -storetype PKCS12 -alias "$KEY_ALIAS" -storepass:env PASSBY_KS_PASS \
        | openssl x509 -noout -fingerprint "-$1" | sed -e 's/^.*=//' -e 's/://g'
}
