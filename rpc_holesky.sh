#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------
# CONFIGURATION
# ----------------------------------------
DATA_DIR="$HOME/holesky-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
JWT_SECRET="$DATA_DIR/jwtsecret"          # single file, shared
GETH_DATA="$DATA_DIR/geth-data"
TEKU_BEACON="$DATA_DIR/teku/beacon"
TEKU_JWT_DIR="$DATA_DIR/teku"
TEKU_JWT_FILE="$TEKU_JWT_DIR/jwtsecret"

# Snapshot URL for fast chain state (optional)
SNAPSHOT_URL="https://snapshots.ethpandaops.io/holesky/geth/latest/snapshot.tar.zst"

# ----------------------------------------
# 1) INSTALL DOCKER + COMPOSE (if needed)
# ----------------------------------------
install_docker(){
  if ! command -v docker &>/dev/null; then
    echo "🔄 Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    echo "✅ Docker & compose plugin installed."
  else
    echo "ℹ️ Docker already present."
  fi
}

# ----------------------------------------
# 2) GENERATE JWT SECRET
# ----------------------------------------
generate_jwt(){
  mkdir -p "$(dirname "$JWT_SECRET")"
  if [[ ! -f "$JWT_SECRET" ]]; then
    echo "🔑 Generating engine JWT secret..."
    openssl rand -hex 32 > "$JWT_SECRET"
    chmod 400 "$JWT_SECRET"
    echo "✅ JWT saved to $JWT_SECRET"
  else
    echo "ℹ️ JWT already exists at $JWT_SECRET"
  fi
}

# ----------------------------------------
# 3) WRITE DOCKER-COMPOSE.YML
# ----------------------------------------
write_compose(){
  echo "📄 Writing compose file to $COMPOSE_FILE…"
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
      - --syncmode=full
      - --gcmode=archive
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
    ports:
      - "8545:8545"
      - "8546:8546"
      - "30303:30303"
      - "30303:30303/udp"
    volumes:
      - $GETH_DATA:/root/.ethereum
      - $JWT_SECRET:/root/.ethereum/jwtsecret:ro

  teku:
    image: consensys/teku:latest
    container_name: teku
    restart: unless-stopped
    depends_on:
      - geth
    environment:
      JAVA_OPTS: "-Xmx16G"
    command:
      - beacon-node
      - --network=holesky
      - --ee-endpoint=http://geth:8551
      - --ee-jwt-file=/var/lib/teku/jwtsecret
      - --data-path=/var/lib/teku/beacon
      - --rest-api-enabled
      - --rest-api-interface=0.0.0.0
      - --rest-api-port=5051
    ports:
      - "9000:9000"   # P2P
      - "5051:5051"   # REST
    volumes:
      - $TEKU_BEACON:/var/lib/teku/beacon
      - $JWT_SECRET:$TEKU_JWT_FILE:ro
EOF
  echo "✅ Compose file ready."
}

# ----------------------------------------
# 4) DOWNLOAD SNAPSHOT (OPTIONAL)
# ----------------------------------------
download_snapshot(){
  echo "⬇️ Fetching and unpacking snapshot…"
  mkdir -p "$GETH_DATA"
  curl -fsSL "$SNAPSHOT_URL" | tar -I zstd -x -C "$GETH_DATA"
  echo "✅ Snapshot loaded into $GETH_DATA"
}

# ----------------------------------------
# 5) LAUNCH EVERYTHING
# ----------------------------------------
start_stack(){
  echo "🚀 Bringing up Geth + Teku stack…"
  cd "$DATA_DIR"
  docker compose up -d
  echo "✅ All containers started."
  echo
  echo "→ Geth logs:   docker logs -f holesky-geth"
  echo "→ Teku logs:   docker logs -f teku"
}

# ----------------------------------------
# RUN
# ----------------------------------------
echo "=== Holesky Full Archive + Teku Installer ==="
install_docker
generate_jwt
write_compose
# download_snapshot   # uncomment if you want the fast snapshot
start_stack
