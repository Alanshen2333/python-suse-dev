#!/usr/bin/env bash
set -e

# host key 已在构建时生成并固化，无需运行时 ssh-keygen -A
mkdir -p /run/sshd

# 注入 SSH 公钥到 dev 用户（若提供 SSH_PUBKEY 环境变量）
if [ -n "$SSH_PUBKEY" ]; then
    install -d -m 700 -o dev -g dev /home/dev/.ssh
    printf '%s\n' "$SSH_PUBKEY" > /home/dev/.ssh/authorized_keys
    chmod 600 /home/dev/.ssh/authorized_keys
    chown dev:dev /home/dev/.ssh/authorized_keys
fi

# 启动 sshd（绑定 22 端口需要 root）
/usr/sbin/sshd

# 启动 code-server（仅 code 镜像存在该命令；以 dev 身份后台运行，仅监听 127.0.0.1，需经 SSH 隧道访问）
if command -v code-server >/dev/null 2>&1; then
    nohup runuser -l dev -c \
        'code-server --bind-addr 127.0.0.1:8080 --auth none --disable-telemetry /workspace' \
        >/var/log/code-server.log 2>&1 &
fi

# 传了命令就执行命令；有 TTY 且无命令则以 dev 登录进 fish；否则常驻让 sshd / code-server 提供服务
if [ $# -gt 0 ]; then
    exec "$@"
elif [ -t 0 ]; then
    exec runuser -l dev
else
    exec tail -f /dev/null
fi
