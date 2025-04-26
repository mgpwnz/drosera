#!/usr/bin/env bash
set -euo pipefail

# ---- Configuration ----
DATA_DIR="$HOME/holesky-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
JWT_DIR="$DATA_DIR/jwtsecret"
JWT_FILE="$JWT_DIR/jwtsecret"
TEKU_DATA="$DATA_DIR/teku-data"

# ---- Prepare directories ----
mkdir -p "$DATA_DIR/geth-data" "$JWT_DIR" "$TEKU_DATA"

# ---- Install Docker if missing ----
install_docker() {
  if ! command -v docker &>/dev/null; then
    echo "🔄 Installing Docker..."
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg lsb-release
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker "$USER"
    echo "✅ Docker installed."
  else
    echo "ℹ️ Docker is already installed."
  fi
}

# ---- Generate JWT secret ----
generate_jwt() {
  if [[ ! -f "$JWT_FILE" ]]; then
    echo "🔑 Generating JWT secret..."
    openssl rand -hex 32 > "$JWT_FILE"
    echo "✅ JWT secret saved to $JWT_FILE"
  else
    echo "ℹ️ JWT secret already exists."
  fi
}

# ---- Determine cache based on RAM ----
determine_cache() {
  local total_kb
  total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  if (( total_kb >= 32768000 )); then
    CACHE=16384
  elif (( total_kb >= 16384000 )); then
    CACHE=8192
  else
    CACHE=4096
  fi
  echo "ℹ️ Geth cache set to $CACHE MiB"
}

# ---- Read optional unlock addresses ----
read -p "Enter EVM addresses to unlock (comma-separated, leave blank to skip): " EVM_ADDRS
UNLOCK_ARGS=()
if [[ -n "$EVM_ADDRS" ]]; then
  IFS=',' read -ra ADDR_ARRAY <<< "$EVM_ADDRS"
  for addr in "${ADDR_ARRAY[@]}"; do
    UNLOCK_ARGS+=("--unlock=$addr")
  done
  UNLOCK_ARGS+=("--allow-insecure-unlock")
fi

# ---- Write docker-compose.yml ----
write_compose() {
  echo "📄 Generating docker-compose.yml..."
  local tmp
  tmp=$(mktemp)
  cat >"$tmp" <<EOF
version: "3.8"

services:
  # Execution client: Geth
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
  local geth_args=(
    "--holesky"
    "--syncmode=full"
    "--gcmode=archive"
    "--cache=$CACHE"
    "--maxpeers=200"
    "--bootnodes=enode://ac906289e4b7f12df423d654c5a962b6ebe5b3a74cc9e06292a85221f9a64a6f1cfdd6b714ed6dacef51578f92b34c60ee91e9ede9c7f8fadc4d347326d95e2b@146.190.13.128:30303"
    "--http"
    "--http.addr=0.0.0.0"
    "--http.port=8545"
    "--http.api=eth,net,web3,txpool,debug,admin"
    "--http.corsdomain=*"
    "--http.vhosts=*"
    "--ws"
    "--ws.addr=0.0.0.0"
    "--ws.port=8546"
    "--ws.api=eth,net,web3"
    "--authrpc.addr=0.0.0.0"
    "--authrpc.port=8551"
    "--authrpc.jwtsecret=/root/.ethereum/jwtsecret/jwtsecret"
  )
  for arg in "${geth_args[@]}"; do
    echo "      - $arg" >>"$tmp"
  done
  if (( ${#UNLOCK_ARGS[@]} > 0 )); then
    for u in "${UNLOCK_ARGS[@]}"; do
      echo "      - $u" >>"$tmp"
    done
  fi
  cat >>"$tmp" <<EOF
    ports:
      - "8545:8545"
      - "8546:8546"
      - "8551:8551"
      - "30303:30303"
      - "30303:30303/udp"
    volumes:
      - ./geth-data:/root/.ethereum
      - ./jwtsecret:/root/.ethereum/jwtsecret

  # Consensus client: Teku
  teku:
    image: consensys/teku:latest
    container_name: teku
    restart: unless-stopped
    ports:
      - "5051:5051"   # REST API port
      - "9000:9000"   # P2P port
    command:
      - --network=holesky
      - --data-path=/var/lib/teku
      - --ee-endpoint=http://holesky-geth:8551
      - --ee-jwt-secret-file=/var/lib/teku/jwtsecret
      - --rest-api-enabled
      - --rest-api-port=5051
      - --p2p-enabled
      - --p2p-port=9000
    volumes:
      - ./teku-data:/var/lib/teku
      - ./jwtsecret:/var/lib/teku/jwtsecret

volumes:
  teku-data:
  geth-data:
EOF
  mv "$tmp" "$COMPOSE_FILE"
  echo "✅ docker-compose.yml generated."
}

# ---- Start node ----
start_node() {
  echo "🚀 Launching Holesky Full+Archive Node with Consensus..."
  cd "$DATA_DIR"
  docker compose up -d
  echo "✅ Containers started. Following logs..."
  docker logs -f holesky-geth
}

# ---- Main ----
echo "=== Holesky Full+Archive Node & Teku Consensus Setup ==="
install_docker
determine_cache
generate_jwt
write_compose
start_node
