#!/bin/bash
# ========== 专用同步脚本：同步到 a-server 仓库 ==========

# 配置区
LOCAL_BACKUP_DIR="/www/wwwroot/py_backup"
GITEE_REPO="git@gitee-backup:xxxxxxx.git"  # 已验证的仓库
LOG_FILE="/www/wwwlogs/sync_to_a-server.log"
MAX_RETRIES=3
RETRY_DELAY=15

echo "========== 同步到 a-server 仓库 [$(date '+%Y-%m-%d %H:%M:%S')] ==========" >> "$LOG_FILE"

# 1. 检查本地备份
echo "[1/6] 检查本地备份..." >> "$LOG_FILE"
if [ ! -d "$LOCAL_BACKUP_DIR" ]; then
    echo "❌ 错误：本地备份目录不存在" >> "$LOG_FILE"
    exit 1
fi

# 统计本地备份
recent_backups=$(find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type d -name "202*" | wc -l)
latest_backup=$(find "$LOCAL_BACKUP_DIR" -maxdepth 1 -type d -name "202*" | sort -r | head -1)
echo "  本地备份数: $recent_backups" >> "$LOG_FILE"
if [ -n "$latest_backup" ]; then
    echo "  最新备份: $(basename "$latest_backup")" >> "$LOG_FILE"
fi

# 2. 进入备份目录
cd "$LOCAL_BACKUP_DIR" || {
    echo "❌ 无法进入备份目录" >> "$LOG_FILE"
    exit 1
}

# 3. 初始化或更新Git仓库
echo "[2/6] 初始化Git仓库..." >> "$LOG_FILE"
if [ ! -d ".git" ]; then
    git init >> "$LOG_FILE" 2>&1
    git config user.email "backup@server.com"
    git config user.name "Server Backup"
    git remote add origin "$GITEE_REPO" >> "$LOG_FILE" 2>&1
    echo "  Git仓库已初始化" >> "$LOG_FILE"
fi

# 4. 检查远程分支
echo "[3/6] 检查远程分支..." >> "$LOG_FILE"
git remote set-url origin "$GITEE_REPO" >> "$LOG_FILE" 2>&1

# 检测远程分支
if git ls-remote --exit-code origin main &>/dev/null; then
    BRANCH="main"
elif git ls-remote --exit-code origin master &>/dev/null; then
    BRANCH="master"
else
    BRANCH="main"
    echo "  警告：远程无分支，将创建 $BRANCH" >> "$LOG_FILE"
fi

git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH" 2>/dev/null
echo "  使用分支: $BRANCH" >> "$LOG_FILE"

# 5. 拉取最新更改
echo "[4/6] 同步远程更改..." >> "$LOG_FILE"
git fetch origin >> "$LOG_FILE" 2>&1
git merge --ff-only "origin/$BRANCH" 2>> "$LOG_FILE" || \
    git reset --hard "origin/$BRANCH" 2>> "$LOG_FILE"

# 6. 添加并提交本地备份
echo "[5/6] 添加并提交本地备份..." >> "$LOG_FILE"

# 创建备份信息文件
cat > BACKUP_INFO.md << INFO
# 备份同步信息

## 同步概要
- 同步时间: $(date)
- 本地目录: $LOCAL_BACKUP_DIR
- 备份数量: $recent_backups
- 最新备份: $(basename "$latest_backup" 2>/dev/null || echo "无")

## 本地备份结构
\`\`\`
$(find . -maxdepth 2 -type d | sort | head -20)
\`\`\`

## 恢复指南
1. 下载所需日期的备份目录
2. 合并分卷: cat *.part.* > backup.tar.gz
3. 解压: tar -xzf backup.tar.gz
INFO

# 添加所有文件
git add -A . >> "$LOG_FILE" 2>&1

# 检查是否有变更
if git diff --cached --quiet; then
    echo "  无新变更，跳过提交" >> "$LOG_FILE"
else
    changed_files=$(git diff --cached --name-only | wc -l)
    git commit -m "备份同步: $(date '+%Y-%m-%d %H:%M:%S')

同步统计:
- 变更文件: $changed_files 个
- 本地备份: $recent_backups 个目录
- 最新备份: $(basename "$latest_backup" 2>/dev/null || echo "无")

同步时间: $(date)
" >> "$LOG_FILE" 2>&1
    
    echo "  已提交 $changed_files 个变更" >> "$LOG_FILE"
fi

# 7. 推送到远程
echo "[6/6] 推送到远程仓库..." >> "$LOG_FILE"
push_success=false

for attempt in $(seq 1 $MAX_RETRIES); do
    echo "  推送尝试 $attempt/$MAX_RETRIES..." >> "$LOG_FILE"
    
    if git push origin "$BRANCH" 2>&1 | tee -a "$LOG_FILE" | grep -q "Writing objects\|Everything up-to-date"; then
        push_success=true
        echo "  ✅ 推送成功！" >> "$LOG_FILE"
        break
    else
        echo "  ⚠️  推送失败，等待 ${RETRY_DELAY}秒后重试..." >> "$LOG_FILE"
        sleep $RETRY_DELAY
    fi
done

# 8. 结果报告
if $push_success; then
    echo "✅ 同步成功完成！" >> "$LOG_FILE"
    echo "   同步时间: $(date)" >> "$LOG_FILE"
    echo "   同步到: https://gitee.com/xxxxxxr" >> "$LOG_FILE"
    echo "   分支: $BRANCH" >> "$LOG_FILE"
    echo "   本地备份数: $recent_backups" >> "$LOG_FILE"
else
    echo "❌ 同步失败！" >> "$LOG_FILE"
    echo "   本地备份仍保留在: $LOCAL_BACKUP_DIR" >> "$LOG_FILE"
fi

echo "========== 同步结束 [$(date '+%Y-%m-%d %H:%M:%S')] ==========" >> "$LOG_FILE"
echo "" >> "$LOG_FILE"
