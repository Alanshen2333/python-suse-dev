# ===== base 镜像：Python + uv + 网络工具 + docker(DooD) + fish + nvim + sshd =====
FROM opensuse/leap:16.0 AS base

# 刷新软件源，安装 Python 3.13、网络工具、docker CLI(DooD)、fish/neovim 工具链
# openSUSE Leap 16 镜像源同步偶发 403/404，切 https download 源 + 多次重试
RUN sed -i -e 's|http://cdn.opensuse.org|https://download.opensuse.org|g' \
           -e 's|https://cdn.opensuse.org|https://download.opensuse.org|g' \
           /etc/zypp/repos.d/*.repo && \
    set -e; \
    for i in $(seq 1 8); do \
      if zypper --gpg-auto-import-keys refresh && \
         zypper --non-interactive install --no-recommends \
            python313 python313-pip python313-devel python313-virtualenv python3 \
            curl wget git bind-utils iputils netcat-openbsd tcpdump socat telnet \
            traceroute openssh openssh-server openssl jq vim neovim fish rsync \
            httpie ca-certificates \
            docker docker-buildx docker-bash-completion \
            nodejs22 npm22 npm-default ripgrep fd fzf tree starship; then \
         break; \
      fi; \
      echo "==> zypper 第 $i 次失败，10s 后重试"; sleep 10; \
      [ $i -eq 8 ] && exit 1; \
    done; \
    zypper clean --all

LABEL maintainer="alan"
LABEL description="openSUSE Leap 16 + Python 3.13 + uv + 网络工具 + docker(DooD) + fish/nvim 预配置 + sshd(密钥登录)"

# python / python3 指向 3.13
RUN ln -sf /usr/bin/python3.13 /usr/bin/python && \
    ln -sf /usr/bin/python3.13 /usr/bin/python3

# uv 装到系统路径 /usr/local/bin，root 与 dev 用户共用
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# 预装常用 Python 网络开发库（系统级，所有用户可用）
RUN uv pip install --system --no-cache \
        requests httpx aiohttp websockets fastapi uvicorn flask pytest rich

# SSH 仅密钥登录：禁止 root 登录，dev 用户密钥认证；运行时通过 SSH_PUBKEY 注入公钥
RUN printf 'PasswordAuthentication no\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/00-dev.conf
# sshd host key 构建时一次性生成并固化进镜像（注意：勿将镜像推到公开 registry，否则指纹泄露可被 MITM）
RUN ssh-keygen -A

# 创建 dev 用户（UID 1000，fish 登录 shell），加入 docker 组以便使用 DooD docker CLI
RUN useradd -m -u 1000 -s /usr/bin/fish -G docker dev && \
    mkdir -p /workspace && chown dev:dev /workspace

# ---- 以下以 dev 用户身份预配置 fish / nvim ----
USER dev
# fish 配置
COPY --chown=dev:dev fish/config.fish /home/dev/.config/fish/config.fish
# starship 提示符：no-nerd-font 预设，浏览器终端也能正常显示
RUN starship preset no-nerd-font -o /home/dev/.config/starship.toml
# fisher + 插件（autopair 自动补全括号、fzf.fish 模糊查找）
RUN fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher jorgebucaran/autopair.fish patrickf1/fzf.fish"

# ---- nvim 预配置（LazyVim + Python extra）----
RUN git clone --depth 1 https://github.com/LazyVim/starter /home/dev/.config/nvim \
    && rm -rf /home/dev/.config/nvim/.git
# 启用 Python extra（LSP/pyright + ruff + DAP）
RUN printf '{\n  "extras": ["lazyvim.plugins.extras.lang.python"],\n  "version": 6\n}\n' > /home/dev/.config/nvim/lazyvim.json
# 构建期预装插件 + Python LSP（best-effort，失败则首次启动自动 bootstrap，不阻断构建）
RUN timeout 900 nvim --headless "+Lazy! sync" "+MasonInstall pyright ruff" +qa \
    || echo "==> nvim 预装未完成，将首次启动自动 bootstrap"

ENV EDITOR=nvim VISUAL=nvim

# ---- 切回 root 装入口脚本（sshd 绑定 22 端口需要 root，entrypoint 内部再切 dev）----
USER root
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]


# ===== code 镜像：base + code-server（Web IDE）=====
FROM base AS code
LABEL description="python-suse-dev base + code-server Web IDE"
# code-server 装到系统路径（/usr/bin），dev 用户经 SSH 隧道访问
RUN curl -fsSL https://code-server.dev/install.sh | sh
EXPOSE 8080
