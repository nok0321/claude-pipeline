#!/usr/bin/env bash
# SessionStart: プロジェクト種別を自動検出しコンテキストを注入

# Claude Code の Hook は最小 PATH で起動される場合がある
# scoop / cargo / ~/.local/bin 等のユーザー環境を PATH に追加
for d in "$HOME/scoop/shims" "$HOME/.cargo/bin" "$HOME/.local/bin" "/usr/local/bin"; do
  [ -d "$d" ] && [[ ":$PATH:" != *":$d:"* ]] && PATH="$d:$PATH"
done
export PATH

cd "${CLAUDE_PROJECT_DIR:-$(pwd)}" 2>/dev/null || exit 0

context=""

# CHECKPOINT.md の確認
if [ -f "CHECKPOINT.md" ]; then
  context="[CHECKPOINT.md あり — /checkpoint restore で復元可能]\n"
fi

# Git 状態
if git rev-parse --is-inside-work-tree &>/dev/null; then
  branch=$(git branch --show-current 2>/dev/null || echo "detached")
  uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  context="${context}Branch: ${branch} | Uncommitted: ${uncommitted} file(s)"
else
  context="${context}[Git 未初期化]"
fi

# --- ツールチェーン自動検出 ---

# Rust
if [ -f "Cargo.toml" ]; then
  if command -v rustc &>/dev/null; then
    rust_ver=$(rustc --version 2>/dev/null | awk '{print $2}')
    context="${context} | Rust: ${rust_ver}"
  else
    context="${context} | [WARNING] Cargo.toml あり / rustc 未検出"
  fi
  # wasm-pack (Cargo.tomlにwasm-bindgenがあれば表示)
  if grep -q 'wasm-bindgen' Cargo.toml */Cargo.toml **/Cargo.toml 2>/dev/null; then
    if command -v wasm-pack &>/dev/null; then
      wasm_ver=$(wasm-pack --version 2>/dev/null | awk '{print $2}')
      context="${context} | wasm-pack: ${wasm_ver}"
    else
      context="${context} | [INFO] wasm-pack 未検出"
    fi
  fi
fi

# Node.js
if [ -f "package.json" ] || [ -d "frontend" ] || [ -d "client" ]; then
  if command -v node &>/dev/null; then
    node_ver=$(node --version 2>/dev/null)
    context="${context} | Node: ${node_ver}"
  else
    context="${context} | [WARNING] Node.js プロジェクト検出 / node 未検出"
  fi
fi

# Python
if [ -f "pyproject.toml" ] || [ -f "setup.py" ] || [ -f "requirements.txt" ] || [ -f "Pipfile" ]; then
  if command -v python3 &>/dev/null; then
    py_ver=$(python3 --version 2>/dev/null | awk '{print $2}')
    context="${context} | Python: ${py_ver}"
  elif command -v python &>/dev/null; then
    py_ver=$(python --version 2>/dev/null | awk '{print $2}')
    context="${context} | Python: ${py_ver}"
  else
    context="${context} | [WARNING] Python プロジェクト検出 / python 未検出"
  fi
fi

# Go
if [ -f "go.mod" ]; then
  if command -v go &>/dev/null; then
    go_ver=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//')
    context="${context} | Go: ${go_ver}"
  else
    context="${context} | [WARNING] go.mod あり / go 未検出"
  fi
fi

# Java / Kotlin
if [ -f "pom.xml" ] || [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
  if command -v java &>/dev/null; then
    java_ver=$(java -version 2>&1 | head -1 | awk -F'"' '{print $2}')
    context="${context} | Java: ${java_ver}"
  else
    context="${context} | [WARNING] Java/Kotlin プロジェクト検出 / java 未検出"
  fi
fi

# Docker
if [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ] || [ -f "compose.yml" ]; then
  if command -v docker &>/dev/null; then
    docker_ver=$(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')
    context="${context} | Docker: ${docker_ver}"
  fi
fi

[ -n "$context" ] && echo -e "$context"
exit 0
