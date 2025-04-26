#!/usr/bin/env bash
set -euo pipefail

# ==== Configuration ==== 
DATA_DIR="$HOME/holesky-node"
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
JWT_FILE="$DATA_DIR/jwtsecret"

# ---- Create necessary directories ----
mkdir -p "$DATA_DIR/geth-data"
mkdir -p "$DATA_DIR/logs/teku"
mkdir -p "$DATA_DIR/beacon/teku"
mkdir -p "$DATA_DIR/validator/teku/slashprotection"

# ==== Install Docker if missing ==== 
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
    echo "ℹ️ Docker already present."
  fi
}

# ==== Generate JWT secret ==== 
generate_jwt() {
  if [[ ! -f "$JWT_FILE" ]]; then
    echo "🔑 Creating JWT secret..."
    openssl rand -hex 32 > "$JWT_FILE"
    echo "✅ JWT saved: $JWT_FILE"
  else
    echo "ℹ️ JWT secret exists: $JWT_FILE"
  fi
}

# ==== Write docker-compose.yml ==== 
write_compose() {
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
      - --cache=8192
      - --maxpeers=200
      - --http
      - --http.addr=0.0.0.0
      - --http.port=8545
      - --http.api=eth,net,web3,txpool,admin,debug
      - --http.corsdomain='*'
      - --http.vhosts='*'
      - --ws
      - --ws.addr=0.0.0.0
      - --ws.port=8546
      - --ws.api=eth,net,web3
      - --authrpc
      - --authrpc.addr=0.0.0.0
      - --authrpc.port=8551
      - --authrpc.jwtsecret=/root/.ethereum/jwtsecret
    ports:
      - '8545:8545'
      - '8546:8546'
      - '8551:8551'
      - '30303:30303'
      - '30303:30303/udp'
    volumes:
      - ./geth-data:/root/.ethereum
      - ./jwtsecret:/root/.ethereum/jwtsecret:ro

  teku:
    image: eclipse-temurin:17-jre
    container_name: teku
    restart: unless-stopped
    depends_on:
      - holesky-geth
    command:
      - teku
      - --network=holesky
      - --ee-endpoint=http://holesky-geth:8551
      - --ee-jwt-secret-file=/var/lib/teku/jwtsecret
      - --data-path=/var/lib/teku/beacon
      - --validators-keystore-locking-enabled=false
      - --Xrest-api-enabled=true
      - --rest-api-interface=0.0.0.0
      - --rest-api-port=5051
      - --status-logging-enabled
      - --log-destination=file
      - --log-file=/var/lib/teku/logs/teku.log
    ports:
      - '5051:5051'
    volumes:
      - ./jwtsecret:/var/lib/teku/jwtsecret:ro
      - ./logs/teku:/var/lib/teku/logs
      - ./beacon/teku:/var/lib/teku/beacon
      - ./validator/teku/slashprotection:/var/lib/teku/validator/slashprotection
EOF
  echo "✅ docker-compose.yml created at $COMPOSE_FILE"
}

# ==== Main ==== 
echo '=== Starting Holesky full+archive + Teku stack ==='
install_docker
generate_jwt
write_compose
echo '🚀 Launching containers...'
cd "$DATA_DIR"
docker compose up -d

echo '✅ All services started.'
docker compose logs -f --tail=20
