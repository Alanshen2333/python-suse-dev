# fish 配置 -- python-suse-dev 镜像
# 预装：fisher + autopair + fzf.fish 插件，starship 提示符

# 关掉默认欢迎语
set -g fish_greeting ""

# PATH：uv、go、用户本地 bin
fish_add_path -g /root/.local/bin /root/go/bin /usr/local/go/bin

# 默认编辑器 / 分页器
set -gx EDITOR nvim
set -gx VISUAL nvim
set -gx PAGER less
set -gx LANG en_US.UTF-8

# fzf.fish 配置
set -g fzf_fd_opts --hidden --exclude=.git

# starship 提示符（配置由 starship preset no-nerd-font 生成）
starship init fish | source
