#!/usr/bin/env bash
set -e

# 生成 SSH 主机密钥（仅首次启动时需要）
mkdir -p /run/sshd
ssh-keygen -A >/dev/null 2>&1

# 注入 SSH 公钥：若提供了 SSH_PUBKEY 环境变量，写入 authorized_keys
if [ -n "$SSH_PUBKEY" ]; then
    mkdir -p /root/.ssh && chmod 700 /root/.ssh
    echo "$SSH_PUBKEY" > /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

# 启动 sshd
/usr/sbin/sshd

# 启动 code-server（仅 code 镜像存在该命令；后台运行，关闭鉴权便于本地开发，监听 0.0.0.0:8080）
if command -v code-server >/dev/null 2>&1; then
    nohup code-server \
        --bind-addr 0.0.0.0:8080 \
        --auth none \
        --disable-telemetry \
        /workspace >/var/log/code-server.log 2>&1 &
fi

# 传了命令就执行命令；有 TTY 且无命令则进 fish 交互；否则常驻让 sshd / code-server 提供服务
if [ $# -gt 0 ]; then
    exec "$@"
elif [ -t 0 ]; then
    exec fish
else
    exec tail -f /dev/null
fi
