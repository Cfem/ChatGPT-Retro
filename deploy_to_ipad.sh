#!/bin/bash
set -e

IPAD_IP="192.168.1.106"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedKeyTypes=+ssh-rsa -o BatchMode=yes"

APP_PATH="$1"
BUNDLE_ID="$2"

if [ -z "$APP_PATH" ] || [ -z "$BUNDLE_ID" ]; then
    echo "Kullanım: ./deploy_to_ipad.sh <App.app Yolu> <Bundle ID>"
    exit 1
fi

APP_DIR=$(dirname "$APP_PATH")
APP_NAME=$(basename "$APP_PATH")

echo "==> 1/3: $APP_NAME iPad'e aktarılıyor ($IPAD_IP)..."
tar --no-xattrs -C "$APP_DIR" -cf - "$APP_NAME" | ssh $SSH_OPTS root@$IPAD_IP "rm -rf /Applications/$APP_NAME && tar -C /Applications -xf - && chown -R mobile:staff /Applications/$APP_NAME && chmod -R 755 /Applications/$APP_NAME"

echo "==> 2/3: SpringBoard ikonu güncelleniyor (uicache)..."
ssh $SSH_OPTS root@$IPAD_IP "uicache"

echo "==> 3/3: Uygulama iPad ekranında başlatılıyor ($BUNDLE_ID)..."
ssh $SSH_OPTS root@$IPAD_IP "open $BUNDLE_ID"

echo "==> [TAMAMLANDI] $APP_NAME başarıyla iPad Mini ekranında açıldı!"
