#!/usr/bin/env bash
set -euo pipefail

# ---- Configuration ----
DATA_DIR="$HOME/holesky-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
JWT_DIR="$DATA_DIR/jwtsecret"
JWT_FILE="$JWT_DIR/jwtsecret"
SNAPSHOT_URL="https://snapshots.ethpandaops.io/holesky/geth/latest/snapshot.tar.zst"

# ---- 1) Install Docker if missing ----
install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "🔄 Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker "$USER"
    echo "✅ Docker installed."
  else
    echo "ℹ️ Docker already present."
  fi
}

# ---- 2) Generate JWT secret ----
generate_jwt() {
  mkdir -p "$JWT_DIR"
  if [[ ! -f "$JWT_FILE" ]]; then
    echo "🔑 Generating JWT secret..."
    openssl rand -hex 32 > "$JWT_FILE"
    echo "✅ JWT secret saved to $JWT_FILE"
  else
    echo "ℹ️ JWT secret already exists."
  fi
}

# ---- 3) Download & extract Holesky snapshot ----
download_snapshot() {
  local SNAP_DIR="$DATA_DIR/geth-data/holesky/geth"
  local SNAP_FILE="$DATA_DIR/snapshot.tar.zst"
  if [[ ! -d "$SNAP_DIR/chaindata" ]]; then
    echo "⬇️ Downloading snapshot to $SNAP_FILE..."
    mkdir -p "$SNAP_DIR"
    curl -fsSL --retry 5 --retry-delay 5 -C - "$SNAPSHOT_URL" -o "$SNAP_FILE"
    echo "🗜️ Extracting snapshot to $SNAP_DIR..."
    tar -I zstd -xvf "$SNAP_FILE" -C "$SNAP_DIR"
    rm -f "$SNAP_FILE"
    echo "✅ Snapshot extracted."
  else
    echo "ℹ️ Snapshot already in place."
  fi
}

# ---- 4) Auto-tune Geth cache by RAM ----
determine_cache() {
  local total_kb
  total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  if (( total_kb >= 32_000_000 )); then
    CACHE=16384
  elif (( total_kb >= 16_000_000 )); then
    CACHE=8192
  else
    CACHE=4096
  fi
  echo "ℹ️ Geth cache set to ${CACHE} MiB."
}

# ---- 5) Render docker-compose.yml ----
write_compose() {
  echo "📄 Writing $COMPOSE_FILE…"
  mkdir -p "$DATA_DIR"
  cat > "$COMPOSE_FILE" <<EOF
version: "3.8"
services:

  geth:
    image: ethereum/client-go:stable
    container_name: holesky-geth
    restart: unless-stopped
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
    command:
      - --holesky
      - --syncmode=full
      - --gcmode=archive
      - --cache=${CACHE}
      - --maxpeers=200
      - --bootnodes=enode://ac906289e4b7f12df423d654c5a962b6ebe5b3a74cc9e06292a85221f9a64a6f1cfdd6b714ed6dacef51578f92b34c60ee91e9ede9c7f8fadc4d347326d95e2b@146.190.13.128:30303
      - --http
      - --http.addr=0.0.0.0
      - --http.port=8545
      - --http.api=eth,net,web3,txpool,debug,admin
      - --http.corsdomain=*
      - --http.vhosts=*
      - --ws
      - --ws.addr=0.0.0.0
      - --ws.port=8546
      - --ws.api=eth,net,web3
      - --authrpc.addr=0.0.0.0
      - --authrpc.port=8551
      - --authrpc.vhosts=*
      - --authrpc.jwtsecret=/root/.ethereum/jwtsecret
    ports:
      - "8545:8545"
      - "8546:8546"
      - "8551:8551"
      - "30303:30303"
      - "30303:30303/udp"
    volumes:
      - ./geth-data:/root/.ethereum
      - ./jwtsecret/jwtsecret:/root/.ethereum/jwtsecret:ro

  teku:
    image: consensys/teku:latest
    container_name: holesky-teku
    restart: unless-stopped
    depends_on:
      - geth
    command:
      - beacon-node
      - --network=holesky
      - --ee-endpoint=http://geth:8551
      - --ee-jwt-file=/opt/teku/jwtsecret
      - --rest-api-enabled
      - --rest-api-interface=0.0.0.0
      - --rest-api-port=5051
    ports:
      - "5051:5051"
    volumes:
      - ./teku/beacon:/var/lib/teku/beacon
      - ./jwtsecret/jwtsecret:/opt/teku/jwtsecret:ro
EOF
  echo "✅ docker-compose.yml written."
}

# ---- 6) Launch everything ----
start_node() {
  echo "🚀 Bringing containers up…"
  cd "$DATA_DIR"
  docker compose up -d
  echo "✅ All set – streaming logs. ^C to stop:"
  docker logs -f holesky-geth holesky-teku
}

# ---- Main flow ----
echo "=== Holesky Full + Archive Script ==="
install_docker
determine_cache
generate_jwt
download_snapshot
write_compose
start_node
