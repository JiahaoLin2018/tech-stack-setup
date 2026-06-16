#!/usr/bin/env bash
# 通用 Skill 安装脚本
# 将当前目录的所有内容部署到 ~/.claude/skills/<目录名>/
# 此脚本适用于所有 skill，无需修改

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="$(basename "$SRC")"
DST="${HOME}/.claude/skills/${SKILL_NAME}"

mkdir -p "$DST"
cp -r "$SRC"/. "$DST"/

echo "✅ ${SKILL_NAME} installed to ${DST}"
