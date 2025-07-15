#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Проверяем базовые утилиты
command -v curl >/dev/null 2>&1 || { echo "❌ curl не установлен"; exit 1; }
command -v jq   >/dev/null 2>&1 || { echo "❌ jq не установлен";   exit 1; }
command -v git  >/dev/null 2>&1 || { echo "❌ git не установлен";  exit 1; }
# Проверки docker и docker compose будут в соответствующих блоках

# Пути и основные переменные
ENV_FILE="$HOME/.env.drosera"
TRAP_DIR="$HOME/my-drosera-trap"
PROJECT_DIR="$HOME/Drosera-Network"

# Функция проверки Ethereum-адреса
function is_valid_eth_address() {
  [[ $1 =~ ^0x[0-9a-fA-F]{40}$ ]]
}

# Функция для генерации docker-compose.yml с двумя контейнерами
function two_containers() {
  mkdir -p "$PROJECT_DIR"
  cat > "$PROJECT_DIR/docker-compose.yml" <<EOF
version: '3'
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

PS3='Select an action: '
options=(
  "Install Dependencies"
  "Setup CLI & add env"
  "Create trap"
  "CLI operator installation"
  "RUN Drosera"
  "Logs"
  "Change rpc"
  "Uninstall"
  "Exit"
)

while true; do
  select opt in "${options[@]}"; do
    case $opt in

      ############################
      "Install Dependencies")
        echo "--- Install Dependencies ---"
        sudo apt update && sudo apt upgrade -y
        sudo apt install -y \
          curl ufw iptables build-essential git wget lz4 jq make gcc nano \
          automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev \
          libleveldb-dev tar clang bsdmainutils ncdu unzip

        # Установка Docker (скрипт извне)
        if ! command -v docker &>/dev/null; then
          echo "🔽 Installing Docker..."
          . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
        else
          echo "ℹ️ Docker уже установлен"
        fi
        echo "✅ Dependencies installed"
        break
        ;;

      ############################
      "Setup CLI & add env")
        echo "--- Setup CLI & add env ---"

        # Устанавливаем Drosera CLI
        if ! command -v drosera &>/dev/null; then
          echo "🔽 Installing Drosera CLI..."
          curl https://app.drosera.io/install | bash || { echo "❌ Drosera install failed"; exit 1; }
        else
          echo "ℹ️ drosera CLI уже присутствует"
        fi

        # Устанавливаем Foundry
        if ! command -v forge &>/dev/null; then
          echo "🔽 Installing Foundry..."
          curl -L https://foundry.paradigm.xyz | bash || { echo "❌ Foundry install failed"; exit 1; }
        else
          echo "ℹ️ Foundry уже присутствует"
        fi

        # Устанавливаем Bun
        if ! command -v bun &>/dev/null; then
          echo "🔽 Installing Bun..."
          curl -fsSL https://bun.sh/install | bash || { echo "❌ Bun install failed"; exit 1; }
        else
          echo "ℹ️ Bun уже присутствует"
        fi

        # Поднимаем PATH в .bashrc
        for dir in "$HOME/.drosera/bin" "$HOME/.foundry/bin" "$HOME/.bun/bin"; do
          grep -qxF "export PATH=\"\$PATH:$dir\"" "$HOME/.bashrc" \
            || echo "export PATH=\"\$PATH:$dir\"" >> "$HOME/.bashrc"
        done
        source "$HOME/.bashrc"

        # Обновляем droseraup и foundryup
        #echo "🔄 Updating droseraup..."
        "$HOME/.drosera/bin/droseraup" || { echo "❌ droseraup failed"; exit 1; }
        echo "🔄 Updating foundryup..."
        "$HOME/.foundry/bin/foundryup" || { echo "❌ foundryup failed"; exit 1; }

        # Создаём/проверяем .env.drosera
        touch "$ENV_FILE"
        if [[ -f "$ENV_FILE" ]]; then
          source "$ENV_FILE"
        fi

        # Сохраняем в .env.drosera базовые переменные
        if [[ -z "${github_Email:-}" ]]; then
          read -p "Enter GitHub email: " github_Email
          echo "github_Email=\"$github_Email\"" >> "$ENV_FILE"
        fi

        if [[ -z "${github_Username:-}" ]]; then
          read -p "Enter GitHub username: " github_Username
          echo "github_Username=\"$github_Username\"" >> "$ENV_FILE"
        fi

        if [[ -z "${private_key:-}" ]]; then
          read -p "Enter your private key: " private_key
          echo "private_key=\"$private_key\"" >> "$ENV_FILE"
        fi

        if [[ -z "${public_key:-}" ]]; then
          read -p "Enter your public key: " public_key
          echo "public_key=\"$public_key\"" >> "$ENV_FILE"
        fi

        if [[ -z "${Hoodi_RPC:-}" ]]; then
          read -p "🌐 Hoodi RPC URL (default: https://ethereum-hoodi-rpc.publicnode.com): " inputHoodi_RPC
          Hoodi_RPC="${inputHoodiRPC:-https://ethereum-hoodi-rpc.publicnode.com}"
          echo "Hoodi_RPC=\"$Hoodi_RPC\"" >> "$ENV_FILE"
        fi
        # Второй адрес 
          if [[ -z "${private_key2:-}" ]]; then
            read -p "Enter your private key2: " private_key2
            echo "private_key2=\"$private_key2\"" >> "$ENV_FILE"
          fi

          if [[ -z "${public_key2:-}" ]]; then
            read -p "Enter your public key2: " public_key2
            echo "public_key2=\"$public_key2\"" >> "$ENV_FILE"
          fi
        read -p "⚠️ Do you already have a trap address? [y/N]: " has_trap
        if [[ "$has_trap" =~ ^([yY][eE][sS]|[yY])$ ]]; then
          read -p "Enter existing trap address: " trap_address
          echo "trap_address=\"$existing_trap\"" >> "$ENV_FILE"
        fi
        echo "🔁 Using conf $ENV_FILE"
        break
        ;;

      ############################
      "Create trap")
        echo "--- Create trap ---"
        if [[ ! -f "$ENV_FILE" ]]; then
          echo "❌ $ENV_FILE not found. Run 'Setup CLI & add env'."
          exit 1
        fi
        source "$ENV_FILE"
        : "${github_Email:? github_Email is not set in $ENV_FILE}"
        : "${github_Username:? github_Username is not set in $ENV_FILE}"
        : "${private_key:? private_key is not set in $ENV_FILE}"
        : "${public_key:? public_key is not set in $ENV_FILE}"
        # Hoodi_RPC может быть пустым

        mkdir -p "$TRAP_DIR"
        cd "$TRAP_DIR" || { echo "❌ Не удалось зайти в $TRAP_DIR"; exit 1; }

        # Настраиваем локально git user
        git config --global user.email "$github_Email"
        git config --global user.name  "$github_Username"
        # Клонируем шаблон, генерируем контракт
        "$HOME/.foundry/bin/forge" init -t drosera-network/trap-foundry-template
        # mkdir -p src
        "$HOME/.bun/bin/bun" install
        "$HOME/.foundry/bin/forge" build

        # Добавляем в whitelist значение public_key и public_key2
        cat >> drosera.toml <<EOF
whitelist = ["$public_key", "$public_key2"]
EOF
        # Проверяем, есть ли уже trap_address
        if [[ -z "${existing_trap:-}" ]]; then
          sed -i "s|^address = .*|address = \"$existing_trap\"|" drosera.toml
        fi
          # Создаём новый trap
          echo "📲 You'll need an EVM wallet & some Holesky ETH (0.2 - 2+). Пополните баланс."
          read -p "Press Enter to continue…"

          if [[ -n "${Hoodi_RPC:-}" ]]; then
            DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply --eth-rpc-url "$Hoodi_RPC"
          else
            DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply
          fi
          "$HOME/.drosera/bin/drosera" dryrun

        echo "📂 Trap created in $TRAP_DIR"
        cd "$HOME"
        break
        ;;

      ############################
      "CLI operator installation")
        echo "--- CLI operator installation ---"
        if [[ ! -f "$ENV_FILE" ]]; then
          echo "❌ $ENV_FILE not found. Run 'Setup CLI & add env'."
          exit 1
        fi
        source "$ENV_FILE"
        : "${private_key:? private_key is not set in $ENV_FILE}"
        : "${public_key:? public_key is not set in $ENV_FILE}"
        : "${Hoodi_RPC:? Hoodi_RPC is not set in $ENV_FILE}"

        echo "🔄 Fetching latest release from GitHub..."
        VERSION=$(curl -s https://api.github.com/repos/drosera-network/releases/releases/latest | jq -r '.tag_name')
        if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
          VERSION="v1.20.0"
        fi
        ASSET="drosera-operator-${VERSION}-x86_64-unknown-linux-gnu.tar.gz"
        URL="https://github.com/drosera-network/releases/releases/download/${VERSION}/${ASSET}"

        echo "🔽 Downloading $URL..."
        curl -fL "$URL" -o "$ASSET" || { echo "❌ Не удалось скачать $ASSET"; exit 1; }
        tar -xvf "$ASSET" || { echo "❌ Не удалось распаковать $ASSET"; exit 1; }
        rm -f "$ASSET"

        OPERATOR_BIN=$(find . -type f -name "drosera-operator" | head -n 1)
        if [[ -z "${OPERATOR_BIN:-}" || ! -f "$OPERATOR_BIN" ]]; then
          echo "❌ drosera-operator binary not found after extraction"
          exit 1
        fi
        chmod +x "$OPERATOR_BIN"

        echo "🚀 Registering operator with public_key=$public_key"
        "$OPERATOR_BIN" register --eth-rpc-url "$Hoodi_RPC" --eth-private-key "$private_key"
        sleep 20
        echo "🚀 Registering second operator with public_key2=$public_key2"
        "$OPERATOR_BIN" register --eth-rpc-url "$Hoodi_RPC" --eth-private-key "$private_key2"

        echo "✅ CLI operator registration completed."
        break
        ;;

      ############################
      "RUN Drosera")
        echo "--- RUN Drosera ---"
        if [[ ! -f "$ENV_FILE" ]]; then
          echo "❌ $ENV_FILE not found. Run 'Setup CLI & add env'."
          exit 1
        fi
        source "$ENV_FILE"
        : "${private_key:? private_key not set in $ENV_FILE}"
        : "${public_key:? public_key not set in $ENV_FILE}"
        : "${Hoodi_RPC:? Hoodi_RPC not set in $ENV_FILE}"

        SERVER_IP=$(hostname -I | awk '{print $1}')
        if [[ -z "$SERVER_IP" ]]; then
          echo "❌ Не удалось получить IP"
          exit 1
        fi

        # Предварительно остановим старые контейнеры, если есть
        if [[ -d "$PROJECT_DIR" ]]; then
          cd "$PROJECT_DIR"
          docker compose down -v || true
          cd "$HOME"
        fi
        # Создаем два контейнера
        two_containers

        echo "🔄 Starting Drosera operator..."
        docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d
        echo "✅ Drosera is up."
        cd "$HOME"
        break
        ;;

      ############################
      "Logs")
        docker compose -f "$PROJECT_DIR/docker-compose.yml" logs -f --tail 100
        break
        ;;

      ############################
      "Change rpc")
        echo "--- Change RPC ---"
        if [[ ! -f "$ENV_FILE" ]]; then
          echo "❌ $ENV_FILE not found. Run 'Setup CLI & add env'."
          exit 1
        fi

        if [[ ! -f "${ENV_FILE}.bak" ]]; then
          cp "$ENV_FILE" "${ENV_FILE}.bak"
          echo "🔄 Backup created at ${ENV_FILE}.bak"
        else
          echo "🔄 Backup already exists at ${ENV_FILE}.bak"
        fi

        source "$ENV_FILE"
        : "${Hoodi_RPC:? Hoodi_RPC is not set in $ENV_FILE}"
        echo "Current RPC : $Hoodi_RPC"
        
              read -p "Enter new RPC URL: " newRPC
              sed -i -E "s|^Hoodi_RPC=.*|Hoodi_RPC=\"$newRPC\"|" "$ENV_FILE"
              echo "✅ Hoodi_RPC updated to $newRPC"

        break
        ;;


      ############################
      "Uninstall")
        echo "--- Uninstall ---"
        if [[ ! -d "$PROJECT_DIR" ]]; then
          echo "ℹ️ $PROJECT_DIR не найден, ничего удалять не нужно"
          break
        fi

        read -r -p "Wipe all DATA? [y/N] " should_wipe
        if [[ "$should_wipe" =~ ^([yY][eE][sS]|[yY])$ ]]; then
          cd "$PROJECT_DIR"
          docker compose down -v || true
          cd "$HOME"
          rm -rf "$PROJECT_DIR" "$TRAP_DIR"
          echo "✅ Drosera directory удалена"
        else
          echo "❌ Cancelled. Drosera directory не удалена."
        fi
        break
        ;;

      ############################
      "Exit")
        echo "👋 Goodbye!"
        exit
        ;;
      *)
        echo "Invalid option $REPLY"
        ;;
    esac
  done
done
