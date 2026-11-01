#!/bin/zsh
# Offline test for the injected Markdown / text extractors (jsdom, no network).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# 依赖 jsdom。装不上或想复用别处的依赖时，用 NODE_MODULES 指过去：
#   NODE_MODULES=/path/to/node_modules ./tests/run.sh
NODE_MODULES="${NODE_MODULES:-$ROOT/tests/node_modules}"

# node 从 PATH 里找；需要指定版本时用 NODE_BIN 覆盖。
NODE_BIN="${NODE_BIN:-$(command -v node || true)}"
if [ -z "$NODE_BIN" ]; then
  echo "没找到 node。先装 Node.js，或用 NODE_BIN=/path/to/node 指定。" >&2
  exit 1
fi
if [ ! -d "$NODE_MODULES/jsdom" ]; then
  echo "没找到 jsdom。先执行：" >&2
  echo "  npm install --prefix tests jsdom" >&2
  exit 1
fi

cd "$ROOT"
echo "using node: $NODE_BIN"
NODE_PATH="$NODE_MODULES" "$NODE_BIN" tests/export.test.mjs
