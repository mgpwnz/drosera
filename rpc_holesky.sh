#!/usr/bin/env bash
set -euo pipefail

# ---- Configuration ----
DATA_DIR="$HOME/holesky-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
JWT_FILE="$DATA_DIR/jwtsecret"
SNAPSHOT_URL="https://snapshots.ethpandaops.io/holesky/geth/latest/snapshot.tar.zst"

# ---- Install Docker if missing ----
install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "🔄 Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker "$USER"
    echo "✅ Docker installed."
  else
    echo "ℹ️ Docker is already installed."
  fi
}

# ---- Generate a JWT secret if missing ----
generate_jwt() {
  if [[ ! -f "$JWT_FILE" ]]; then
    echo "🔑 Generating JWT secret..."
    openssl rand -hex 32 > "$JWT_FILE"
    echo "✅ JWT secret saved to $JWT_FILE"
  else
    echo "ℹ️ JWT secret already exists."
  fi
}

# ---- Download and extract a Holesky snapshot ----
download_snapshot() {
  local SNAP_DIR="$DATA_DIR/geth-data/holesky/geth"
  if [[ ! -d "$SNAP_DIR/chaindata" ]]; then
    echo "⬇️ Downloading and extracting Holesky snapshot to $SNAP_DIR..."
    mkdir -p "$SNAP_DIR"
    curl -sL "$SNAPSHOT_URL" \
      | tar -I zstd -xvf - -C "$SNAP_DIR"
    echo "✅ Snapshot extracted to $SNAP_DIR"
  else
    echo "ℹ️ Snapshot already extracted."
  fi
}

# ---- Read optional EVM addresses for unlocking ----
read -p "Enter EVM addresses to unlock (comma-separated, leave blank to skip): " EVM_ADDRS
UNLOCK_ARGS=()
if [[ -n "$EVM_ADDRS" ]]; then
  IFS=',' read -ra ADDR_ARRAY <<< "$EVM_ADDRS"
  for addr in "${ADDR_ARRAY[@]}"; do
    UNLOCK_ARGS+=("--unlock=$addr")
  done
  UNLOCK_ARGS+=("--allow-insecure-unlock")
fi

# ---- Write docker-compose.yml with current settings ----
write_compose() {
  echo "📄 Generating docker-compose.yml..."
  local TMP_FILE
  TMP_FILE=$(mktemp)
  cat > "$TMP_FILE" <<EOF
version: "3.8"

services:
  holesky-geth:
    image: ethereum/client-go:stable
    container_name: holesky-geth
    restart: unless-stopped
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    command:
EOF
  # Base command-line arguments
  BASE_ARGS=(
    "--holesky"
    "--syncmode=snap"
    "--cache=4096"
    "--maxpeers=100"
    "--bootnodes=enode://ac906289e4b7f12df423d654c5a962b6ebe5b3a74cc9e06292a85221f9a64a6f1cfdd6b714ed6dacef51578f92b34c60ee91e9ede9c7f8fadc4d347326d95e2b@146.190.13.128:30303,enode://a3435a0155a3e837c02f5e7f5662a2f1fbc25b48e4dc232016e1c51b544cb5b4510ef633ea3278c0e970fa8a"
    "--http"
    "--port=30303"
    "--nat=extip:88.99.209.50"
    "--http.addr=0.0.0.0"
    "--http.port=8545"
    "--http.api=eth,net,web3,txpool"
    "--http.corsdomain=*"
    "--http.vhosts=*"
    "--ws"
    "--ws.addr=0.0.0.0"
    "--ws.port=8546"
    "--ws.api=eth,net,web3"
    "--authrpc.addr=0.0.0.0"
    "--authrpc.port=8551"
    "--authrpc.jwtsecret=/root/.ethereum/jwtsecret"
  )
  for arg in "${BASE_ARGS[@]}"; do
    echo "      - $arg" >> "$TMP_FILE"
  done
  # Append unlock arguments if provided
  if [[ ${#UNLOCK_ARGS[@]} -gt 0 ]]; then
    for arg in "${UNLOCK_ARGS[@]}"; do
      echo "      - $arg" >> "$TMP_FILE"
    done
  fi
  # Ports and volumes
  cat >> "$TMP_FILE" <<EOF
    ports:
      - "8545:8545"
      - "8546:8546"
      - "8551:8551"
      - "30303:30303"
      - "30303:30303/udp"
    volumes:
      - ./geth-data:/root/.ethereum
      - ./jwtsecret:/root/.ethereum/jwtsecret
EOF
  mv "$TMP_FILE" "$COMPOSE_FILE"
  echo "✅ docker-compose.yml generated."
}

# ---- Start the node using Docker Compose ----
start_node() {
  echo "🚀 Starting Holesky RPC node..."
  cd "$DATA_DIR"
  docker compose up -d
  echo "✅ Node started. Logs:"
  docker logs -f holesky-geth
}

# ---- Main execution ----
echo "=== Installing and starting Holesky RPC node with current settings ==="
install_docker
mkdir -p "$DATA_DIR/geth-data/holesky/geth"
generate_jwt
download_snapshot
write_compose
start_node
echo "=== Holesky RPC node setup complete! ==="
echo "You can access the RPC at http://localhost:8545"