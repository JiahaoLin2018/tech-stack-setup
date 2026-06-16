#!/usr/bin/env bash
# 通用 Skill 安装脚本
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="$(basename "$SRC")"
DST="${HOME}/.claude/skills/${SKILL_NAME}"

mkdir -p "$DST"
cp -r "$SRC"/. "$DST"/
echo "✅ ${SKILL_NAME} installed to ${DST}"
