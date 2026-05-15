# 115Docker - Web 环境中的 115 浏览器客户端
一个基于 LinuxServer WebTop 的 Docker 解决方案，在 Web 环境中运行 115 浏览器客户端，提供便捷的远程访问体验。

推广链接: [https://115.com/u/VDSCVx/1](https://115.com/u/VDSCVx/1)

## 🌟 功能特性

- **Web 访问**: 通过浏览器直接访问 115 客户端，无需安装本地软件
- **增强功能**: 集成 115Cookie 扩展，增强浏览器功能
- **优化配置**: 预配置的浏览器参数，优化性能和稳定性

## 🚀 快速开始

### 构建本地镜像
```bash
git clone https://github.com/dream10201/115Docker.git
cd 115Docker
docker build -t 115docker:unraid .
```

### Docker CLI
```bash
docker run \
--name 115docker \
--security-opt seccomp:unconfined \
-e PUID=99 \
-e PGID=100 \
-e UMASK=000 \
-e DOWNLOAD_PERMISSION_FIX=1 \
-e DOWNLOAD_PERMISSION_FIX_INTERVAL=30 \
-e DOWNLOAD_FILE_MODE=666 \
-e DOWNLOAD_DIR_MODE=777 \
--network=host -d \
-e PASSWORD=123456 \
-e DISPLAY_WIDTH=1920 \
-e DISPLAY_HEIGHT=1080 \
-e COOKIE_CID="xxxxxxxxx" \
-e COOKIE_SEID="xxxxxxxx" \
-e COOKIE_UID="xxxxxxxxx" \
-e COOKIE_KID="xxxxxxxxx" \
-e TZ=Asia/Shanghai \
-e LC_ALL=zh_CN.UTF-8 \
-v /mnt/user/appdata/115docker:/etc/115 \
-v /mnt/user/downloads:/opt/Downloads \
--shm-size 1gb \
--restart unless-stopped \
115docker:unraid
```

### Docker Compose
```bash
docker compose up -d --build
```

### Unraid 权限建议

Unraid 默认共享目录通常使用 `nobody:users`，对应 `PUID=99`、`PGID=100`。本镜像入口脚本会先用 root 完成初始化和权限修复，然后将 noVNC、VNC、桌面和 115 浏览器进程降权到 `PUID:PGID` 运行，避免 `/mnt/user/appdata/115docker` 和下载目录生成 root 文件。

在 Unraid 模板中建议：

| 项目 | 建议值 |
|------|--------|
| `PUID` | `99` |
| `PGID` | `100` |
| `UMASK` | `000` |
| `DOWNLOAD_PERMISSION_FIX` | `1` |
| `DOWNLOAD_PERMISSION_FIX_INTERVAL` | `30` |
| `DOWNLOAD_FILE_MODE` | `666` |
| `DOWNLOAD_DIR_MODE` | `777` |
| `/etc/115` | `/mnt/user/appdata/115docker` |
| `/opt/Downloads` | `/mnt/user/downloads` |

不要额外设置 Docker 的 `--user 99:100`，让入口脚本保留 root 初始化阶段即可；如果强制使用 `--user`，容器仍会尽量运行，但无法自动修复已存在挂载目录的属主。

下载文件权限默认会被修正为 `nobody:users` 可读写的 `rw-rw-rw-`，下载目录会被修正为 `rwxrwxrwx`。如果只想依赖程序自身创建权限，可以设置 `DOWNLOAD_PERMISSION_FIX=0`。

### 访问服务
[http://localhost:1150/vnc.html](http://localhost:1150/vnc.html)

## 📋 详细配置

### 环境变量

| 变量名 | 默认值 | 说明 |
|--------|--------|------|
| `PUID` | 99 | 运行 115 浏览器的用户 ID，Unraid 默认为 99 |
| `PGID` | 100 | 运行 115 浏览器的用户组 ID，Unraid 默认为 100 |
| `UMASK` | 000 | 进程默认创建权限掩码，`000` 通常对应文件 `666`、目录 `777` |
| `DOWNLOAD_PERMISSION_FIX` | 1 | 是否后台修正 `/opt/Downloads` 权限，`1` 开启，`0` 关闭 |
| `DOWNLOAD_PERMISSION_FIX_INTERVAL` | 30 | 下载目录权限修正间隔，单位秒 |
| `DOWNLOAD_FILE_MODE` | 666 | 下载文件修正后的权限 |
| `DOWNLOAD_DIR_MODE` | 777 | 下载目录修正后的权限 |
| `PASSWORD` | "" | WEB VNC密码 |
| `COOKIE_CID` | "" | Cookie | 用于自动登录 |
| `COOKIE_SEID` | "" | Cookie | 用于自动登录 |
| `COOKIE_UID` | "" | Cookie | 用于自动登录 |
| `COOKIE_KID` | "" | Cookie | 用于自动登录 |
| `DISPLAY_WIDTH` | 1366 | 窗口宽度 |
| `DISPLAY_HEIGHT` | 768 | 窗口高度 |

### 数据卷挂载

| 容器路径 | 说明 |
|----------|------|
| `/etc/115` | 115 浏览器用户数据目录，存储登录态、Cookie、浏览器配置、扩展状态等 |
| `/opt/Downloads` | 下载目录 |

## 📄 许可证

本项目采用 [GPL-3.0 许可证](LICENSE)。

## ⚖️ 免责声明

- 本项目仅供学习和研究使用
- 请遵守相关法律法规和服务条款
- 使用本项目产生的任何问题由用户自行承担
- 项目作者不对使用本项目造成的任何损失负责

---

**注意**: 本项目与 115 官方无关，仅为第三方 Docker 化解决方案。使用前请确保遵守 115 服务条款。
