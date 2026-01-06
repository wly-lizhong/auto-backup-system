#!/bin/bash
# ========== Gitee云端镜像同步脚本 ==========
# 功能：将本地备份目录 /www/wwwroot/py_backup/ 完整镜像到Gitee私有仓库
# 特点：增量同步、智能重试、完整日志

# 配置区（请根据实际情况修改）
LOCAL_BACKUP_DIR="/www/wwwroot/py_backup"       # 本地备份根目录
GITEE_REPO="git@gitee-backup:wly-lizhong/a-server-backup-prod.git"  # Gitee仓库地址
SYNC_LOG="/www/wwwroot/py_backup/gitee_sync_backup.log"   # 同步日志
MAX_RETRIES=3                                    # 最大重试次数
RETRY_DELAY=30                                   # 重试间隔（秒）
KEEP_DAYS_ON_GITEE=30                            # Gitee保留天数（与本地一致）

echo "========== Gitee云端同步开始 [$(date '+%Y-%m-%d %H:%M:%S')] ==========" >> "$SYNC_LOG"

# 1. 环境检查
echo "[1/7] 环境检查..." >> "$SYNC_LOG"

# 检查本地备份目录
if [ ! -d "$LOCAL_BACKUP_DIR" ]; then
    echo "❌ 错误：本地备份目录不存在: $LOCAL_BACKUP_DIR" >> "$SYNC_LOG"
    exit 1
fi

# 检查SSH连接
echo "  测试SSH连接..." >> "$SYNC_LOG"
if ! ssh -o ConnectTimeout=10 -T git@gitee-backup 2>/dev/null | grep -q "successfully authenticated"; then
    echo "  ⚠️  SSH连接测试失败，尝试继续..." >> "$SYNC_LOG"
fi

# 2. 准备Git工作区
echo "[2/7] 准备Git工作区..." >> "$SYNC_LOG"
WORK_DIR="/tmp/gitee_sync_$(date +%Y%m%d_%H%M%S)"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

# 初始化Git仓库
git init >> "$SYNC_LOG" 2>&1
git config user.email "backup-sync@server.com"
git config user.name "Backup Sync"
git config core.compression 0                    # 禁用压缩（分卷文件已压缩）
git config http.postBuffer 52428800              # 50MB缓冲区

# 3. 复制本地备份到工作区
echo "[3/7] 复制本地备份文件..." >> "$SYNC_LOG"
cp -r "$LOCAL_BACKUP_DIR"/* . 2>/dev/null

# 检查文件数量
file_count=$(find . -type f | wc -l)
dir_count=$(find . -type d | wc -l)
total_size=$(du -sh . | cut -f1)

if [ "$file_count" -eq 0 ]; then
    echo "❌ 错误：未找到任何备份文件" >> "$SYNC_LOG"
    exit 1
fi

echo "  文件统计: $file_count 个文件, $dir_count 个目录, 总大小: $total_size" >> "$SYNC_LOG"

# 4. 生成同步信息文件
echo "[4/7] 生成同步元数据..." >> "$SYNC_LOG"
cat > SYNC_INFO.md << EOF
# 备份云端镜像同步信息

## 同步概要
- **同步时间**: $(date)
- **本地目录**: $LOCAL_BACKUP_DIR
- **文件总数**: $file_count
- **目录总数**: $dir_count
- **总大小**: $total_size
- **Gitee仓库**: $GITEE_REPO

## 目录结构
\`\`\`
$(find . -maxdepth 3 -type d | sort | sed 's|^\./||' | head -50)
\`\`\`

## 恢复指南
1. 从Gitee下载整个仓库或特定日期目录
2. 分卷文件合并命令：
   \`\`\`bash
   # 进入日期目录
   cd YYYY-MM-DD
   
   # 合并所有分卷
   cat backup_*.tar.gz.part.* > combined_backup.tar.gz
   
   # 验证完整性
   gzip -t combined_backup.tar.gz
   
   # 解压到当前目录
   tar -xzf combined_backup.tar.gz
   \`\`\`

3. 使用rsync恢复生产环境：
   \`\`\`bash
   rsync -av --delete restored_files/ /www/wwwroot/py/
   \`\`\`

## 同步策略
- 每日凌晨自动同步
- 云端保留最近 $KEEP_DAYS_ON_GITEE 天备份
- 自动清理过期备份
- 增量同步，仅传输变化文件

## 最后同步
$(date) - 同步完成
EOF

# 5. 设置远程仓库并同步
echo "[5/7] 设置远程仓库..." >> "$SYNC_LOG"
git remote add origin "$GITEE_REPO" >> "$SYNC_LOG" 2>&1

# 检测远程分支
echo "  检测远程分支..." >> "$SYNC_LOG"
if git ls-remote --exit-code origin main &>/dev/null; then
    BRANCH="main"
    echo "  使用分支: main" >> "$SYNC_LOG"
elif git ls-remote --exit-code origin master &>/dev/null; then
    BRANCH="master"
    echo "  使用分支: master" >> "$SYNC_LOG"
else
    BRANCH="main"
    echo "  远程无分支，将创建: $BRANCH" >> "$SYNC_LOG"
fi

# 拉取远程最新状态（如果存在）
if git ls-remote --exit-code origin "$BRANCH" &>/dev/null; then
    echo "  拉取远程最新内容..." >> "$SYNC_LOG"
    git pull origin "$BRANCH" --allow-unrelated-histories --strategy=recursive -X theirs >> "$SYNC_LOG" 2>&1 || \
        echo "  首次拉取可能失败，继续..." >> "$SYNC_LOG"
fi

git checkout -b "$BRANCH" >> "$SYNC_LOG" 2>&1

# 6. 智能添加和提交
echo "[6/7] 添加文件并提交..." >> "$SYNC_LOG"

# 先清理过期备份（保持与本地一致）
echo "  清理云端过期备份..." >> "$SYNC_LOG"
CUTOFF_DATE=$(date -d "$KEEP_DAYS_ON_GITEE days ago" +%Y-%m-%d 2>/dev/null || date -v-"$KEEP_DAYS_ON_GITEE"d +%Y-%m-%d)

for old_dir in */; do
    dir_name=$(basename "$old_dir")
    if [[ "$dir_name" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [[ "$dir_name" < "$CUTOFF_DATE" ]]; then
        echo "    删除过期备份: $dir_name" >> "$SYNC_LOG"
        rm -rf "$old_dir"
    fi
done

# 添加所有文件（Git会自动检测变化）
git add -A . >> "$SYNC_LOG" 2>&1

# 检查是否有变化
if git diff --cached --quiet; then
    echo "  无变化，跳过提交" >> "$SYNC_LOG"
    # 创建空提交以记录同步时间
    git commit --allow-empty -m "云端同步检查: $(date '+%Y-%m-%d %H:%M:%S') - 无新备份" >> "$SYNC_LOG" 2>&1
else
    # 获取变化统计
    added_files=$(git diff --cached --name-status | grep -c '^[A]')
    modified_files=$(git diff --cached --name-status | grep -c '^[M]')
    deleted_files=$(git diff --cached --name-status | grep -c '^[D]')
    
    echo "  检测到变化: +${added_files} 新, ~${modified_files} 修改, -${deleted_files} 删除" >> "$SYNC_LOG"
    
    git commit -m "云端镜像同步: $(date '+%Y-%m-%d %H:%M:%S')

同步统计:
- 新增备份: ${added_files} 个
- 修改文件: ${modified_files} 个  
- 删除备份: ${deleted_files} 个
- 总文件数: ${file_count}
- 总大小: ${total_size}

包含备份日期:
$(find . -maxdepth 1 -type d -name "202*" | sort -r | head -5 | sed 's|^\./||' | xargs -I {} echo "  - {}")

同步策略:
- 保留最近 ${KEEP_DAYS_ON_GITEE} 天备份
- 自动清理过期数据
- 增量同步，节省流量
" >> "$SYNC_LOG" 2>&1
fi

# 7. 推送到Gitee（带智能重试和详细错误分析）
echo "[7/7] 推送到Gitee仓库..." >> "$SYNC_LOG"

push_success=false
for attempt in $(seq 1 $MAX_RETRIES); do
    echo "  推送尝试 ($attempt/$MAX_RETRIES)..." >> "$SYNC_LOG"
    
    # 显示推送进度并捕获错误
    push_output=$(git push -f origin "$BRANCH" --progress 2>&1)
    echo "$push_output" >> "$SYNC_LOG"
    
    # 分析推送结果
    if echo "$push_output" | grep -q "Writing objects\|Everything up-to-date"; then
        push_success=true
        echo "  ✅ 推送成功！" >> "$SYNC_LOG"
        break
    else
        # 详细错误分析
        echo "  ⚠️  推送失败，分析错误..." >> "$SYNC_LOG"
        
        if echo "$push_output" | grep -q "repository not found"; then
            echo "   错误：仓库不存在或地址错误" >> "$SYNC_LOG"
            echo "   请检查: https://gitee.com/wly-lizhong/a-server-backup-prod" >> "$SYNC_LOG"
        elif echo "$push_output" | grep -q "Permission denied"; then
            echo "   错误：权限被拒绝" >> "$SYNC_LOG"
            echo "   请确认：1. 仓库是否私有 2. 是否有推送权限" >> "$SYNC_LOG"
        elif echo "$push_output" | grep -q "remote rejected"; then
            echo "   错误：远程拒绝推送" >> "$SYNC_LOG"
            echo "   可能原因：分支保护、强制推送限制等" >> "$SYNC_LOG"
        else
            echo "   未知错误，原错误信息:" >> "$SYNC_LOG"
            echo "   $push_output" >> "$SYNC_LOG" | tail -5
        fi
        
        if [ $attempt -lt $MAX_RETRIES ]; then
            echo "  等待 ${RETRY_DELAY}秒后重试..." >> "$SYNC_LOG"
            sleep $RETRY_DELAY
        else
            echo "  已达到最大重试次数" >> "$SYNC_LOG"
        fi
    fi
done

# 8. 同步结果报告
echo "========== 同步结果 ==========" >> "$SYNC_LOG"
if $push_success; then
    echo "✅ 云端镜像同步成功！" >> "$SYNC_LOG"
    echo "   同步时间: $(date)" >> "$SYNC_LOG"
    echo "   总文件数: $file_count" >> "$SYNC_LOG"
    echo "   总大小: $total_size" >> "$SYNC_LOG"
    echo "   Gitee分支: $BRANCH" >> "$SYNC_LOG"
    echo "   仓库地址: https://gitee.com/wly-lizhong/a-server-backup-prod" >> "$SYNC_LOG"
    
    # 显示最新的备份日期
    latest_backup=$(find . -maxdepth 1 -type d -name "202*" | sort -r | head -1 | sed 's|^\./||')
    if [ -n "$latest_backup" ]; then
        echo "   最新备份: $latest_backup" >> "$SYNC_LOG"
    fi
    
    # 云端备份统计
    echo "   云端备份日期:" >> "$SYNC_LOG"
    find . -maxdepth 1 -type d -name "202*" | sort -r | head -5 | sed 's|^\./||' | xargs -I {} echo "     - {}" >> "$SYNC_LOG"
    
    # 计算已用空间
    echo "   🗂️ 云端仓库建议：定期检查使用量，确保不超过500MB限制" >> "$SYNC_LOG"
else
    echo "❌ 云端同步失败！" >> "$SYNC_LOG"
    echo "   本地备份文件保留在: $LOCAL_BACKUP_DIR" >> "$SYNC_LOG"
    echo "   工作目录: $WORK_DIR" >> "$SYNC_LOG"
    echo "   请检查:" >> "$SYNC_LOG"
    echo "   1. SSH密钥配置 (ssh -T git@gitee-backup)" >> "$SYNC_LOG"
    echo "   2. 仓库地址权限" >> "$SYNC_LOG"
    echo "   3. 网络连接" >> "$SYNC_LOG"
fi

# 9. 清理工作区
echo "清理工作区..." >> "$SYNC_LOG"
rm -rf "$WORK_DIR"
echo "  已清理: $WORK_DIR" >> "$SYNC_LOG"

echo "========== Gitee云端同步结束 [$(date '+%Y-%m-%d %H:%M:%S')] ==========" >> "$SYNC_LOG"
echo "" >> "$SYNC_LOG"