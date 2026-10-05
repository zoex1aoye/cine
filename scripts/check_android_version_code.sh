#!/usr/bin/env bash
# 发版门禁：pubspec.yaml 的 +versionCode 必须严格大于所有已发布 v* tag。
# 指向当前 HEAD 的 tag 不算“已发布”，避免正在打的 tag 和自己比较。
set -euo pipefail

root=$(git rev-parse --show-toplevel)
cd "$root"

line=$(awk '/^version:/ { print $2; exit }' pubspec.yaml)
if [[ "$line" != *"+"* ]]; then
  echo "pubspec.yaml version 必须写成 名称+整数，例如 1.0.10+8。当前：${line:-<空>}"
  exit 1
fi
current=${line##*+}
if ! [[ "$current" =~ ^[0-9]+$ ]]; then
  echo "versionCode 必须是整数。当前：+$current"
  exit 1
fi

head_sha=$(git rev-parse HEAD)
max=0
max_tag=""
found=0
while IFS= read -r tag; do
  [ -z "$tag" ] && continue
  tag_sha=$(git rev-parse "$tag^{commit}")
  if [ "$tag_sha" = "$head_sha" ]; then
    continue
  fi
  prev=$(git show "$tag:pubspec.yaml" 2>/dev/null | awk '/^version:/ { print $2; exit }' || true)
  if [[ "$prev" != *"+"* ]]; then
    continue
  fi
  code=${prev##*+}
  if [[ "$code" =~ ^[0-9]+$ ]]; then
    found=1
    if [ "$code" -gt "$max" ]; then
      max=$code
      max_tag=$tag
    fi
  fi
done < <(git tag --list 'v*')

if [ "$found" -eq 1 ] && [ "$current" -le "$max" ]; then
  echo "versionCode 必须大于已有 v* tag。当前 +${current}，最高是 ${max_tag} 的 +${max}。只改版本名（+ 前面）不能覆盖安装。"
  exit 1
fi

echo "versionCode +$current 可以通过发版（已有 tag 最高 +$max${max_tag:+，$max_tag}）。"
