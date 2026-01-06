#!/bin/bash

# 配置变量
DATE=$(date +%Y-%m-%d)
BACKUP_DIR="/www/wwwroot/py_backup"                  # 主备份目录
DATE_DIR="$BACKUP_DIR/$DATE"                         # 按日期子目录
TEMP_DIR="/tmp/prod-backup-$DATE"                     # 临时工作目录
TAR_FILE="$DATE_DIR/prod-backup-$DATE.tar.gz"        # 临时完整压缩包路径
PART_PREFIX="$DATE_DIR/prod-backup-$DATE.tar.gz.part-"  # 分卷前缀
EXCLUDES="--exclude='*.log' --exclude='*.tmp' --exclude='__pycache__' --exclude='*.pyc'"

# 创建必要目录
mkdir -p "$DATE_DIR"
mkdir -p "$TEMP_DIR"

# 复制ocrmask指定文件夹
rsync -a $EXCLUDES /www/wwwroot/py/ocrmask/medic_2pdf3_cs/ "$TEMP_DIR/medic_2pdf3_cs/"
rsync -a $EXCLUDES /www/wwwroot/py/ocrmask/medic_2pdf3_zs/ "$TEMP_DIR/medic_2pdf3_zs/"

# 复制RAG目录（带特定排除）
rsync -a $EXCLUDES \
    --exclude='.git/' --exclude='.cache/' --exclude='templates/' --exclude='rag-venv/' \
    /www/wwwroot/py/RAG/pd0.1/ "$TEMP_DIR/pd0.1/"

# 添加备份元数据（压缩包内）
cat << EOF > "$TEMP_DIR/README.md"
# 生产环境备份快照

备份日期: $DATE
备份存储路径: 分卷文件（prod-backup-$DATE.tar.gz.part-*）

### 备份范围
1. /www/wwwroot/py/ocrmask/medic_2pdf3_cs/ （全部内容）
2. /www/wwwroot/py/ocrmask/medic_2pdf3_zs/ （全部内容）
3. /www/wwwroot/py/RAG/pd0.1/ （排除 .git/、.cache/、templates/、rag-venv/ 以及所有临时文件）

### 恢复指南
1. 合并分卷（如果有多个）：
   cat prod-backup-$DATE.tar.gz.part-* > prod-backup-$DATE.tar.gz

2. 解压压缩包：
   tar -xzvf prod-backup-$DATE.tar.gz -C /tmp/recover

3. 使用rsync同步回生产目录：
   rsync -a /tmp/recover/medic_2pdf3_cs/ /www/wwwroot/py/ocrmask/medic_2pdf3_cs/
   rsync -a /tmp/recover/medic_2pdf3_zs/ /www/wwwroot/py/ocrmask/medic_2pdf3_zs/
   rsync -a /tmp/recover/pd0.1/ /www/wwwroot/py/RAG/pd0.1/

4. 检查并修复权限：
   chown -R www:www /www/wwwroot/py/ocrmask/
   chown -R www:www /www/wwwroot/py/RAG/pd0.1/

5. 重启相关服务。

注意：恢复前请备份当前生产目录。
EOF

# 生成文件列表
find "$TEMP_DIR" -type f | sed "s|$TEMP_DIR/||g" | sort > "$TEMP_DIR/filelist.txt"

# 压缩整个临时目录到日期目录
tar -czf "$TAR_FILE" -C /tmp "prod-backup-$DATE"

# 检查压缩是否成功
if [ ! -f "$TAR_FILE" ]; then
    echo "错误：压缩失败，$TAR_FILE 未生成！请检查源目录内容和权限。"
    rm -rf "$TEMP_DIR"
    exit 1
fi

# 分卷（每个45MB，安全低于Gitee 50MB限制）
split -b 45M "$TAR_FILE" "$PART_PREFIX"

# 删除原单大文件（只保留分卷）
rm "$TAR_FILE"

# 在日期目录添加外部README（含合并命令，便于直接查看）
cat << EOF > "$DATE_DIR/README.md"
# 生产备份分卷文件（$DATE）

此目录包含当日备份分卷：
- 分卷文件：prod-backup-$DATE.tar.gz.part-*
- 总大小约：$(du -ch "$PART_PREFIX"* 2>/dev/null | tail -1 | cut -f1)

合并命令：
cat prod-backup-$DATE.tar.gz.part-* > prod-backup-$DATE.tar.gz

然后解压并按压缩包内 README.md 恢复。
EOF

# 清理临时目录
rm -rf "$TEMP_DIR"

# 自动清理30天前旧备份
find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} \; 2>/dev/null

# 输出信息
echo "备份分卷完成：$PART_PREFIX*"
echo "分卷总大小: $(du -ch "$PART_PREFIX"* 2>/dev/null | tail -1 | cut -f1)"
echo "旧备份清理完毕（保留最近30天）"