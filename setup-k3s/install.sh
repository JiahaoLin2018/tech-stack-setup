#!/bin/bash
# setup-k3s 安装脚本
# 用于 Claude Code Skill 安装

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="setup-k3s"
SKILL_DIR="$HOME/.claude/skills/$SKILL_NAME"

echo "=== 安装 $SKILL_NAME Skill ==="

# 创建 Skill 目录
mkdir -p "$SKILL_DIR"

# 复制所有文件
cp -r "$SCRIPT_DIR"/* "$SKILL_DIR/"

# 设置权限
chmod +x "$SKILL_DIR/install.sh" 2>/dev/null || true

echo "✓ $SKILL_NAME 已安装到 $SKILL_DIR"
echo ""
echo "使用方法:"
echo "  /setup-k3s start --host <IP> [--env nonprod|prod]"
echo "  /setup-k3s status --host <IP>"
echo "  /setup-k3s verify --host <IP>"
echo "  /setup-k3s stop --host <IP>"
