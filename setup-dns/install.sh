#!/usr/bin/env bash
# 通用 Skill 安装脚本
# 将当前目录的所有内容部署到 ~/.claude/skills/<目录名>/
# 此脚本适用于所有 skill，无需修改

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="$(basename "$SRC")"
DST="${HOME}/.claude/skills/${SKILL_NAME}"

mkdir -p "$DST"

# 用 rsync --delete 同步：能拉取新文件，也能清理 skill 中已删除的旧文件
# 排除 install.sh 自身（避免脚本运行时改自己）
if command -v rsync > /dev/null 2>&1; then
  rsync -a --delete --exclude='install.sh' "$SRC"/ "$DST"/
  cp "$SRC"/install.sh "$DST"/install.sh
else
  # 退化方案：先清空目标目录再 cp（保证不残留旧文件）
  find "$DST" -mindepth 1 -delete
  cp -r "$SRC"/. "$DST"/
fi

echo "✅ ${SKILL_NAME} installed to ${DST}"
