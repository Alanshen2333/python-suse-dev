# python-suse-dev

基于 openSUSE Leap 16.0 的 Python 开发容器镜像。开箱即用：Python 3.13 + uv + 网络调试工具 + docker CLI (DooD) + fish/nvim 全套预配置 + sshd（仅密钥登录）。

## 镜像

| 镜像 | 说明 | 端口 |
|------|------|------|
| `ghcr.io/alanshen2333/python-suse-dev:16.0` | base：全套开发环境 | 22 (SSH) |
| `ghcr.io/alanshen2333/python-suse-dev-code:16.0` | base + code-server Web IDE | 22 (SSH), 8080 |

多架构：`linux/amd64` + `linux/arm64`。

## 快速开始

```bash
# 拉取
docker pull ghcr.io/alanshen2333/python-suse-dev:16.0

# 运行（注入你的 SSH 公钥）
docker run -d --name psd \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -p 2222:22 \
  -e SSH_PUBKEY="$(cat ~/.ssh/id_ed25519.pub)" \
  ghcr.io/alanshen2333/python-suse-dev:16.0

# SSH 登录（dev 用户，fish shell，无密码纯密钥）
ssh -p 2222 dev@localhost
```

不传 `SSH_PUBKEY` 则无法 SSH，只能 `docker exec` 进容器。

## code 镜像（Web IDE）

code-server 只监听 `127.0.0.1:8080` 且无密码，**必须经 SSH 隧道访问**：

```bash
docker run -d --name psd-code \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -p 2222:22 \
  -e SSH_PUBKEY="$(cat ~/.ssh/id_ed25519.pub)" \
  ghcr.io/alanshen2333/python-suse-dev-code:16.0

# 建隧道后浏览器打开 http://localhost:8080
ssh -p 2222 -L 8080:127.0.0.1:8080 dev@localhost
```

## 预装内容

- **Python**：3.13（`python`/`python3` 均指向 3.13）+ uv（`/usr/local/bin`）
- **Python 库**（系统级）：requests httpx aiohttp websockets fastapi uvicorn flask pytest rich
- **网络工具**：curl wget httpie bind-utils(dig) iputils(ping) netcat tcpdump socat telnet traceroute
- **开发工具**：git vim neovim(LazyVim + pyright/ruff 预装) jq rsync ripgrep fd fzf tree starship
- **Node**：nodejs22 + npm（供 Mason 装 LSP 用）
- **docker CLI + buildx**：DooD 模式，见下方警告
- **fish**：fisher + autopair + fzf.fish 插件，starship no-nerd-font 预设

工作目录 `/workspace`（dev 用户所有）。日常用 `uv` 管 Python 项目。

## ⚠️ DooD 安全警告

挂载 `/var/run/docker.sock` 等于把宿主机 root 权限交给容器 —— 容器内 `docker` 命令操作的是**宿主机** daemon。**仅限本地开发使用**，不要在不可信环境这样跑。不需要 docker 的话去掉该挂载即可。

## 其他用法

```bash
# 进运行中的容器调试
docker exec -it psd fish

# 交互式一次性使用（直接进 fish）
docker run -it --rm ghcr.io/alanshen2333/python-suse-dev:16.0

# 执行单条命令
docker run --rm ghcr.io/alanshen2333/python-suse-dev:16.0 python --version
```

## 本地构建

```bash
docker build -t python-suse-dev:16.0 .                          # base
docker build --target code -t python-suse-dev-code:16.0 .       # code
```

## CI

GitHub Actions 每天 nightly（北京时间约 02:17）+ 手动触发 + main 分支相关文件变更时自动构建推送 GHCR，多架构。

## 注意

- 镜像内固化了 sshd host key。公开镜像意味着 host key 指纹公开，理论上可被用于 MITM 伪造该镜像的 SSH 服务 —— 对个人开发镜像影响有限，介意的话本地构建自用。
- root 登录已禁用（`PermitRootLogin no`），固定使用 `dev` 用户（UID 1000）。
