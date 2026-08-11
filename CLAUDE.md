# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

基于 openSUSE Leap 16.0 的 Python 开发 Docker 镜像。单 Dockerfile 多阶段构建出两个镜像：
- **base** (`python-suse-dev:16.0`)：Python 3.13 + uv + 网络工具 + docker CLI(DooD) + fish/nvim 预配置 + sshd(仅密钥登录)
- **code** (`python-suse-dev-code:16.0`)：base 之上加 code-server Web IDE

## 常用命令

构建（base 是默认 target；code 镜像用 `--target code`）：
```bash
docker build -t python-suse-dev:16.0 .
docker build --target code -t python-suse-dev-code:16.0 .
```

运行（DooD 需挂载宿主机 docker socket —— 等同于把宿主机 root 交给容器，仅限本地开发）：
```bash
# base：SSH 2222
docker run -d --name psd \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -p 2222:22 \
  -e SSH_PUBKEY="$(cat ~/.ssh/id_ed25519.pub)" \
  python-suse-dev:16.0
ssh -p 2222 root@localhost   # 无密码，密钥认证

# code：再加 8080
docker run -d --name psd-code \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -p 2222:22 -p 8080:8080 \
  -e SSH_PUBKEY="$(cat ~/.ssh/id_ed25519.pub)" \
  python-suse-dev-code:16.0
```

进容器调试：`docker exec -it psd fish`

## 架构要点（需跨多文件理解）

### 单 entrypoint 服务两个镜像
`entrypoint.sh` 同时服务 base 和 code 两个镜像：启动 sshd → 若存在 `code-server` 二进制则后台起 Web IDE（靠 `command -v code-server` 检测，所以 base 镜像里没有它）→ 最后按参数/TTY 决定 `exec` 什么。正因如此 **Dockerfile 没有 `CMD`**：有参数 exec 参数；有 TTY 且无参数 exec fish；否则 `tail -f /dev/null` 保持容器存活。改动入口逻辑时三者都要兼顾。

### SSH 仅密钥认证（无密码）
无 root 密码。运行时通过 `SSH_PUBKEY` 环境变量注入 `/root/.ssh/authorized_keys`（entrypoint 处理）。sshd 配置写在 `/etc/ssh/sshd_config.d/00-dev.conf`（`PasswordAuthentication no` + `PermitRootLogin prohibit-password`）。注意 Leap 16 主配置在 `/usr/etc/ssh/sshd_config`，顶部 `Include` 是首次匹配优先语义，所以 `00-` 前缀保证最高优先级。

### DooD（非 DinD）
容器内装的是 docker CLI + buildx，通过挂载 `/var/run/docker.sock` 调用**宿主机** daemon。容器内 `docker ps` 看到的是宿主机容器。没有在容器内跑 dockerd。

### zypper 源不稳定 —— 重试循环别删
Leap 16 的 `cdn.opensuse.org` 镜像同步经常 403/404。Dockerfile 里 `sed` 把源切到 `https://download.opensuse.org` + 8 次重试（每次 10s + 重新 refresh）。这是构建能成功的关键，**不要为了"精简"把它删掉**。

### fish / nvim 在构建期完全预配置（非运行时）
- **nvim**：克隆 LazyVim starter 去掉 `.git`；Python extra 写进 `~/.config/nvim/lazyvim.json`；构建期 `nvim --headless` 跑 `Lazy! sync` + `MasonInstall pyright ruff`（带 `timeout 900` 和失败回退提示）。
- **fish**：fisher + autopair.fish + fzf.fish 在构建期装好；starship 用 `no-nerd-font` 预设。
- **uv**：astral.sh 脚本装到 `/root/.local/bin`，已加进 PATH；系统级包用 `uv pip install --system`。

### openSUSE 的 npm 与 node 是分开的包
`nodejs22` 只含 node 二进制。npm 需单独装 `npm22` + `npm-default`（Mason 装 pyright 需要 npm）。`/usr/bin/npm` 和 `/usr/bin/node` 是 libalternatives 的 ELF 包装器（`alts -l <name>` 查看注册的替代项）。

## 约定

- **fish 配置保持精简**：`fish/config.fish` 只有 PATH / 编辑器变量 / fzf 选项 / starship init。用户明确拒绝过自定义 alias/abbr（"太小众"），不要擅自加。
- 构建出的两个镜像 tag 都带 `:16.0`。
