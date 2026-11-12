#!/bin/bash
set -e

IPAD_IP="192.168.1.106"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa,ssh-dss -o PubkeyAcceptedKeyTypes=+ssh-rsa -o BatchMode=yes"

APP_PATH="$1"
BUNDLE_ID="$2"

if [ -z "$APP_PATH" ] || [ -z "$BUNDLE_ID" ]; then
    echo "Kullanım: ./install_and_run.sh <App.app Yolu> <Bundle ID>"
    exit 1
fi

APP_NAME=$(basename "$APP_PATH")

echo "==> 1/3: $APP_NAME iPad'e kopyalanıyor..."
ssh $SSH_OPTS root@$IPAD_IP "rm -rf /Applications/$APP_NAME"
scp -r $SSH_OPTS -q "$APP_PATH" root@$IPAD_IP:/Applications/
ssh $SSH_OPTS root@$IPAD_IP "chmod -R 755 /Applications/$APP_NAME"

echo "==> 2/3: SpringBoard önbelleği yenileniyor (uicache)..."
ssh $SSH_OPTS root@$IPAD_IP "uicache"

echo "==> 3/3: Uygulama iPad ekranında başlatılıyor ($BUNDLE_ID)..."
ssh $SSH_OPTS root@$IPAD_IP "killall -9 $APP_NAME 2>/dev/null || true; open $BUNDLE_ID"

echo "==> Başarılı! Uygulama iPad Mini ekranında açıldı."
