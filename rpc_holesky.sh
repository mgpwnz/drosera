#!/usr/bin/env bash
set -euo pipefail

# === Holesky Full-Node + Beacon Setup Script (with fixes) ===

# ---- Configuration ----
DATA_DIR="$HOME/holesky-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
GETH_DATA_DIR="$DATA_DIR/geth-data"
TEKU_DATA_DIR="$DATA_DIR/teku-data"
JWT_DIR="$DATA_DIR/jwtsecret"
JWT_FILE="$JWT_DIR/jwtsecret"
SNAPSHOT_URL="https://snapshots.ethpandaops.io/holesky/geth/latest/snapshot.tar.zst"
USE_SNAPSHOT=1

# ---- 1) Install Docker & Compose if missing ----
install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "🔄 Installing Docker & Compose..."
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
    echo "✅ Docker & Compose installed. You may need to log out/in for Docker group changes."
  else
    echo "ℹ️ Docker already installed."
  fi
}

# ---- 2) Prompt for snapshot usage ----
prompt_snapshot() {
  read -rp "⬇️ Use snapshot to speed sync? [Y/n]: " ans
  if [[ "$ans" =~ ^[Nn] ]]; then
    USE_SNAPSHOT=0
    echo "⚠️ Skipping snapshot; full sync from genesis."
  else
    echo "✅ Snapshot will be downloaded and applied."
  fi
}

# ---- 3) Prompt to wipe existing Geth data ----
prompt_wipe() {
  if [[ -d "$GETH_DATA_DIR/geth/chaindata" ]]; then
    read -rp "🗑️ Existing Geth data found; wipe it? [Y/n]: " wipe_ans
    if [[ ! "$wipe_ans" =~ ^[Nn] ]]; then
      echo "🗑️ Removing old Geth data..."
      rm -rf "$GETH_DATA_DIR"
    else
      echo "⚠️ Keeping existing Geth data; ensure state.storage=path."
    fi
  fi
}

# ---- 4) Generate JWT secret ----
generate_jwt() {
  mkdir -p "$JWT_DIR"
  if [[ ! -f "$JWT_FILE" ]]; then
    echo "🔑 Generating JWT secret..."
    openssl rand -hex 32 > "$JWT_FILE"
    echo "✅ JWT written to $JWT_FILE"
  else
    echo "ℹ️ JWT secret already exists."
  fi
}

# ---- 5) Download & extract snapshot ----
download_snapshot() {
  if (( USE_SNAPSHOT )); then
    echo "⬇️ Downloading snapshot..."
    mkdir -p "$GETH_DATA_DIR/geth"
    curl -fsSL --retry 5 --retry-delay 5 -C - "$SNAPSHOT_URL" -o "$DATA_DIR/snapshot.tar.zst"
    echo "🗜️ Extracting snapshot..."
    tar -I zstd -xvf "$DATA_DIR/snapshot.tar.zst" -C "$GETH_DATA_DIR/geth"
    rm -f "$DATA_DIR/snapshot.tar.zst"
    echo "✅ Snapshot applied."
  fi
}

# ---- 6) Write docker-compose.yml with fixes ----
write_compose() {
  echo "📄 Writing $COMPOSE_FILE"
  mkdir -p "$DATA_DIR"
  cat > "$COMPOSE_FILE" <<EOF
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
EOF

  if (( USE_SNAPSHOT )); then
    cat >> "$COMPOSE_FILE" <<EOF
      - --syncmode=snap
      - --snapshot=true
EOF
  else
    cat >> "$COMPOSE_FILE" <<EOF
      - --syncmode=full
EOF
  fi

  cat >> "$COMPOSE_FILE" <<EOF
      - --gcmode=full
      - --state.scheme=path
      - --cache=8192
      - --maxpeers=200
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
    networks:
      - holesky-net

  teku:
    image: consensys/teku:latest
    container_name: holesky-teku
    restart: unless-stopped
    depends_on:
      - geth
    user: root
    volumes:
      - ./teku-data:/data
      - ./jwtsecret/jwtsecret:/data/jwtsecret:ro
    entrypoint:
      - /bin/sh
      - -c
      - |
        mkdir -p /data/logs && \
        exec teku \
          --network=holesky \
          --data-path=/data \
          --logging=INFO \
          --ee-jwt-secret-file=/data/jwtsecret \
          --ee-endpoint=http://geth:8551 \
          --p2p-peer-lower-bound=50 \
          --rest-api-enabled \
          --rest-api-interface=0.0.0.0 \
          --rest-api-port=5051 \
          --metrics-enabled \
          --metrics-interface=0.0.0.0
    ports:
      - "5051:5051"
    networks:
      - holesky-net

networks:
  holesky-net:
    driver: bridge
EOF

  echo "✅ docker-compose.yml written."
}

# ---- 7) Launch Docker Compose stack ----
start_stack() {
  echo "🚀 Launching containers..."
  cd "$DATA_DIR"
  docker compose up -d
  echo "✅ Stack started. You can monitor logs with:"
  echo "   docker compose logs -f holesky-geth holesky-teku"
}

# ---- Main ----
install_docker
prompt_snapshot
prompt_wipe
generate_jwt
download_snapshot
write_compose
start_stack
