#!/usr/bin/env bash
set -euo pipefail

# ---- Configuration ----
DATA_DIR="$HOME/holesky-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
JWT_DIR="$DATA_DIR/jwtsecret"
JWT_FILE="$JWT_DIR/jwtsecret"

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

# ---- Generate JWT secret ----
generate_jwt() {
  mkdir -p "$JWT_DIR"
  if [[ ! -f "$JWT_FILE" ]]; then
    echo "🔑 Generating JWT secret..."
    openssl rand -hex 32 > "$JWT_FILE"
    chmod 600 "$JWT_FILE"
    echo "✅ JWT secret saved to $JWT_FILE"
  else
    echo "ℹ️ JWT secret already exists."
  fi
}

# ---- Determine Geth cache based on system memory ----
determine_cache() {
  local total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  if (( total_kb >= 32768000 )); then
    CACHE=16384
  elif (( total_kb >= 16384000 )); then
    CACHE=8192
  else
    CACHE=4096
  fi
  echo "ℹ️ Setting Geth cache to $CACHE MiB based on system RAM"
}

# ---- Write docker-compose.yml ----
write_compose() {
  echo "📄 Generating docker-compose.yml..."
  mkdir -p "$DATA_DIR"
  cat > "$COMPOSE_FILE" <<EOF
version: '3.8'
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
      - --holesky
      - --syncmode=full
      - --gcmode=archive
      - --cache=\${CACHE}
      - --maxpeers=200
      - --bootnodes=enode://ac906289e4b7f12df423d654...@146.190.13.128:30303
      - --http
      - --http.addr=0.0.0.0
      - --http.port=8545
      - --http.api=eth,net,web3,txpool,debug,admin
      - --http.corsdomain="*"
      - --http.vhosts="*"
      - --ws
      - --ws.addr=0.0.0.0
      - --ws.port=8546
      - --ws.api=eth,net,web3
      - --authrpc.addr=0.0.0.0
      - --authrpc.port=8551
      - --authrpc.jwtsecret=/root/.ethereum/jwtsecret/jwtsecret
    ports:
      - "8545:8545"
      - "8546:8546"
      - "8551:8551"
      - "30303:30303"
      - "30303:30303/udp"
    volumes:
      - ./geth-data:/root/.ethereum/holesky
      - ./jwtsecret/jwtsecret:/root/.ethereum/jwtsecret

  teku:
    image: consensys/teku:latest
    container_name: teku
    restart: unless-stopped
    volumes:
      - ./teku-data:/var/lib/teku
      - ./jwtsecret/jwtsecret:/var/lib/teku/jwtsecret:ro
    ports:
      - "5051:5051"
    command:
      # Teku auto-entrypoint will pick up args directly
      --network=holesky
      --data-path=/var/lib/teku
      --beacon-node-api-enabled=true
      --beacon-node-api-interface=0.0.0.0
      --beacon-node-api-port=5051
      --ee-jwt-file=/var/lib/teku/jwtsecret
      --logging=INFO
EOF
  echo "✅ docker-compose.yml generated."
}

# ---- Start the stack ----
start_services() {
  echo "🚀 Bringing up Geth + Teku..."
  cd "$DATA_DIR"
  docker compose up -d
  echo "✅ Containers started. To follow logs: docker logs -f holesky-geth teku"
}

# ---- Main ----
echo "=== Installing and starting Holesky full+archive + Teku stack ==="
install_docker
determine_cache
generate_jwt
write_compose
start_services
