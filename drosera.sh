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
PROJECT_DIR="$HOME/Drosera"

# Функция проверки Ethereum-адреса
function is_valid_eth_address() {
  [[ $1 =~ ^0x[0-9a-fA-F]{40}$ ]]
}

# Функция для генерации docker-compose.yml с одним контейнером
function one_container() {
  mkdir -p "$PROJECT_DIR"
  cat > "$PROJECT_DIR/docker-compose.yml" <<EOF
version: '3'
services:
  drosera:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node
    network_mode: host
    volumes:
      - drosera_data:/data
    command: node --db-file-path /data/drosera.db \
                   --network-p2p-port 31313 \
                   --server-port 31314 \
                   --eth-rpc-url ${Hol_RPC} \
                   --eth-backup-rpc-url https://holesky.drpc.org \
                   --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \
                   --eth-private-key ${private_key} \
                   --listen-address 0.0.0.0 \
                   --network-external-p2p-address ${SERVER_IP} \
                   --disable-dnr-confirmation true
    restart: always

volumes:
  drosera_data:
EOF
}

# Функция для генерации docker-compose.yml с двумя контейнерами
function two_containers() {
  mkdir -p "$PROJECT_DIR"
  cat > "$PROJECT_DIR/docker-compose.yml" <<EOF
version: '3'
services:
  drosera:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node
    network_mode: host
    volumes:
      - drosera_data:/data
    command: node --db-file-path /data/drosera.db \
                   --network-p2p-port 31313 \
                   --server-port 31314 \
                   --eth-rpc-url ${Hol_RPC} \
                   --eth-backup-rpc-url https://holesky.drpc.org \
                   --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \
                   --eth-private-key ${private_key} \
                   --listen-address 0.0.0.0 \
                   --network-external-p2p-address ${SERVER_IP} \
                   --disable-dnr-confirmation true
    restart: always

  drosera2:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node2
    network_mode: host
    volumes:
      - drosera_data2:/data
    command: node --db-file-path /data/drosera.db \
                   --network-p2p-port 31315 \
                   --server-port 31316 \
                   --eth-rpc-url ${Hol_RPC2} \
                   --eth-backup-rpc-url https://holesky.drpc.org \
                   --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 \
                   --eth-private-key ${private_key2} \
                   --listen-address 0.0.0.0 \
                   --network-external-p2p-address ${SERVER_IP} \
                   --disable-dnr-confirmation true
    restart: always

volumes:
  drosera_data:
  drosera_data2:
EOF
}

PS3='Select an action: '
options=(
  "Install Dependencies"
  "Setup CLI & add env"
  "Create trap"
  "Installing and configuring the Operator"
  "CLI operator installation"
  "Update CLI operator"
  "RUN Drosera"
  "Logs"
  "Check"
  "Change rpc"
  "Cadet ROLE"
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
          curl https://raw.githubusercontent.com/drosera-network/releases/main/droseraup/install | bash || { echo "❌ Drosera install failed"; exit 1; }
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
        #"$HOME/.drosera/bin/droseraup" || { echo "❌ droseraup failed"; exit 1; }
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

        if [[ -z "${Hol_RPC:-}" ]]; then
          read -p "🌐 Holesky RPC URL (default: https://ethereum-holesky-rpc.publicnode.com): " inputHolRPC
          Hol_RPC="${inputHolRPC:-https://ethereum-holesky-rpc.publicnode.com}"
          echo "Hol_RPC=\"$Hol_RPC\"" >> "$ENV_FILE"
        fi

        read -r -p "Add secondary operator? [y/N] " add2
        if [[ "$add2" =~ ^([yY][eE][sS]|[yY])$ ]]; then
          if [[ -z "${private_key2:-}" ]]; then
            read -p "Enter your private key2: " private_key2
            echo "private_key2=\"$private_key2\"" >> "$ENV_FILE"
          fi

          if [[ -z "${public_key2:-}" ]]; then
            read -p "Enter your public key2: " public_key2
            echo "public_key2=\"$public_key2\"" >> "$ENV_FILE"
          fi

          if [[ -z "${Hol_RPC2:-}" ]]; then
            read -p "🌐 Holesky RPC URL2 (default: https://ethereum-holesky-rpc.publicnode.com): " inputHolRPC2
            Hol_RPC2="${inputHolRPC2:-https://ethereum-holesky-rpc.publicnode.com}"
            echo "Hol_RPC2=\"$Hol_RPC2\"" >> "$ENV_FILE"
          fi
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
        # Hol_RPC может быть пустым

        mkdir -p "$TRAP_DIR"
        cd "$TRAP_DIR" || { echo "❌ Не удалось зайти в $TRAP_DIR"; exit 1; }

        # Настраиваем локально git user
        git config --global user.email "$github_Email"
        git config --global user.name  "$github_Username"

        read -p "⚠️ Do you already have a trap address? [y/N]: " has_trap
        if [[ "$has_trap" =~ ^([yY][eE][sS]|[yY])$ ]]; then
          read -p "Enter existing trap address: " existing_trap
          if ! is_valid_eth_address "$existing_trap"; then
            echo "❌ Адрес невалидный"
            exit 1
          fi
          echo "address = \"$existing_trap\"" >> drosera.toml
        else
          # Клонируем шаблон, генерируем контракт
          "$HOME/.foundry/bin/forge" init -t drosera-network/trap-foundry-template
          mkdir -p src
          "$HOME/.bun/bin/bun" install
          "$HOME/.foundry/bin/forge" build

          echo "📲 You'll need an EVM wallet & some Holesky ETH (0.2 - 2+). Пополните баланс."
          read -p "Press Enter to continue…"

          if [[ -n "${Hol_RPC:-}" ]]; then
            DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply --eth-rpc-url "$Hol_RPC"
          else
            DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply
          fi
          "$HOME/.drosera/bin/drosera" dryrun
        fi

        echo "📂 Trap created in $TRAP_DIR"
        cd "$HOME"
        break
        ;;

      ############################
      "Installing and configuring the Operator")
        echo "--- Installing and configuring the Operator ---"
        if [[ ! -f "$ENV_FILE" ]]; then
          echo "❌ $ENV_FILE not found. Run 'Setup CLI & add env'."
          exit 1
        fi
        source "$ENV_FILE"
        : "${private_key:? private_key is not set in $ENV_FILE}"
        : "${public_key:? public_key is not set in $ENV_FILE}"

        SERVER_IP=$(hostname -I | awk '{print $1}')
        if [[ -z "$SERVER_IP" ]]; then
          echo "❌ Не удалось получить IP с hostname -I"
          exit 1
        fi

        if [[ ! -d "$TRAP_DIR" ]]; then
          echo "❌ $TRAP_DIR not found. Run 'Create trap' first."
          exit 1
        fi
        cd "$TRAP_DIR"

        # Удаляем существующие private_trap, whitelist и network-Strings
        sed -i '/^private_trap\s*=/d' drosera.toml
        sed -i '/^whitelist\s*=/d'    drosera.toml
        sed -i '/^\[network\]/,$d'    drosera.toml

        if [[ -z "${public_key2:-}" ]]; then
          cat >> drosera.toml <<EOF
private_trap = true
whitelist = ["$public_key"]

[network]
external_p2p_address = "$SERVER_IP"
EOF
        else
          cat >> drosera.toml <<EOF
private_trap = true
whitelist = ["$public_key", "$public_key2"]

[network]
external_p2p_address = "$SERVER_IP"
EOF
        fi

        echo "🔄 Applying drosera apply..."
        if [[ -n "${Hol_RPC:-}" ]]; then
          DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply --eth-rpc-url "$Hol_RPC"
        else
          DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply
        fi
        echo "✅ Operator configured."
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
        : "${Hol_RPC:? Hol_RPC is not set in $ENV_FILE}"

        echo "🔄 Fetching latest release from GitHub..."
        VERSION=$(curl -s https://api.github.com/repos/drosera-network/releases/releases/latest | jq -r '.tag_name')
        if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
          VERSION="v1.17.2"
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
        "$OPERATOR_BIN" register --eth-rpc-url "$Hol_RPC" --eth-private-key "$private_key"

        if [[ -n "${private_key2:-}" ]]; then
          echo "🚀 Registering second operator with public_key2=$public_key2"
          "$OPERATOR_BIN" register --eth-rpc-url "${Hol_RPC2:-$Hol_RPC}" --eth-private-key "$private_key2"
        fi

        echo "✅ CLI operator registration completed."
        break
        ;;

      ############################
      "Update CLI operator")
        echo "--- Update CLI operator ---"
        SERVER_IP=$(hostname -I | awk '{print $1}')
        if [[ -z "$SERVER_IP" ]]; then
          echo "❌ Не удалось получить IP"
          exit 1
        fi

        # Останавливаем существующие контейнеры, если есть
        if [[ -d "$PROJECT_DIR" ]]; then
          cd "$PROJECT_DIR"
          docker compose down -v || true
          cd "$HOME"
        else
          echo "ℹ️ $PROJECT_DIR not found, skipping docker compose down"
        fi

        # Получаем новую версию оператора
        VERSION=$(curl -s https://api.github.com/repos/drosera-network/releases/releases/latest | jq -r '.tag_name')
        if [ -z "$VERSION" ] || [ "$VERSION" = "null" ]; then
          VERSION="v1.17.2"
        fi
        ASSET="drosera-operator-${VERSION}-x86_64-unknown-linux-gnu.tar.gz"
        URL="https://github.com/drosera-network/releases/releases/download/${VERSION}/${ASSET}"
        echo "🔽 Downloading operator version $VERSION..."
        curl -fL "$URL" -o "$ASSET" || { echo "❌ Не удалось скачать $ASSET"; exit 1; }
        tar -xvf "$ASSET"   || { echo "❌ Не удалось распаковать $ASSET"; exit 1; }
        rm -f "$ASSET"

        echo "🔄 Updating drosera CLI..."
        curl https://raw.githubusercontent.com/drosera-network/releases/main/droseraup/install | bash || { echo "❌ Drosera install failed"; exit 1; }
        #"$HOME/.drosera/bin/droseraup" 

        echo "🔄 Pulling latest Docker image..."
        docker pull ghcr.io/drosera-network/drosera-operator:latest

        if [[ ! -f "$ENV_FILE" ]]; then
          echo "❌ $ENV_FILE not found. Run 'Setup CLI & add env'."
          exit 1
        fi
        source "$ENV_FILE"
        : "${private_key:? private_key is not set}"
        : "${public_key:? public_key is not set}"
        : "${Hol_RPC:? Hol_RPC is not set}"

        # Переходим к TRAP_DIR, чтобы обновить drosera.toml
        if [[ ! -d "$TRAP_DIR" ]]; then
          echo "❌ $TRAP_DIR not found. Run 'Create trap' first."
          exit 1
        fi
        cd "$TRAP_DIR"

        if grep -qE '^[[:space:]]*(drosera_team|drosera_rpc) = ' drosera.toml; then
          echo "🔄 Backing up drosera.toml to drosera.toml.bak"
          cp drosera.toml drosera.toml.bak

          sed -i -E 's|^[[:space:]]*drosera_team = .*|drosera_rpc = "https://relay.testnet.drosera.io"|' drosera.toml
          sed -i -E 's|^[[:space:]]*drosera_rpc = .*|drosera_rpc = "https://relay.testnet.drosera.io"|' drosera.toml

          sed -i '/^\[network\]/,$d' drosera.toml
          echo "✅ drosera.toml updated: drosera_rpc set to https://relay.testnet.drosera.io"
        else
          echo "ℹ️ drosera_team or drosera_rpc not found in drosera.toml, skipping update"
        fi

        # Применяем изменения
        DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply --eth-rpc-url "$Hol_RPC"

        # Обновляем docker-compose.yml для операторов
        if [[ -z "${private_key2:-}" ]]; then
          one_container
        else
          two_containers
        fi

        echo "🔄 Starting operator containers..."
        docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d
        echo "✅ Operator containers started."
        cd "$HOME"
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
        : "${Hol_RPC:? Hol_RPC not set in $ENV_FILE}"

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

        # Создаем/обновляем docker-compose.yml
        if [[ -z "${private_key2:-}" ]]; then
          one_container
        else
          two_containers
        fi

        echo "🔄 Starting Drosera operator..."
        docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d
        echo "✅ Drosera is up."
        cd "$HOME"
        break
        ;;

      ############################
      "Logs")
        echo "--- Logs ---"
        PS3="Select logs to view: "
        select logopt in "Main Operator (drosera-node)" "Secondary Operator (drosera-node2)" "Both (combined)" "Back"; do
          case $logopt in
            "Main Operator (drosera-node)")
              if docker ps | grep -q drosera-node; then
                docker logs -f drosera-node --tail 100
              else
                echo "❌ Контейнер drosera-node не запущен"
              fi
              break
              ;;
            "Secondary Operator (drosera-node2)")
              if docker ps | grep -q drosera-node2; then
                docker logs -f drosera-node2 --tail 100
              else
                echo "❌ Контейнер drosera-node2 не запущен"
              fi
              break
              ;;
            "Both (combined)")
              if [[ -d "$PROJECT_DIR" ]]; then
                echo "🔎 Showing combined logs. Press Ctrl+C to stop."
                docker compose -f "$PROJECT_DIR/docker-compose.yml" logs -f --tail 100
              else
                echo "❌ $PROJECT_DIR not found"
              fi
              break
              ;;
            "Back")
              break
              ;;
            *) echo "Invalid option $REPLY" ;;
          esac
        done
        break
        ;;

      ############################
      "Check")
        echo "--- Health Check ---"
        IP=$(hostname -I | awk '{print $1}')
        if [[ -z "$IP" ]]; then
          echo "❌ Не удалось получить IP"
          break
        fi

        RESPONSE=$(curl -s --location "http://$IP:31314" \
          --header 'Content-Type: application/json' \
          --data '{
            "jsonrpc": "2.0",
            "method": "drosera_healthCheck",
            "params": [],
            "id": 1
          }' || true)

        if [[ -z "$RESPONSE" ]]; then
          echo "❌ No response from http://$IP:31314"
        else
          if echo "$RESPONSE" | jq . >/dev/null 2>&1; then
            echo "$RESPONSE" | jq
          else
            echo "❌ Invalid JSON response:"
            echo "$RESPONSE"
          fi
        fi

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
        : "${Hol_RPC:? Hol_RPC is not set in $ENV_FILE}"
        echo "Current Main RPC : $Hol_RPC"
        echo "Current Secondary RPC : ${Hol_RPC2:-<not set>}"
        echo "Select RPC to change:"
        PS3="Select option: "
        select rpcopt in "Main RPC" "Secondary RPC" "Apply Host mode" "Back"; do
          case $rpcopt in
            "Main RPC")
              read -p "Enter new Main RPC URL: " newRPC
              sed -i -E "s|^Hol_RPC=.*|Hol_RPC=\"$newRPC\"|" "$ENV_FILE"
              echo "✅ Hol_RPC updated to $newRPC"
              break
              ;;
            "Secondary RPC")
              read -p "Enter new Secondary RPC URL: " newRPC2
              sed -i -E "s|^Hol_RPC2=.*|Hol_RPC2=\"$newRPC2\"|" "$ENV_FILE"
              echo "✅ Hol_RPC2 updated to $newRPC2"
              break
              ;;
            "Back")
              break
              ;;
            "Apply Host mode")
              if [[ ! -d "$PROJECT_DIR" ]]; then
                echo "❌ $PROJECT_DIR not found. Run 'RUN Drosera' first."
                break
              fi
              SERVER_IP=$(hostname -I | awk '{print $1}')
              if [[ -z "$SERVER_IP" ]]; then
                echo "❌ Не удалось получить IP"
                break
              fi
              cd "$PROJECT_DIR"
              docker compose down -v || true

              # Создаем/обновляем docker-compose.yml
              if [[ -z "${private_key2:-}" ]]; then
                one_container
              else
                two_containers
              fi

              echo "🔄 Restarting with new host mode..."
              docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d
              cd "$HOME"
              break
              ;;
            *)
              echo "Invalid option $REPLY"
              ;;
          esac
        done
        break
        ;;

      ############################
      "Cadet ROLE")
        echo "--- Cadet ROLE ---"
        if [[ ! -f "$ENV_FILE" ]]; then
          echo "❌ $ENV_FILE not found. Run 'Setup CLI & add env'."
          exit 1
        fi
        source "$ENV_FILE"
        : "${private_key:? private_key is not set in $ENV_FILE}"
        : "${public_key:? public_key is not set in $ENV_FILE}"
        : "${Hol_RPC:? Hol_RPC is not set in $ENV_FILE}"

        # Работаем в папке с “trap”
        if [[ ! -d "$TRAP_DIR" ]]; then
          echo "❌ $TRAP_DIR not found. Run 'Create trap' first."
          exit 1
        fi
        cd "$TRAP_DIR" || exit 1

        # Создаём или перезаписываем src/Trap.sol
        mkdir -p src
        read -p "Enter your discord name: " DISCORD_USERNAME
        # Очистка от нежелательных символов
        SANITIZED="${DISCORD_USERNAME//$'\n'/}"
        SANITIZED="${SANITIZED//\"/}"
        SANITIZED="${SANITIZED//\\/}"
        if [[ -z "${SANITIZED//[[:space:]]/}" ]]; then
          echo "❌ Discord name не может быть пустым."
          exit 1
        fi

        cat > src/Trap.sol <<EOF
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITrap} from "drosera-contracts/interfaces/ITrap.sol";

interface IMockResponse {
    function isActive() external view returns (bool);
}

contract Trap is ITrap {
    address public constant RESPONSE_CONTRACT = ${RESPONSE_CONTRACT:-0x4608Afa7f277C8E0BE232232265850d1cDeB600E};
    string constant discordName = "$SANITIZED";

    function collect() external view returns (bytes memory) {
        bool active = IMockResponse(RESPONSE_CONTRACT).isActive();
        return abi.encode(active, discordName);
    }

    function shouldRespond(bytes[] calldata data) external pure returns (bool, bytes memory) {
        (bool active, string memory name) = abi.decode(data[0], (bool, string));
        if (!active || bytes(name).length == 0) {
            return (false, bytes(""));
        }
        return (true, abi.encode(name));
    }
}
EOF

        # === Change toml ===
        if [[ ! -f "drosera.toml" ]]; then
          echo "❌ drosera.toml not found in $TRAP_DIR"
          exit 1
        fi

        # 1) Закомментировать старую строку и вставить новую path
        sed -i \
          's|^[[:space:]]*path = "out/HelloWorldTrap.sol/HelloWorldTrap.json"|# &\npath = "out/Trap.sol/Trap.json"|' \
          drosera.toml

        # 2) Закомментировать старую response_contract и вставить новую
        sed -i \
          's|^[[:space:]]*response_contract = "0xdA890040Af0533D98B9F5f8FE3537720ABf83B0C"|# &\nresponse_contract = "0x4608Afa7f277C8E0BE232232265850d1cDeB600E"|' \
          drosera.toml

        # 3) Закомментировать старую response_function и вставить новую
        sed -i \
          's|^[[:space:]]*response_function = "helloworld(string)"|# &\nresponse_function = "respondWithDiscordName(string)"|' \
          drosera.toml

        echo "🔨 Building trap contract..."
        "$HOME/.foundry/bin/forge" build

        echo "🔄 Running drosera dryrun..."
        "$HOME/.drosera/bin/drosera" dryrun

        echo "🔄 Applying trap changes..."
        DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply --eth-rpc-url "$Hol_RPC"

        # echo "🔍 Будем проверять isResponder каждые 60 секунд до true..."

        # # Цикл: проверяем метод isResponder, пока не станет true
        # while true; do
        #   RESPONSE=$( "$HOME/.foundry/bin/cast" call \
        #     ${RESPONSE_CONTRACT:-0x4608Afa7f277C8E0BE232232265850d1cDeB600E} \
        #     "isResponder(address)(bool)" "$public_key" \
        #     --rpc-url "$Hol_RPC" 2>/dev/null ) || RESPONSE="false"

        #   echo "📝 isResponder returned: $RESPONSE"
        #   if [[ "$RESPONSE" == "true" ]]; then
        #     echo "✅ isResponder == true — выходим из цикла и запускаем Apply Host mode."
        #     break
        #   fi

        #   echo "⏳ isResponder != true — ждём 60 секунд и проверяем снова..."
        #   sleep 60
        # done

        # === Apply Host mode после того, как isResponder стал true ===
        # echo "🔄 Запускаем Apply Host mode..."

        # SERVER_IP=$(hostname -I | awk '{print $1}')
        # if [[ -z "$SERVER_IP" ]]; then
        #   echo "❌ Не удалось получить IP"
        #   break
        # fi
        # if [[ ! -d "$PROJECT_DIR" ]]; then
        #   echo "❌ $PROJECT_DIR not found. Run 'RUN Drosera' first."
        #   break
        # fi

        # cd "$PROJECT_DIR"
        # docker compose down -v || true

        # # Создаем/обновляем docker-compose.yml
        # if [[ -z "${private_key2:-}" ]]; then
        #   one_container
        # else
        #   two_containers
        # fi

        # echo "🔄 Restarting with new host mode..."
        # docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d
        # cd "$HOME"
        #         echo "🔍 Будем проверять isResponder каждые 60 секунд до true..."

        # Цикл: проверяем метод isResponder, пока не станет true
        # while true; do
        #   RESPONSE=$( "$HOME/.foundry/bin/cast" call \
        #     ${RESPONSE_CONTRACT:-0x4608Afa7f277C8E0BE232232265850d1cDeB600E} \
        #     "isResponder(address)(bool)" "$public_key" \
        #     --rpc-url "$Hol_RPC" 2>/dev/null ) || RESPONSE="false"

        #   echo "📝 isResponder returned: $RESPONSE"
        #   if [[ "$RESPONSE" == "true" ]]; then
        #     echo "✅ isResponder == true — выходим из цикла и запускаем Apply Host mode."
        #     break
        #   fi

        #   echo "⏳ isResponder != true — ждём 60 секунд и проверяем снова..."
        #   sleep 60
        # done
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
          rm -rf "$PROJECT_DIR"
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
