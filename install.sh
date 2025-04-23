#!/bin/bash

# Default variables
function="install"

# Options
option_value(){ echo "$1" | sed -e 's%^--[^=]*=%%g; s%^-[^=]*=%%g'; }
while test $# -gt 0; do
        case "$1" in
        -in|--install)
            function="install"
            shift
            ;;
        -un|--uninstall)
            function="uninstall"
            shift
            ;;
        -rpc|--rpc)
            function="rpc"
            shift
            ;;
        *|--)
            break
        ;;
        esac
done

install() {
# === SETUP ===
cd $HOME
set -e

# === LOAD ENV ===
ENV_FILE="$HOME/.drosera_env"
if [[ -f "$ENV_FILE" ]]; then
  source "$ENV_FILE"
fi

# === ASK FOR MISSING VARIABLES ===
[[ -z "$GIT_NAME" ]] && read -p "👤 Enter Git user.name: " GIT_NAME && echo "GIT_NAME=\"$GIT_NAME\"" >> "$ENV_FILE"
[[ -z "$GIT_EMAIL" ]] && read -p "📧 Enter Git user.email: " GIT_EMAIL && echo "GIT_EMAIL=\"$GIT_EMAIL\"" >> "$ENV_FILE"
[[ -z "$PUBKEY" ]] && read -p "🔑 Enter your wallet address (0x...): " PUBKEY && echo "PUBKEY=\"$PUBKEY\"" >> "$ENV_FILE"
[[ -z "$PRIVKEY" ]] && read -p "🗝️ Enter your private key: " PRIVKEY && echo "PRIVKEY=\"$PRIVKEY\"" >> "$ENV_FILE"
[[ -z "$EXISTING_TRAP" ]] && read -p "🎯 Enter existing Trap address (or leave blank to create new): " EXISTING_TRAP && echo "EXISTING_TRAP=\"$EXISTING_TRAP\"" >> "$ENV_FILE"
[[ -z "$ETH_RPC" ]] && read -p "🌐 Enter ETH RPC URL (or leave blank for public node): " ETH_RPC && echo "ETH_RPC=\"$ETH_RPC\"" >> "$ENV_FILE"

# === DEFAULTS ===
ETH_RPC=${ETH_RPC:-"https://ethereum-holesky-rpc.publicnode.com"}

# === SYSTEM UPDATE ===
echo "🔄 Updating system packages..."
sudo apt-get update && sudo apt-get upgrade -y

# === INSTALL DEPENDENCIES ===
echo "📦 Installing dependencies..."
sudo apt install curl ufw iptables build-essential git wget lz4 jq make gcc nano \
  automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev \
  tar clang bsdmainutils ncdu unzip -y

# === INSTALL DOCKER & COMPOSE ===
echo "🐳 Installing Docker and Compose..."
cd $HOME
touch $HOME/.bash_profile
if ! docker --version &>/dev/null; then
  . /etc/*-release
  sudo apt update
  sudo apt install curl apt-transport-https ca-certificates gnupg lsb-release -y
  wget -qO- "https://download.docker.com/linux/${DISTRIB_ID,,}/gpg" | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
  echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${DISTRIB_ID,,} ${DISTRIB_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install docker-ce docker-ce-cli containerd.io -y
  docker_version=$(apt-cache madison docker-ce | grep -oPm1 "(?<=docker-ce \| )([^_]+)(?= \| https)")
  sudo apt install docker-ce="$docker_version" docker-ce-cli="$docker_version" containerd.io -y
fi

if ! docker compose version &>/dev/null; then
  docker_compose_version=$(wget -qO- https://api.github.com/repos/docker/compose/releases/latest | jq -r ".tag_name")
  sudo wget -O /usr/bin/docker-compose "https://github.com/docker/compose/releases/download/${docker_compose_version}/docker-compose-$(uname -s)-$(uname -m)"
  sudo chmod +x /usr/bin/docker-compose
fi

echo -e "\e[1m\e[32m✅ Docker and dependencies installed.\e[0m"

# === INSTALL TRAP CLI TOOLS ===
echo "🌐 Installing Drosera, Foundry, and Bun..."
curl -L https://app.drosera.io/install | bash
curl -L https://foundry.paradigm.xyz | bash
curl -fsSL https://bun.sh/install | bash
source /root/.bashrc
foundryup
droseraup

# === TRAP DEPLOYMENT STEPS ===
echo "📁 Setting up Trap project..."
mkdir -p $HOME/my-drosera-trap
cd $HOME/my-drosera-trap

git config --global user.email "$GIT_EMAIL"
git config --global user.name "$GIT_NAME"

forge init -t drosera-network/trap-foundry-template
bun install
source $HOME/.bashrc
forge build

# Add trap address if provided
[[ -n "$EXISTING_TRAP" ]] && echo "address = \"$EXISTING_TRAP\"" >> drosera.toml

# Remove any old private_trap or whitelist lines
sed -i '/^private_trap/d' drosera.toml
sed -i '/^whitelist/d' drosera.toml

# Append new whitelist and external IP block
SERVER_IP=$(hostname -I | awk '{print $1}')
{
  echo "private_trap = true"
  echo "whitelist = [\"$PUBKEY\"]"
  echo "[network]"
  echo "external_p2p_address = \"$SERVER_IP\""
} >> drosera.toml

DROSERA_PRIVATE_KEY="$PRIVKEY" drosera apply
drosera dryrun

# === INSTALL OPERATOR CLI ===
echo "⬇️ Installing Drosera Operator CLI..."
cd ~
curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz

# Optional Docker image pull
docker pull ghcr.io/drosera-network/drosera-operator:latest || true

drosera-operator register --eth-rpc-url "$ETH_RPC" --eth-private-key "$PRIVKEY"

# === CREATE SYSTEMD SERVICE ===
echo "⚙️ Creating drosera systemd service..."
SERVER_IP=$(hostname -I | awk '{print $1}')
sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=drosera node service
After=network-online.target

[Service]
User=$USER
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=$(which drosera-operator) node --db-file-path $HOME/.drosera.db --network-p2p-port 31313 --server-port 31314 \
    --eth-rpc-url $ETH_RPC \
    --eth-backup-rpc-url https://1rpc.io/holesky \
    --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \
    --eth-private-key $PRIVKEY \
    --listen-address 0.0.0.0 \
    --network-external-p2p-address $SERVER_IP \
    --disable-dnr-confirmation true

[Install]
WantedBy=multi-user.target
EOF

# # === ENABLE FIREWALL ===
# echo "🔐 Configuring UFW firewall..."
# sudo ufw allow ssh
# sudo ufw allow 22
# sudo ufw allow 31313/tcp
# sudo ufw allow 31314/tcp
# sudo ufw --force enable

# === START SERVICE ===
echo "🚀 Starting drosera service..."
sudo systemctl daemon-reload
sudo systemctl enable drosera
sudo systemctl start drosera

# === DONE ===
echo -e "\n\e[1m\e[32m✅ Setup complete! Service running.\e[0m"
}

update() {
  echo "(update function placeholder)"
}

uninstall() {
  if [ ! -d "$HOME/my-drosera-trap" ]; then
      echo "Drosera directory not found"
      return
  fi

  read -r -p "Wipe all Drosera data and remove services? [y/N] " response
  case "$response" in
      [yY][eE][sS]|[yY])
          echo "🗑 Removing Drosera trap, config, and service..."
          sudo systemctl stop drosera.service
          sudo systemctl disable drosera.service
          sudo rm -f /etc/systemd/system/drosera.service
          sudo systemctl daemon-reload
          rm -rf "$HOME/my-drosera-trap"
          rm -f "$HOME/.drosera_env"
          echo "✅ Uninstall complete."
          ;;
      *)
          echo "❌ Uninstall canceled."
          ;;
  esac
}

rpc() {
  SERVICE_FILE="/etc/systemd/system/drosera.service"
  if [[ ! -f "$SERVICE_FILE" ]]; then
    echo "❌ Drosera systemd service not found. Please install first."
    exit 1
  fi

  read -p "🌐 Enter new ETH RPC URL: " NEW_RPC
  if [[ -z "$NEW_RPC" ]]; then
    echo "❌ RPC URL cannot be empty."
    exit 1
  fi

  sudo sed -i -E "s|--eth-rpc-url +[^ ]+|--eth-rpc-url $NEW_RPC|g" "$SERVICE_FILE"

  sudo systemctl daemon-reload
  sudo systemctl restart drosera
  echo "✅ RPC updated to $NEW_RPC and drosera service restarted."

  # Update ENV file
  ENV_FILE=\"$HOME/.drosera_env\"
  if grep -q \"^ETH_RPC=\" \"$ENV_FILE\"; then
    sed -i \"s|^ETH_RPC=.*|ETH_RPC=\\\"$NEW_RPC\\\"|\" \"$ENV_FILE\"
  else
    echo \"ETH_RPC=\\\"$NEW_RPC\\\"\" >> \"$ENV_FILE\"
  fi
}

# Actions
sudo apt install wget -y &>/dev/null
cd
$function