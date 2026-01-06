# 备份同步信息

## 同步概要
- 同步时间: Tue Jan  6 10:58:05 AM CST 2026
- 本地目录: /www/wwwroot/py_backup
- 备份数量: 1
- 最新备份: 2026-01-05

## 本地备份结构
```
.
./2026-01-05
./.git
./.git/branches
./.git/hooks
./.git/info
./.git/logs
./.git/objects
./.git/refs
```

## 恢复指南
1. 下载所需日期的备份目录
2. 合并分卷: cat *.part.* > backup.tar.gz
3. 解压: tar -xzf backup.tar.gz
