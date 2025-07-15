#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ---------------------------------------------
# Improved Drosera Setup & Management Script
# ---------------------------------------------

# Helper functions
error_exit() {
  echo "❌ $1" >&2
  exit 1
}
require_cmd() {
  command -v "$1" &>/dev/null || error_exit "Команда '$1' не найдена. Установите её."
}

# Check essential utilities
for cmd in curl jq git docker; do
  require_cmd "$cmd"
done

# Paths and variables
env_file="$HOME/.env.drosera"
project_dir="$HOME/Drosera-Network"
compose_file="$project_dir/docker-compose.yml"
trap_dir="$HOME/my-drosera-trap"

# Load environment if exists
echo "🔁 Loading config from $env_file"
if [[ -f "$env_file" ]]; then
  # shellcheck source=/dev/null
  source "$env_file"
fi

# Function to generate docker-compose with two Drosera operators
generate_compose() {
  mkdir -p "$project_dir"
  cat > "$compose_file" <<-EOF
  version: '3.8'
  services:
    operator1:
      image: ghcr.io/drosera-network/drosera-operator:latest
      network_mode: host
      command: ["node"]
      environment:
        - DRO__ETH__CHAIN_ID=560048
        - DRO__ETH__RPC_URL=${Hoodi_RPC}
        - DRO__ETH__PRIVATE_KEY=${private_key}
        - DRO__NETWORK__P2P_PORT=31313
        - DRO__SERVER__PORT=31314
        - DRO__NETWORK__EXTERNAL_P2P_ADDRESS=${SERVER_IP}
        - DRO__DISABLE_DNR_CONFIRMATION=true
        - DRO__LOG__LEVEL=debug
      volumes:
        - op1_data:/data
      restart: unless-stopped

    operator2:
      image: ghcr.io/drosera-network/drosera-operator:latest
      network_mode: host
      command: ["node"]
      environment:
        - DRO__ETH__CHAIN_ID=560048
        - DRO__ETH__RPC_URL=${Hoodi_RPC}
        - DRO__ETH__PRIVATE_KEY=${private_key2}
        - DRO__NETWORK__P2P_PORT=31315
        - DRO__SERVER__PORT=31316
        - DRO__NETWORK__EXTERNAL_P2P_ADDRESS=${SERVER_IP}
        - DRO__DISABLE_DNR_CONFIRMATION=true
        - DRO__LOG__LEVEL=debug
      volumes:
        - op2_data:/data
      restart: unless-stopped

  volumes:
    op1_data:
    op2_data:
  EOF
}

# Main menu
echo "Select an action:"
PS3='> '
options=(
  "Install Dependencies"
  "Setup CLI & Configure Env"
  "Create Trap"
  "Install & Register Operators"
  "Run Drosera"
  "View Logs"
  "Update RPC URL"
  "Uninstall Drosera"
  "Exit"
)

select opt in "${options[@]}"; do
  case $opt in

  "Install Dependencies")
    echo "--- Installing Dependencies ---"
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl ufw iptables build-essential git wget lz4 jq make gcc nano \
      automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev \
      tar clang bsdmainutils ncdu unzip docker-compose-plugin
    echo "✅ Dependencies installed"
    break ;;  

  "Setup CLI & Configure Env")
    echo "--- Setting Up CLI Tools & Environment ---"
    # Install Drosera CLI, Foundry, Bun
    for tool in drosera forge bun; do
      if ! command -v $tool &>/dev/null; then
        echo "🔽 Installing $tool..."
        case $tool in
          drosera) curl https://app.drosera.io/install | bash || error_exit "Drosera install failed" ;; 
          forge)  curl -L https://foundry.paradigm.xyz | bash || error_exit "Foundry install failed" ;;  
          bun)    curl -fsSL https://bun.sh/install | bash || error_exit "Bun install failed" ;;  
        esac
      else
        echo "ℹ️ $tool уже установлен"
      fi
    done
    # Ensure PATH updates in .bashrc
    for dir in "$HOME/.drosera/bin" "$HOME/.foundry/bin" "$HOME/.bun/bin"; do
      grep -qxF "export PATH=\"\\$PATH:$dir\"" "$HOME/.bashrc" || \
        echo "export PATH=\"\\$PATH:$dir\"" >> "$HOME/.bashrc"
    done
    source "$HOME/.bashrc"

    # Create or source env file
    touch "$env_file"
    # Prompt and save missing variables
    declare -A prompts=(
      [github_Email]="Enter GitHub email: "
      [github_Username]="Enter GitHub username: "
      [private_key]="Enter your private key: "
      [public_key]="Enter your public key: "
      [private_key2]="Enter your second private key: "
      [public_key2]="Enter your second public key: "
      [Hoodi_RPC]="Hoodi RPC URL (default https://ethereum-hoodi-rpc.publicnode.com): "
    )
    for var in "${!prompts[@]}"; do
      if [[ -z "${!var:-}" ]]; then
        read -rp "${prompts[$var]}" input
        # Apply default for RPC
        [[ "$var" == "Hoodi_RPC" && -z "$input" ]] && input="https://ethereum-hoodi-rpc.publicnode.com"
        echo "$var=\"$input\"" >> "$env_file"
        declare "$var=$input"
      fi
    done
    echo "✅ Environment configured ($env_file)"
    break ;;

  "Create Trap")
    echo "--- Creating Trap ---"
    [[ -f "$env_file" ]] || error_exit "$env_file не найден. Сначала запустите 'Setup CLI & Configure Env'."
    source "$env_file"
    require_cmd forge
    require_cmd bun
    mkdir -p "$trap_dir" && cd "$trap_dir"
    git config --global user.email "$github_Email"
    git config --global user.name  "$github_Username"
    forge init -t drosera-network/trap-foundry-template  # клонирование шаблона
    bun install
    forge build
    # Insert whitelist keys
    cat >> drosera.toml <<EOF
whitelist = ["$public_key", "$public_key2"]
EOF
    # Apply existing trap address if present
    if [[ -n "${trap_address:-}" ]]; then
      sed -i "s|^address = .*|address = \"$trap_address\"|" drosera.toml
    fi
    echo "📲 Пополните баланс Holesky ETH и нажмите Enter для продолжения..."
    read -r
    DROSERA_PRIVATE_KEY="$private_key" drosera apply --eth-rpc-url "$Hoodi_RPC"
    drosera dryrun
    echo "📂 Trap создан в $trap_dir"
    cd ~
    break ;;

  "Install & Register Operators")
    echo "--- Installing & Registering Operators ---"
    [[ -f "$env_file" ]] || error_exit "$env_file не найден. Сначала 'Setup CLI & Configure Env'."
    source "$env_file"
    echo "🔄 Fetching latest operator release..."
    version=$(curl -s https://api.github.com/repos/drosera-network/releases/releases/latest | jq -r '.tag_name // "v1.20.0"')
    asset="drosera-operator-${version}-x86_64-unknown-linux-gnu.tar.gz"
    # Note: repo "releases" leads to repeated 'releases' in URL
    url="https://github.com/drosera-network/releases/releases/download/$version/$asset"
    curl -fL "$url" -o "$asset" || error_exit "Не удалось скачать $asset"
    tar -xzf "$asset" && rm -f "$asset"
    bin=$(find . -type f -name drosera-operator | head -1)
    [[ -f "$bin" ]] || error_exit "Binary не найден"
    chmod +x "$bin"
    echo "🚀 Registering operator 1"
    "$bin" register --eth-rpc-url "$Hoodi_RPC" --eth-private-key "$private_key"
    echo "🚀 Registering operator 2"
    "$bin" register --eth-rpc-url "$Hoodi_RPC" --eth-private-key "$private_key2"
    echo "✅ Registration complete"
    break ;;

  "Run Drosera")
    echo "--- Starting Drosera Operators ---"
    [[ -f "$env_file" ]] || error_exit "$env_file не найден. Сначала 'Setup CLI & Configure Env'."
    source "$env_file"
    SERVER_IP=$(hostname -I | awk '{print $1}')
    [[ -n "$SERVER_IP" ]] || error_exit "Не удалось определить IP-адрес"
    # Stop existing
    if [[ -d "$project_dir" ]]; then
      cd "$project_dir" && docker compose down -v || true && cd ~
    fi
    generate_compose
    echo "🔄 Запускаем операторы..."
    cd "$project_dir" && docker compose up -d
    echo "✅ Drosera запущен"
    cd ~
    break ;;

  "View Logs")
    docker compose -f "$compose_file" logs -f --tail=100
    break ;;

  "Update RPC URL")
    echo "--- Updating RPC URL ---"
    [[ -f "$env_file" ]] || error_exit "$env_file не найден."
    cp -n "$env_file" "${env_file}.bak"
    source "$env_file"
    echo "Текущий RPC: $Hoodi_RPC"
    read -rp "Новый RPC URL: " new_rpc
    sed -i "s|^Hoodi_RPC=.*|Hoodi_RPC=\"$new_rpc\"|" "$env_file"
    echo "✅ Hoodi_RPC обновлён"
    break ;;

  "Uninstall Drosera")
    echo "--- Uninstalling Drosera ---"
    [[ -d "$project_dir" ]] || { echo "ℹ️ $project_dir не найден"; break; }
    read -rp "Удалить все данные? [y/N] " ans
    if [[ "$ans" =~ ^[Yy]$ ]]; then
      cd "$project_dir" && docker compose down -v || true
      rm -rf "$project_dir" "$trap_dir"
      echo "✅ Удалено"
    else
      echo "❌ Отменено"
    fi
    break ;;

  "Exit")
    echo "👋 До встречи!"
    exit 0 ;;
  *)
    echo "Invalid option: $REPLY" ;;
  esac
done
