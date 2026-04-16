#!/bin/bash

set -e

########################################
# Architecture detection
########################################
arch=$(uname -m)

case "$arch" in
    x86_64|amd64)
        ARCH_TYPE="x64"
        ;;
    aarch64|arm64)
        ARCH_TYPE="arm64"
        ;;
    *)
        echo "Unsupported architecture: $arch"
        exit 1
        ;;
esac

echo "Detected architecture: $ARCH_TYPE"


########################################
# Install dependency helper
########################################
install_if_missing() {
    name=$1

    if command -v "$name" >/dev/null 2>&1; then
        return
    fi

    echo "$name not found, installing..."

    if command -v apt >/dev/null 2>&1; then
        apt update && apt install -y "$name"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "$name"
    elif command -v apk >/dev/null 2>&1; then
        apk add "$name"
    else
        echo "No supported package manager found"
        exit 1
    fi
}


########################################
# Dependencies
########################################
install_if_missing screen
install_if_missing unzip
install_if_missing wget


########################################
# Detect libc type (glibc only)
########################################
echo "Detecting libc type..."

LIBC_TYPE="unknown"

if command -v ldd >/dev/null 2>&1; then
    if ldd --version 2>&1 | grep -qi musl; then
        LIBC_TYPE="musl"
    elif ldd --version 2>&1 | grep -qi glibc; then
        LIBC_TYPE="glibc"
    fi
fi

if [[ "$LIBC_TYPE" == "unknown" ]]; then
    if strings /lib*/libc.so.6 2>/dev/null | grep -qi glibc; then
        LIBC_TYPE="glibc"
    fi
fi

echo "Detected libc: $LIBC_TYPE"

if [[ "$LIBC_TYPE" != "glibc" ]]; then
    echo "This program only supports glibc systems"
    echo "Detected: $LIBC_TYPE"
    exit 1
fi


########################################
# Download binary
########################################
echo "Downloading remote binary..."

wget -O remote.zip "https://github.com/ren-zzzzz/renss-app-publish/releases/download/v2.2-beta/remote-linux-${ARCH_TYPE}.zip"

unzip -o remote.zip
rm -f remote.zip
chmod +x remote


########################################
# Create startup script
########################################
RENSS_FILE="/root/renss.sh"
CRON_CMD="@reboot bash $RENSS_FILE"

echo "Creating $RENSS_FILE ..."

cat > "$RENSS_FILE" <<EOF
#!/bin/bash
screen -dmS renss /root/remote
EOF

chmod +x "$RENSS_FILE"


########################################
# Add cron @reboot
########################################
add_cron_reboot() {
    TMPCRON=$(mktemp)

    if crontab -l 2>/dev/null | grep -Fq "$CRON_CMD"; then
        echo "Cron already exists"
        rm -f "$TMPCRON"
        return
    fi

    crontab -l 2>/dev/null | sed '/^\s*$/d' > "$TMPCRON" || true
    echo "$CRON_CMD" >> "$TMPCRON"
    crontab "$TMPCRON"

    rm -f "$TMPCRON"
    echo "Added cron: $CRON_CMD"
}

add_cron_reboot


########################################
# Create watchdog script
########################################
echo "Creating check.sh ..."

cat > "/root/check.sh" <<'EOF'
#!/bin/bash

PROC_NAME="remote"

if ! pgrep -x "$PROC_NAME" > /dev/null; then
    bash /root/renss.sh
fi
EOF

chmod +x /root/check.sh

CRON_CMD2="* * * * * /root/check.sh"

add_cron_check() {
    TMPCRON=$(mktemp)

    if crontab -l 2>/dev/null | grep -Fq "$CRON_CMD2"; then
        echo "Watchdog cron already exists"
        rm -f "$TMPCRON"
        return
    fi

    crontab -l 2>/dev/null | sed '/^\s*$/d' > "$TMPCRON" || true
    echo "$CRON_CMD2" >> "$TMPCRON"
    crontab "$TMPCRON"

    rm -f "$TMPCRON"
    echo "Added watchdog cron: $CRON_CMD2"
}

add_cron_check


echo "Setup completed successfully"
echo "Please reboot system"
