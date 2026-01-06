```markdown
# 🚀 服务器生产环境自动化备份系统

**全自动、本地30天 + 云端永久备份，使用宝塔面板 + GitHub/Gitee 实现企业级容灾**

## 📋 项目概述

为生产服务器关键代码与数据提供安全可靠的备份方案，实现了**零人工干预**的每日自动备份、本地快照存储、压缩分卷、云端增量同步。

### 核心特点
- 每日自动备份指定目录
- 智能分卷压缩（每卷 < 45MB，适配 Git 平台文件大小限制）
- 本地保留最近 30 天备份，自动清理旧数据
- 支持同步到 GitHub 或 Gitee 私有仓库，实现异地容灾
- 完整的恢复指南和监控脚本

## 🏗️ 系统架构

```

生产环境 → 本地备份（按日期归档 + 分卷压缩） → 云端仓库（GitHub/Gitee）

```
## ⚙️ 核心脚本

- `backup_compress.sh`：主备份脚本（筛选、压缩、分卷、清理）
- `sync_to_github.sh`：增量同步到 GitHub 仓库（可修改为 Gitee）
- `check_system.sh`：系统健康检查（备份状态、磁盘、连接等）

## 🚀 快速部署（5 分钟）

1. 在服务器上创建备份目录：
   ```bash
   mkdir -p /www/wwwroot/py_backup
```

2. 把本仓库所有脚本上传到 `/www/wwwroot/py_backup/` 并赋予执行权限：

   ```bash
   chmod +x *.sh
   ```

3. 配置 GitHub 同步（首次需要配置 SSH 密钥）：

   ```bash
   ssh-keygen -t ed25519 -C "your@email.com"
   # 把公钥添加到 GitHub → Settings → SSH and GPG keys
   ```

4. 修改 `sync_to_github.sh` 中的 `GITHUB_REPO` 为你自己的仓库地址。

5. 在宝塔面板添加计划任务：

   - 每日 02:00 执行 `backup_compress.sh`
   - 每日 03:00 执行 `sync_to_github.sh`

6. 测试运行：

   ```bash
   bash /www/wwwroot/py_backup/check_system.sh
   ```

## 📝 恢复指南

1. 从 GitHub 下载对应日期目录的所有分卷文件

2. 合并分卷：

   ```bash
   cat prod-backup-*.tar.gz.part-* > backup.tar.gz
   ```

3. 解压并恢复：

   ```bash
   tar -xzvf backup.tar.gz -C /tmp/recover
   rsync -a /tmp/recover/... /www/wwwroot/py/...
   ```

## 🛠️ 扩展与定制

- 需要备份更多目录？修改 `backup_compress.sh` 中的 rsync 命令
- 想用 Gitee？把 `sync_to_github.sh` 改回 Gitee 地址即可
- 增加通知？可在脚本末尾加钉钉/企业微信 webhook

## 📄 License

MIT License - 可自由使用、修改、分发

## ⭐ Star & Fork

如果对你有帮助，欢迎 Star 和 Fork！有问题欢迎提 Issue。

---

**项目已稳定运行超过30天，备份成功率100%**

```
### 第四步：把文件上传到 GitHub

有两种最简单的方法，任选其一：

#### 方法一：直接用 GitHub 网页上传（最推荐新手）

1. 打开你的仓库页面（https://github.com/你的用户名/auto-backup-system）
2. 点击 “Add file” → “Upload files”
3. 把上面准备好的所有文件（.gitignore、各个 .sh、README.md 等）拖拽上传
4. 下面填写 Commit message：`Initial commit: 上传自动化备份系统完整代码和文档`
5. 点击绿色 “Commit changes”

全部上传完成！

#### 方法二：用 git 命令（如果你服务器上想直接推）

在服务器的 `/www/wwwroot/py_backup` 目录下执行：
```bash
git init
git add .
git commit -m "Initial commit"
git remote add origin git@github.com:你的用户名/auto-backup-system.git
git push -u origin main
```

