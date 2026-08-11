# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 这是什么

基于 openSUSE Leap 16.0 的 Python 开发 Docker 镜像。单 Dockerfile 多阶段构建出两个镜像：
- **base** (`ghcr.io/alanshen2333/python-suse-dev:16.0`)：Python 3.13 + uv + 网络工具 + docker CLI(DooD) + fish/nvim 预配置 + sshd(仅密钥登录)
- **code** (`ghcr.io/alanshen2333/python-suse-dev-code:16.0`)：base 之上加 code-server Web IDE

CI：`.github/workflows/docker.yml`，nightly + 手动 + main 分支相关文件变更时构建推送 GHCR（多架构 amd64/arm64）。注意 GHCR tag 必须全小写，`github.repository_owner` 含大写会直接 buildx 报错，所以镜像名硬编码小写。

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
ssh -p 2222 dev@localhost   # dev 用户，密钥认证

# code 镜像：code-server 仅监听 127.0.0.1:8080 且无密码，必须 SSH 隧道访问
docker run -d --name psd-code \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -p 2222:22 \
  -e SSH_PUBKEY="$(cat ~/.ssh/id_ed25519.pub)" \
  python-suse-dev-code:16.0
ssh -p 2222 -L 8080:127.0.0.1:8080 dev@localhost   # 然后浏览器开 localhost:8080
```

进容器调试：`docker exec -it psd fish`（注意 exec 进去是 root，SSH 进去才是 dev）

## 架构要点（需跨多文件理解）

### 单 entrypoint 服务两个镜像
`entrypoint.sh` 同时服务 base 和 code 两个镜像：注入 `SSH_PUBKEY` → 启动 sshd → 若存在 `code-server` 二进制则以 dev 身份后台起 Web IDE（靠 `command -v code-server` 检测，base 镜像里没有它）→ 最后按参数/TTY 决定 `exec` 什么。正因如此 **Dockerfile 没有 `CMD`**：有参数 exec 参数；有 TTY 且无参数 exec `runuser -l dev` 进 fish；否则 `tail -f /dev/null` 保持容器存活。改动入口逻辑时三者都要兼顾。

### SSH 仅密钥认证 + dev 用户（非 root）
无密码登录。`PermitRootLogin no`，固定用 **dev 用户**（UID 1000，fish shell，docker 组成员）。运行时 entrypoint 把 `SSH_PUBKEY` 写进 `/home/dev/.ssh/authorized_keys`。sshd 配置在 `/etc/ssh/sshd_config.d/00-dev.conf`（`00-` 前缀保证首次匹配优先语义下的最高优先级）。

**sshd host key 构建时 `ssh-keygen -A` 固化进镜像**（不是运行时生成）。公开镜像 = host key 公开，README 已写明风险；若改回运行时生成，注意 entrypoint 要加回 `ssh-keygen -A`。

### code-server 只监听 127.0.0.1
`--auth none` + `--bind-addr 127.0.0.1:8080`，安全模型完全依赖 SSH 隧道。**不要改成 0.0.0.0 后还保持 auth none**。Dockerfile `EXPOSE 8080` 只是文档意义，运行时无需 `-p 8080`。

### DooD（非 DinD）
容器内装的是 docker CLI + buildx，通过挂载 `/var/run/docker.sock` 调用**宿主机** daemon。dev 用户在 docker 组所以能用。容器内 `docker ps` 看到的是宿主机容器。没有在容器内跑 dockerd。

### zypper 源不稳定 —— 重试循环别删
Leap 16 的 `cdn.opensuse.org` 镜像同步经常 403/404。Dockerfile 里 `sed` 把源切到 `https://download.opensuse.org` + 8 次重试（每次 10s + 重新 refresh）。这是构建能成功的关键，**不要为了"精简"把它删掉**。

### fish / nvim 在构建期完全预配置（非运行时），且都是 dev 用户的
- **nvim**：配置在 `/home/dev/.config/nvim`。克隆 LazyVim starter 去掉 `.git`；Python extra 写进 `lazyvim.json`；构建期 `nvim --headless` 跑 `Lazy! sync` + `MasonInstall pyright ruff`（带 `timeout 900` 和失败回退提示）。
- **fish**：`/home/dev/.config/fish/config.fish`；fisher + autopair.fish + fzf.fish 构建期装好；starship 用 `no-nerd-font` 预设。
- **uv**：装到 `/usr/local/bin`（`UV_INSTALL_DIR`），root 和 dev 共用；系统级包用 `uv pip install --system`。

### openSUSE 的 npm 与 node 是分开的包
`nodejs22` 只含 node 二进制。npm 需单独装 `npm22` + `npm-default`（Mason 装 pyright 需要 npm）。`/usr/bin/npm` 和 `/usr/bin/node` 是 libalternatives 的 ELF 包装器（`alts -l <name>` 查看注册的替代项）。

## 约定

- **fish 配置保持精简**：`fish/config.fish` 只有 PATH / 编辑器变量 / fzf 选项 / starship init。用户明确拒绝过自定义 alias/abbr（"太小众"），不要擅自加。
- 构建出的两个镜像 tag 都带 `:16.0`。
