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
[[ -z "$EXISTING_TRAP" ]] && read -p "🎯 Enter existing Trap address (or leave blank to use local config): " EXISTING_TRAP && echo "EXISTING_TRAP=\"$EXISTING_TRAP\"" >> "$ENV_FILE"
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

if [[ -f "$HOME/my-drosera-trap/drosera.toml" ]]; then
  echo "🔁 Reusing existing Trap configuration..."
  EXISTING_TRAP=$(grep '^address' drosera.toml | cut -d'"' -f2)
  echo "EXISTING_TRAP=\"$EXISTING_TRAP\"" >> "$ENV_FILE"
else
  echo "🆕 Initializing new Trap project..."
  forge init -t drosera-network/trap-foundry-template
  bun install
  source $HOME/.bashrc
  forge build
fi

git config --global user.email "$GIT_EMAIL"
git config --global user.name "$GIT_NAME"

# Write trap address if not present
if ! grep -q '^address = ' drosera.toml && [[ -n "$EXISTING_TRAP" ]]; then
  echo "address = \"$EXISTING_TRAP\"" >> drosera.toml
fi

# Clean old config
sed -i '/^private_trap/d' drosera.toml
sed -i '/^whitelist/d' drosera.toml
sed -i '/^\[network\]/,$d' drosera.toml

# Append whitelist block
SERVER_IP=$(hostname -I | awk '{print $1}')
{
  echo "private_trap = true"
  echo "whitelist = [\"$PUBKEY\"]"
  echo "[network]"
  echo "external_p2p_address = \"$SERVER_IP\""
} >> drosera.toml

DROSERA_PRIVATE_KEY="$PRIVKEY" drosera apply || echo "⚠️ Trap already applied or no change."
drosera dryrun

# === INSTALL OPERATOR CLI ===
# ... unchanged below
}

uninstall() {
  if [ ! -d "$HOME/my-drosera-trap" ]; then
    echo "Drosera directory not found"
    return
  fi

  read -r -p "Wipe trap files and systemd service, but keep .env? [y/N] " response
  case "$response" in
      [yY][eE][sS]|[yY])
          echo "🗑 Removing Drosera trap and systemd service..."
          sudo systemctl stop drosera.service
          sudo systemctl disable drosera.service
          sudo rm -f /etc/systemd/system/drosera.service
          sudo systemctl daemon-reload
          rm -rf "$HOME/my-drosera-trap"
          echo "✅ Uninstall complete. .drosera_env retained."
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
  ENV_FILE="$HOME/.drosera_env"
  if grep -q "^ETH_RPC=" "$ENV_FILE"; then
    sed -i "s|^ETH_RPC=.*|ETH_RPC=\"$NEW_RPC\"|" "$ENV_FILE"
  else
    echo "ETH_RPC=\"$NEW_RPC\"" >> "$ENV_FILE"
  fi
}

# Actions
sudo apt install wget -y &>/dev/null
cd
$function
