#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_PKG="${1:?需要 pkg 文件路径}"
TASK_CHECK="$(mktemp -d "$TASK_ROOT/.build/PackageCheck.XXXXXX")"
pkgutil --expand-full "$TASK_PKG" "$TASK_CHECK/expanded"
TASK_INFO="$TASK_CHECK/expanded/PackageInfo"
TASK_APP="$TASK_CHECK/expanded/Payload/归拢.app"
[[ -d "$TASK_APP" ]] || { print -u2 '安装包缺少应用'; exit 1; }
[[ "$(xmllint --xpath 'string(/pkg-info/@install-location)' "$TASK_INFO")" == '/Applications' ]] || { print -u2 '安装位置错误'; exit 1; }
[[ "$(xmllint --xpath 'string(/pkg-info/@relocatable)' "$TASK_INFO")" == 'false' ]] || { print -u2 '安装包不应启用自动重定位'; exit 1; }
[[ "$(xmllint --xpath 'count(/pkg-info/relocate/bundle)' "$TASK_INFO")" == '0' ]] || { print -u2 '安装包不应搜索其他应用副本'; exit 1; }
[[ "$(xmllint --xpath 'count(/pkg-info/bundle)' "$TASK_INFO")" == '1' ]] || { print -u2 '应用版本信息错误'; exit 1; }
[[ "$(xmllint --xpath 'string(/pkg-info/bundle/@path)' "$TASK_INFO")" == './归拢.app' ]] || { print -u2 '应用相对路径错误'; exit 1; }
codesign --verify --deep --strict "$TASK_APP"
lipo "$TASK_APP/Contents/MacOS/ProjectBoard" -verify_arch arm64 x86_64
[[ -f "$TASK_APP/Contents/Resources/AppIcon.icns" ]] || { print -u2 '安装包缺少图标'; exit 1; }
[[ ! -e "$TASK_CHECK/expanded/Payload/归拢资料" ]] || { print -u2 '安装包不能包含个人资料'; exit 1; }
print '安装包检查通过：固定 /Applications、禁用重定位、双架构、签名完整、图标齐全、不含个人资料。'
