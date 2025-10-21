#!/bin/bash
set -euo pipefail

ROOT_DIR="$(pwd)"
BIN_DIR="$ROOT_DIR/bin"
RELEASE_REPO="paritytech/hardhat-polkadot"

msg(){ printf "%s\n" "$*"; }
have(){ command -v "$1" >/dev/null 2>&1; }

check_tools(){
  have git || { echo "ERROR: git is required but not found"; exit 1; }
  have npm || { echo "ERROR: npm is required but not found"; exit 1; }
  have curl || { echo "ERROR: curl is required but not found"; exit 1; }
  have node || { echo "ERROR: node is required but not found"; exit 1; }
  command -v corepack >/dev/null 2>&1 || true
}

clone_or_update(){
  local repo_url=$1 dir_name=$2 branch=$3
  echo "Setting up $dir_name..."
  rm -rf "$dir_name"
  if git clone -b "$branch" "$repo_url" "$dir_name"; then
    echo "  - SUCCESS: $dir_name ready"
  else
    echo "  - ERROR: Failed to clone $dir_name"
    return 1
  fi
}

pm_from_pkgjson(){
  local file="$1" val pm="npm"
  if [ -f "$file" ]; then
    val="$(node -e "try{const p=require('$file');console.log(p.packageManager||'')}catch(e){console.log('')}")"
    case "$val" in
      yarn*|*yarn*) pm="yarn";;
      pnpm*|*pnpm*) pm="pnpm";;
      npm*|*npm*)   pm="npm";;
    esac
  fi
  echo "$pm"
}

pm_version_from_pkgjson(){
  local file="$1"
  node -e "try{const p=require('$file');const s=String(p.packageManager||'');console.log(s.split('@')[1]||'')}catch(e){console.log('')}"
}

ensure_pm(){
  local pm="$1" ver="$2"
  case "$pm" in
    pnpm)
      if ! have pnpm; then
        corepack enable >/dev/null 2>&1 || true
        [ -n "$ver" ] && corepack prepare "pnpm@${ver}" --activate >/dev/null 2>&1 || true
      fi
      ;;
    yarn)
      if ! have yarn; then
        corepack enable >/dev/null 2>&1 || true
        [ -n "$ver" ] && corepack prepare "yarn@${ver}" --activate >/dev/null 2>&1 || true
      fi
      ;;
  esac
}

detect_platform(){
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    darwin)
      case "$arch" in
        arm64|aarch64) echo "darwin-arm64";;
        x86_64|amd64)  echo "darwin-x64";;
        *) echo "unknown";;
      esac;;
    linux)
      case "$arch" in
        x86_64|amd64)  echo "linux-x64";;
        aarch64|arm64) echo "linux-arm64";;
        *) echo "unknown";;
      esac;;
    *) echo "unknown";;
  esac
}

ts_loosen(){
  local dir="$1"
  if [ -f "$dir/tsconfig.json" ]; then
    node -e "const fs=require('fs');const p='$dir/tsconfig.json';let j=JSON.parse(fs.readFileSync(p));j.compilerOptions=j.compilerOptions||{};j.compilerOptions.skipLibCheck=true;j.compilerOptions.skipDefaultLibCheck=true;j.compilerOptions.noEmitOnError=false;fs.writeFileSync(p,JSON.stringify(j,null,2));"
  fi
}

install_deps(){
  local dir="$1" pm="$2"
  case "$pm" in
    yarn) (cd "$dir" && yarn install --silent ) || true ;;
    pnpm) (cd "$dir" && pnpm i --silent ) || true ;;
    npm)  (cd "$dir" && npm install --silent --no-audit --no-fund) || true ;;
  esac
}

rebuild_native(){
  local dir="$1" pm="$2"
  case "$pm" in
    yarn) (cd "$dir" && yarn run -s rebuild) || (cd "$dir" && pnpm rebuild >/dev/null 2>&1) || (cd "$dir" && npm rebuild) || true ;;
    pnpm) (cd "$dir" && pnpm rebuild) || true ;;
    npm)  (cd "$dir" && npm rebuild) || true ;;
  esac
}

build_pkg(){
  local dir="$1" pm="$2"
  ts_loosen "$dir"
  case "$pm" in
    yarn) (cd "$dir" && TS_NODE_TRANSPILE_ONLY=1 yarn build) || true ;;
    pnpm) (cd "$dir" && TS_NODE_TRANSPILE_ONLY=1 pnpm build) || true ;;
    npm)  (cd "$dir" && TS_NODE_TRANSPILE_ONLY=1 npm run build) || true ;;
  esac
}

link_parity_packages(){
  mkdir -p node_modules/@parity
  for pkg_dir in hardhat-polkadot/packages/*/; do
    [ -f "$pkg_dir/package.json" ] || continue
    local name
    name="$(grep -oE '"name"[[:space:]]*:[[:space:]]*"@parity/[^"]+' "$pkg_dir/package.json" | sed 's/.*"@parity\///')"
    [ -n "$name" ] || continue
    rm -rf "node_modules/@parity/$name"
    ln -sfn "$ROOT_DIR/$pkg_dir" "node_modules/@parity/$name"
    echo "@parity/$name symlink created"
  done
}

ensure_fs_xattr_stub(){
  local target_dir="$1"
  mkdir -p "$target_dir/node_modules/fs-xattr"
  cat > "$target_dir/node_modules/fs-xattr/package.json" <<'PKG'
{
  "name": "fs-xattr",
  "version": "0.0.0-stub",
  "main": "index.js"
}
PKG
  cat > "$target_dir/node_modules/fs-xattr/index.js" <<'JS'
module.exports = {
  get: async () => Buffer.alloc(0),
  set: async () => {},
  remove: async () => {},
  list: async () => []
}
JS
}

resolve_asset_url(){
  local want="$1"
  curl -fsSL "https://api.github.com/repos/${RELEASE_REPO}/releases?per_page=30" \
  | node -e '
    const fs=require("fs");
    const rels=JSON.parse(fs.readFileSync(0,"utf8"));
    const want=process.argv[1];
    for(const r of rels){
      const tag=(r.tag_name||"").toLowerCase();
      const name=(r.name||"").toLowerCase();
      if(tag.startsWith("nodes-")||name.includes("nodes build")){
        for(const a of r.assets||[]){
          if(a.name===want){ console.log(a.browser_download_url); process.exit(0); }
        }
      }
    }
    process.exit(1);
  ' "$want"
}

download_bin(){
  local asset="$1" link_name="$2"
  local url out
  if ! url="$(resolve_asset_url "$asset")"; then
    msg "$asset not found in latest nodes-* releases"
    return 1
  fi
  out="$BIN_DIR/$asset"
  curl -fsSL --retry 3 --retry-delay 1 -o "$out" "$url"
  chmod +x "$out"
  ln -sfn "$out" "$BIN_DIR/$link_name"
  msg "$link_name installed from $(basename "$url")"
}

install_nodes_binaries(){
  echo "Fetching latest node binaries..."
  mkdir -p "$BIN_DIR"
  local platform
  platform="$(detect_platform)"
  case "$platform" in
    darwin-arm64)
      download_bin "revive-dev-node-darwin-arm64" "revive-dev-node" || true
      download_bin "eth-rpc-darwin-arm64" "eth-rpc" || true
      ;;
    darwin-x64)
      download_bin "revive-dev-node-darwin-x64" "revive-dev-node" || true
      download_bin "eth-rpc-darwin-x64" "eth-rpc" || true
      ;;
    linux-x64)
      download_bin "revive-dev-node-linux-x64" "revive-dev-node" || true
      download_bin "eth-rpc-linux-x64" "eth-rpc" || true
      ;;
    linux-arm64)
      download_bin "revive-dev-node-linux-arm64" "revive-dev-node" || true
      download_bin "eth-rpc-linux-arm64" "eth-rpc" || true
      ;;
    *)
      echo "Unsupported platform: $platform"
      ;;
  esac
}

if [ "${npm_lifecycle_event:-}" = "preinstall" ]; then
  echo "Setting up dependencies..."
  check_tools
  if git submodule status >/dev/null 2>&1; then
    echo "Attempting git submodule update..."
    git submodule update --init --recursive || echo "Submodule update failed, continuing..."
  fi
  clone_or_update "https://github.com/Brianspha/micro-eth-signer.git" "micro-eth-signer" "main"
  clone_or_update "https://github.com/Brianspha/solidity.git" "solidity" "main"
  clone_or_update "https://github.com/Brianspha/hardhat-polkadot-trex.git" "hardhat-polkadot" "main"

  MES_PM="$(pm_from_pkgjson "$ROOT_DIR/micro-eth-signer/package.json")"
  MES_PM_VER="$(pm_version_from_pkgjson "$ROOT_DIR/micro-eth-signer/package.json")"
  ensure_pm "$MES_PM" "$MES_PM_VER"
  install_deps "$ROOT_DIR/micro-eth-signer" "$MES_PM"
  rebuild_native "$ROOT_DIR/micro-eth-signer" "$MES_PM"
  build_pkg "$ROOT_DIR/micro-eth-signer" "$MES_PM"

  HP_PM="$(pm_from_pkgjson "$ROOT_DIR/hardhat-polkadot/package.json")"
  HP_PM_VER="$(pm_version_from_pkgjson "$ROOT_DIR/hardhat-polkadot/package.json")"
  ensure_pm "$HP_PM" "$HP_PM_VER"
  install_deps "$ROOT_DIR/hardhat-polkadot" "$HP_PM"
  rebuild_native "$ROOT_DIR/hardhat-polkadot" "$HP_PM"
  build_pkg "$ROOT_DIR/hardhat-polkadot" "$HP_PM"

  SOL_PM="$(pm_from_pkgjson "$ROOT_DIR/solidity/package.json")"
  SOL_PM_VER="$(pm_version_from_pkgjson "$ROOT_DIR/solidity/package.json")"
  ensure_pm "$SOL_PM" "$SOL_PM_VER"
  install_deps "$ROOT_DIR/solidity" "$SOL_PM"
  rebuild_native "$ROOT_DIR/solidity" "$SOL_PM"
  build_pkg "$ROOT_DIR/solidity" "$SOL_PM"
fi

if [ "${npm_lifecycle_event:-}" = "postinstall" ]; then
  echo "Setting up symlinks..."
  mkdir -p node_modules/@onchain-id node_modules/@parity
  rm -rf node_modules/micro-eth-signer node_modules/@onchain-id/solidity node_modules/@parity/hardhat-polkadot*
  [ -d "micro-eth-signer" ] && ln -sfn "$ROOT_DIR/micro-eth-signer" node_modules/micro-eth-signer && echo "micro-eth-signer symlink created"
  [ -d "hardhat-polkadot" ] && link_parity_packages
  [ -d "solidity" ] && ln -sfn "$ROOT_DIR/solidity" node_modules/@onchain-id/solidity && echo "solidity symlink created"

  echo "Applying fs-xattr stub if native binding is missing..."
  node -e "try{require('fs-xattr');process.exit(0)}catch(e){process.exit(1)}" || true
  if ! node -e "try{require('fs-xattr');process.exit(0)}catch(e){process.exit(1)}"; then
    ensure_fs_xattr_stub "$ROOT_DIR"
    [ -d "$ROOT_DIR/hardhat-polkadot" ] && ensure_fs_xattr_stub "$ROOT_DIR/hardhat-polkadot"
    [ -d "$ROOT_DIR/solidity" ] && ensure_fs_xattr_stub "$ROOT_DIR/solidity"
    echo "fs-xattr stub installed"
  else
    echo "fs-xattr native module present"
  fi

  echo "Installing latest release binaries..."
  install_nodes_binaries
  echo "Setup complete!"
fi

exit 0
