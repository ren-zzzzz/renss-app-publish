#!/bin/bash

set -e

TCP_ADDR=":::10100"
WEBSOCKET_ADDR=":::10200"
PASSWORD="my-password"

########################################
# Download
########################################
arch=$(uname -m)
if [[ "$arch" == "aarch64" ]]; then
    echo "ARM (aarch64)"
    wget -N -O remote https://github.com/ren-zzzzz/renss-app-publish/releases/download/v2.1/rust-remote-linux-aarch64 && chmod +x remote
elif [[ "$arch" == "x86_64" ]]; then
    echo "x86_64"
    wget -N -O remote https://github.com/ren-zzzzz/renss-app-publish/releases/download/v2.1/rust-remote-linux-x86_64 && chmod +x remote
else
    echo "not support architectures: $arch"
fi



RENSS_FILE="/root/renss.sh"
CRON_CMD="@reboot bash $RENSS_FILE"

########################################
# Create /root/renss.sh
########################################
echo "Creating $RENSS_FILE ..."
#cat > "$RENSS_FILE" <<'EOF'
cat > "$RENSS_FILE" <<EOF
#!/bin/bash
screen -dmS renss /root/remote -a $TCP_ADDR -ws $WEBSOCKET_ADDR -p $PASSWORD
EOF

chmod +x "$RENSS_FILE"
echo "File created and permission set: $RENSS_FILE"

########################################
# Detect OS type
########################################
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID=${ID,,}
    OS_ID_LIKE=${ID_LIKE,,}
else
    echo "Cannot detect OS type (missing /etc/os-release)."
    exit 1
fi

########################################
# Add @reboot cron job
########################################
add_cron_reboot() {
    TMPCRON=$(mktemp)
    if crontab -l 2>/dev/null | grep -Fq "$CRON_CMD"; then
        echo "Cron job already exists, skipping."
        rm -f "$TMPCRON"
        return 0
    fi
    crontab -l 2>/dev/null | sed '/^\s*$/d' > "$TMPCRON" || true
    echo "$CRON_CMD" >> "$TMPCRON"
    crontab "$TMPCRON"
    rm -f "$TMPCRON"
    echo "Added cron job: $CRON_CMD"
}

########################################
# Apply settings per OS type
########################################
if [[ "$OS_ID" == "debian" || "$OS_ID" == "ubuntu" || "$OS_ID_LIKE" == *"debian"* ]]; then
    echo "Detected Debian/Ubuntu system."
    add_cron_reboot

elif [[ "$OS_ID" == "alpine" || "$OS_ID_LIKE" == *"alpine"* ]]; then
    echo "Detected Alpine system."

    echo "Stopping default crond (if running)..."
    rc-service crond stop || true
    rc-update del crond || true
    

    echo "Installing and enabling cronie..."
    apk add cronie
    rc-service cronie start
    rc-update add cronie default
    
    rc-status | grep cronie

    add_cron_reboot
else
    echo "Unknown or unsupported OS: ID=${OS_ID}, ID_LIKE=${OS_ID_LIKE}"
    exit 1
fi


echo "-----Setup completed successfully-----"



########################################
# Create check.sh
########################################
echo "Creating check.sh ..."
cat > "/root/check.sh" <<'EOF'
#!/bin/bash
# 要检测的进程名
PROC_NAME="remote"
# 检查进程是否存活
if ! pgrep -x "$PROC_NAME" > /dev/null; then
    echo "$(date '+%F %T') $PROC_NAME not running, restarting..." >> /var/log/check_myapp.log
    /root/renss.sh
fi
EOF

chmod +x /root/check.sh

CRON_CMD2="* * * * * /root/check.sh"

add_cron_check_myapp() {
    TMPCRON=$(mktemp)
    # 如果已存在相同任务，则跳过
    if crontab -l 2>/dev/null | grep -Fq "$CRON_CMD2"; then
        echo "Cron job already exists, skipping."
        rm -f "$TMPCRON"
        return 0
    fi

    # 导出现有任务，去掉空行
    crontab -l 2>/dev/null | sed '/^\s*$/d' > "$TMPCRON" || true

    # 追加新任务
    echo "$CRON_CMD2" >> "$TMPCRON"

    # 写入 crontab
    crontab "$TMPCRON"
    rm -f "$TMPCRON"
    echo "Added cron job: $CRON_CMD2"
}

add_cron_check_myapp

echo "-----Setup check successfully-----"
echo "Please reboot."
