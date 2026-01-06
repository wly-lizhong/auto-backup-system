#!/bin/bash
# ========== 备份系统健康检查 ==========

echo "=== 备份系统状态检查 ==="
echo "检查时间: $(date)"
echo ""

# 1. 本地备份状态
echo "1. 本地备份状态"
LOCAL_DIR="/www/wwwroot/py_backup"
if [ -d "$LOCAL_DIR" ]; then
    backup_count=$(find "$LOCAL_DIR" -maxdepth 1 -type d -name "202*" | wc -l)
    latest=$(find "$LOCAL_DIR" -maxdepth 1 -type d -name "202*" | sort -r | head -1)
    
    echo "   备份目录: $LOCAL_DIR"
    echo "   备份数量: $backup_count 个"
    if [ -n "$latest" ]; then
        latest_name=$(basename "$latest")
        size=$(du -sh "$latest" 2>/dev/null | cut -f1 || echo "未知")
        echo "   最新备份: $latest_name ($size)"
    fi
else
    echo "   ❌ 本地备份目录不存在"
fi

# 2. Gitee同步状态
echo ""
echo "2. Gitee同步状态"
echo "   仓库地址: https://gitee.com/xxxxxx"
echo "   SSH连接测试:"
if ssh -T git@gitee-backup 2>&1 | grep -q "successfully"; then
    echo "   ✅ SSH连接正常"
else
    echo "   ❌ SSH连接失败"
fi

# 3. 同步日志状态
echo ""
echo "3. 同步日志状态"
LOG_FILE="/www/wwwlogs/sync_to_a-server.log"
if [ -f "$LOG_FILE" ]; then
    last_sync=$(grep "同步成功完成" "$LOG_FILE" | tail -1 | cut -d'[' -f2 | cut -d']' -f1 2>/dev/null || echo "无记录")
    echo "   最后成功: $last_sync"
    
    if [ "$last_sync" != "无记录" ]; then
        # 检查是否在24小时内
        if [[ "$last_sync" > "$(date -d '24 hours ago' '+%Y-%m-%d %H:%M:%S')" ]]; then
            echo "   状态: ✅ 同步正常"
        else
            echo "   状态: ⚠️  最近24小时无成功同步"
        fi
    fi
else
    echo "   日志文件不存在"
fi

# 4. 磁盘空间
echo ""
echo "4. 磁盘空间"
df -h /www /tmp | grep -v "Filesystem" | while read line; do
    echo "   $line"
done

echo ""
echo "=== 检查完成 ==="
echo ""
echo "📋 操作命令:"
echo "1. 手动同步: cd /www/wwwroot/py_backup && bash sync_to_a-server.sh"
echo "2. 查看日志: tail -f /www/wwwlogs/sync_to_a-server.log"
echo "3. 检查仓库: https://gitee.comxxxxxxx"
