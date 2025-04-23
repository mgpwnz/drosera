#!/bin/bash

function="install"
ENV_FILE="$HOME/.drosera_env"

while test $# -gt 0; do
  case "$1" in
    -in|--install) function="install"; shift ;;
    -un|--uninstall) function="uninstall"; shift ;;
    -rpc|--rpc) function="rpc"; shift ;;
    *|--) break ;;
  esac
done

install() {
  cd $HOME
  set -e

  [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

  [[ -z "$GIT_NAME" ]] && read -p "👤 Git user.name: " GIT_NAME && echo "GIT_NAME=\"$GIT_NAME\"" >> "$ENV_FILE"
  [[ -z "$GIT_EMAIL" ]] && read -p "📧 Git user.email: " GIT_EMAIL && echo "GIT_EMAIL=\"$GIT_EMAIL\"" >> "$ENV_FILE"
  [[ -z "$PUBKEY" ]] && read -p "🔑 Wallet address (0x...): " PUBKEY && echo "PUBKEY=\"$PUBKEY\"" >> "$ENV_FILE"
  [[ -z "$PRIVKEY" ]] && read -p "🗝️ Private key: " PRIVKEY && echo "PRIVKEY=\"$PRIVKEY\"" >> "$ENV_FILE"
  [[ -z "$EXISTING_TRAP" ]] && read -p "🎯 Existing Trap address (or blank): " EXISTING_TRAP && echo "EXISTING_TRAP=\"$EXISTING_TRAP\"" >> "$ENV_FILE"
  [[ -z "$ETH_RPC" ]] && read -p "🌐 ETH RPC URL (or blank): " ETH_RPC && echo "ETH_RPC=\"$ETH_RPC\"" >> "$ENV_FILE"

  ETH_RPC=${ETH_RPC:-"https://ethereum-holesky-rpc.publicnode.com"}

  echo "🔄 Updating system..."
  sudo apt-get update && sudo apt-get upgrade -y

  echo "📦 Installing packages..."
  sudo apt install curl ufw iptables build-essential git wget lz4 jq make gcc nano \
    automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev \
    tar clang bsdmainutils ncdu unzip -y

  echo "🐳 Installing Docker..."
  touch $HOME/.bash_profile
  if ! docker --version &>/dev/null; then
    . /etc/*-release
    sudo apt update
    sudo apt install curl apt-transport-https ca-certificates gnupg lsb-release -y
    wget -qO- "https://download.docker.com/linux/${DISTRIB_ID,,}/gpg" | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/${DISTRIB_ID,,} ${DISTRIB_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    sudo apt update
    docker_version=$(apt-cache madison docker-ce | grep -oPm1 "(?<=docker-ce \| )([^_]+)(?= \| https)")
    sudo apt install docker-ce="$docker_version" docker-ce-cli="$docker_version" containerd.io -y
  fi

  if ! docker compose version &>/dev/null; then
    docker_compose_version=$(wget -qO- https://api.github.com/repos/docker/compose/releases/latest | jq -r ".tag_name")
    sudo wget -O /usr/bin/docker-compose "https://github.com/docker/compose/releases/download/${docker_compose_version}/docker-compose-$(uname -s)-$(uname -m)"
    sudo chmod +x /usr/bin/docker-compose
  fi

  echo "🛠 Installing Drosera, Foundry, Bun..."
  curl -sL https://app.drosera.io/install | bash
  curl -sL https://foundry.paradigm.xyz | bash
  curl -fsSL https://bun.sh/install | bash
  source ~/.bashrc
  droseraup
  foundryup

  echo "📁 Setting up Trap project..."
  mkdir -p $HOME/my-drosera-trap
  cd $HOME/my-drosera-trap
  git config --global user.email "$GIT_EMAIL"
  git config --global user.name "$GIT_NAME"

  if [[ -f "drosera.toml" ]]; then
    echo "🔁 Found drosera.toml, reusing..."
    EXISTING_TRAP=$(grep '^address' drosera.toml | cut -d'"' -f2)
    echo "EXISTING_TRAP=\"$EXISTING_TRAP\"" >> "$ENV_FILE"
  else
    forge init -t drosera-network/trap-foundry-template
    bun install
    source ~/.bashrc
    forge build
  fi

  SERVER_IP=$(hostname -I | awk '{print $1}')

  sed -i '/^private/d' drosera.toml
  sed -i '/^whitelist/d' drosera.toml
  sed -i '/^\[network\]/,$d' drosera.toml

  echo "private_trap = true" >> drosera.toml
  echo "whitelist = [\"$PUBKEY\"]" >> drosera.toml
  echo "[network]" >> drosera.toml
  echo "external_p2p_address = \"$SERVER_IP\"" >> drosera.toml

  [[ -n "$EXISTING_TRAP" ]] && grep -q '^address' drosera.toml || echo "address = \"$EXISTING_TRAP\"" >> drosera.toml

  if grep -q '^address = ' drosera.toml && [[ -n "$EXISTING_TRAP" ]]; then
    echo "📦 Existing Trap detected. Skipping drosera apply..."
  else
    echo "🚀 Applying Trap config..."
    DROSERA_PRIVATE_KEY="$PRIVKEY" drosera apply
  fi
  drosera dryrun

  echo "⬇️ Installing Operator CLI..."
  cd ~
  curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
  tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
  docker pull ghcr.io/drosera-network/drosera-operator:latest || true
  drosera-operator register --eth-rpc-url "$ETH_RPC" --eth-private-key "$PRIVKEY" || echo "⚠️ Already registered"

  echo "⚙️ Creating systemd service..."
  sudo tee /etc/systemd/system/drosera.service > /dev/null <<EOF
[Unit]
Description=Drosera Node
After=network-online.target

[Service]
User=$USER
Restart=always
RestartSec=15
LimitNOFILE=65535
ExecStart=$HOME/.drosera/bin/drosera-operator node --db-file-path $HOME/.drosera.db --network-p2p-port 31313 --server-port 31314 \
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

  sudo systemctl daemon-reload
  sudo systemctl enable drosera
  sudo systemctl start drosera

#   sudo ufw allow ssh
#   sudo ufw allow 22
#   sudo ufw allow 31313/tcp
#   sudo ufw allow 31314/tcp
#   sudo ufw --force enable

  echo -e "\n✅ Done! Drosera node running."
}

uninstall() {
  read -r -p "🧹 Remove all but keep config? [y/N] " response
  case "$response" in
    [yY][eE][sS]|[yY])
      sudo systemctl stop drosera 2>/dev/null
      sudo systemctl disable drosera 2>/dev/null
      sudo rm -f /etc/systemd/system/drosera.service
      sudo systemctl daemon-reload
      rm -rf $HOME/my-drosera-trap
      rm -rf $HOME/.drosera
      rm -rf $HOME/.drosera.db
      rm -f $HOME/drosera-operator*
      echo "✅ Cleaned up. .env saved at $ENV_FILE"
      ;;
    *) echo "❌ Cancelled" ;;
  esac
}

rpc() {
  SERVICE_FILE="/etc/systemd/system/drosera.service"
  [[ ! -f "$SERVICE_FILE" ]] && echo "❌ Service not found." && exit 1
  read -p "🔄 New ETH RPC URL: " NEW_RPC
  [[ -z "$NEW_RPC" ]] && echo "❌ Empty value." && exit 1
  sudo sed -i -E "s|--eth-rpc-url +[^ ]+|--eth-rpc-url $NEW_RPC|g" "$SERVICE_FILE"
  sudo systemctl daemon-reload
  sudo systemctl restart drosera
  sed -i "s|^ETH_RPC=.*|ETH_RPC=\"$NEW_RPC\"|" "$ENV_FILE" || echo "ETH_RPC=\"$NEW_RPC\"" >> "$ENV_FILE"
  echo "✅ RPC updated and service restarted."
}

sudo apt install wget -y &>/dev/null
cd
$function
