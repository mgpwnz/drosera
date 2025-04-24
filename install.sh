#!/bin/bash

while true; do
# === Главное меню ===
PS3='Select an action: '
options=("Docker" "Setup & Deploy Trap" "Installing and configuring the Operator" "CLI operator installation" "RUN Drosera" "Logs" "Check" "Add Secondary Operator" "Uninstall" "Exit")
select opt in "${options[@]}"; do
    case $opt in

    "Docker")
        . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
        break
        ;;

        "Setup & Deploy Trap")
        # === Установка CLI ===
        curl -L https://app.drosera.io/install | bash || { echo "❌ Drosera install failed"; exit 1; }
        curl -L https://foundry.paradigm.xyz | bash || { echo "❌ Foundry install failed"; exit 1; }
        curl -fsSL https://bun.sh/install | bash || { echo "❌ Bun install failed"; exit 1; }

        # === Додаємо CLI шляхи до PATH (bashrc) ===
        for dir in "$HOME/.drosera/bin" "$HOME/.foundry/bin" "$HOME/.bun/bin"; do
            grep -qxF "export PATH=\"\$PATH:$dir\"" "$HOME/.bashrc" || echo "export PATH=\"\$PATH:$dir\"" >> "$HOME/.bashrc"
        done
        source "$HOME/.bashrc"

        # === Запускаємо оновлення CLI ===
        "$HOME/.drosera/bin/droseraup"
        "$HOME/.foundry/bin/foundryup"

        # === Завантаження або створення .env конфігурації ===
        ENV_FILE="$HOME/.env.drosera"
        [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

        if [[ -z "$github_Email" ]]; then
            read -p "Enter GitHub email: " github_Email
            echo "github_Email=\"$github_Email\"" >> "$ENV_FILE"
        fi

        if [[ -z "$github_Username" ]]; then
            read -p "Enter GitHub username: " github_Username
            echo "github_Username=\"$github_Username\"" >> "$ENV_FILE"
        fi

        if [[ -z "$private_key" ]]; then
            read -p "Enter your private key: " private_key
            echo "private_key=\"$private_key\"" >> "$ENV_FILE"
        fi

        if [[ -z "$public_key" ]]; then
            read -p "Enter your public key: " public_key
            echo "public_key=\"$public_key\"" >> "$ENV_FILE"
        fi

        if [[ -z "$Hol_RPC" ]]; then
            read -p "🌐 Holesky RPC URL (default: https://ethereum-holesky-rpc.publicnode.com): " Hol_RPC
            Hol_RPC="${Hol_RPC:-https://ethereum-holesky-rpc.publicnode.com}"
            echo "Hol_RPC=\"$Hol_RPC\"" >> "$ENV_FILE"
        fi

        echo "🔁 Используется конфигурация из $ENV_FILE"

        # === Створення і компіляція Trap ===
        mkdir -p "$HOME/my-drosera-trap"
        cd "$HOME/my-drosera-trap"

        git config --global user.email "$github_Email"
        git config --global user.name "$github_Username"

        "$HOME/.foundry/bin/forge" init -t drosera-network/trap-foundry-template
        "$HOME/.bun/bin/bun" install
        "$HOME/.foundry/bin/forge" build

        echo "📲 You'll need an EVM wallet & some Holesky ETH (0.2 - 2+)"
        read

        if [[ -n "$Hol_RPC" ]]; then
            DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply --eth-rpc-url "$Hol_RPC"
        else
            DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply
        fi
        "$HOME/.drosera/bin/drosera" dryrun
        cd "$HOME"
        break
        ;;


    "Installing and configuring the Operator")
        ENV_FILE="$HOME/.env.drosera"
        if [[ ! -f "$ENV_FILE" ]]; then
            echo "❌ Файл конфигурации $ENV_FILE не найден. Сначала запусти 'Setup & Deploy Trap'."
            exit 1
        fi
        source "$ENV_FILE"

        SERVER_IP=$(hostname -I | awk '{print $1}')
        cd "$HOME/my-drosera-trap" || { echo "❌ Директория не найдена"; exit 1; }

        sed -i '/^private/d' drosera.toml
        sed -i '/^whitelist/d' drosera.toml
        sed -i '/^\[network\]/,$d' drosera.toml

        cat >> drosera.toml <<EOF
private_trap = true
whitelist = ["$public_key"]

[network]
external_p2p_address = "$SERVER_IP"
EOF

        if [[ -n "$Hol_RPC" ]]; then
            DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply --eth-rpc-url "$Hol_RPC"
        else
            DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply
        fi
        break
        ;;

    "CLI operator installation")
        source "$HOME/.env.drosera"
        cd "$HOME"

        curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
        tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz && rm -f drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz

        # Пошук двійкового файлу після розпакування
        OPERATOR_BIN=$(find . -type f -name "drosera-operator" | head -n 1)

        if [[ ! -x "$OPERATOR_BIN" ]]; then
            chmod +x "$OPERATOR_BIN"
        fi

        echo "🚀 Виконую: $OPERATOR_BIN register ..."

        "$OPERATOR_BIN" register --eth-rpc-url "$Hol_RPC" --eth-private-key "$private_key"
        break
        ;;

    "RUN Drosera")
        source "$HOME/.env.drosera"
        SERVER_IP=$(hostname -I | awk '{print $1}')

        mkdir -p "$HOME/Drosera"
        cd "$HOME/Drosera"

        cat > docker-compose.yml <<EOF
version: '3'
services:
  drosera:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node
    ports:
      - "31313:31313"
      - "31314:31314"
    volumes:
      - drosera_data:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31313 --server-port 31314 --eth-rpc-url ${Hol_RPC} --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key ${private_key} --listen-address 0.0.0.0 --network-external-p2p-address ${SERVER_IP} --disable-dnr-confirmation true
    restart: always

volumes:
  drosera_data:
EOF

        docker compose up -d
        break
        ;;

    "Logs")
        echo "Select logs to view:"
        select logopt in "Main Operator (drosera-node)" "Secondary Operator (drosera-node2)" "Both (combined)" "Back"; do
            case $logopt in
                "Main Operator (drosera-node)")
                    docker logs -f drosera-node
                    break
                    ;;
                "Secondary Operator (drosera-node2)")
                    docker logs -f drosera-node2
                    break
                    ;;
                "Both (combined)")
                    cd "$HOME/Drosera" || { echo "❌ Drosera directory not found"; break; }
                    echo "🔎 Showing combined logs. Press Ctrl+C to stop."
                    docker compose logs -f
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

    "Check")
        IP=$(hostname -I | awk '{print $1}')
        RESPONSE=$(curl -s --location "http://$IP:31314" \
            --header 'Content-Type: application/json' \
            --data '{
                "jsonrpc": "2.0",
                "method": "drosera_healthCheck",
                "params": [],
                "id": 1
            }')
        echo "$RESPONSE" | jq
        break
        ;;
            "Add Secondary Operator")
        SERVER_IP=$(hostname -I | awk '{print $1}')
        ENV_FILE="$HOME/.env.drosera"

        # === Читаємо вже існуючі значення, якщо є ===
        [[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

        # === Зчитуємо ключі, якщо вони ще не задані ===
        if [[ -z "$private_key2" ]]; then
            read -p "Enter your private key2: " private_key2
            echo "private_key2=\"$private_key2\"" >> "$ENV_FILE"
        fi

        if [[ -z "$public_key2" ]]; then
            read -p "Enter your public key2: " public_key2
            echo "public_key2=\"$public_key2\"" >> "$ENV_FILE"
        fi

        if [[ -z "$Hol_RPC2" ]]; then
            read -p "🌐 Holesky RPC URL2 (default: https://ethereum-holesky-rpc.publicnode.com): " Hol_RPC2
            Hol_RPC2="${Hol_RPC2:-https://ethereum-holesky-rpc.publicnode.com}"
            echo "Hol_RPC2=\"$Hol_RPC2\"" >> "$ENV_FILE"
        fi

        # === Оновлюємо drosera.toml whitelist ===
        cd "$HOME/my-drosera-trap" || { echo "❌ Директория не найдена"; break; }

        sed -i '/^whitelist/d' drosera.toml
        echo "whitelist = [\"$public_key\",\"$public_key2\"]" >> drosera.toml

        # === Apply ===
        if [[ -n "$Hol_RPC" ]]; then
            DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply --eth-rpc-url "$Hol_RPC"
        else
            DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/drosera" apply
        fi

        echo "📲 You'll need an EVM wallet & some Holesky ETH (0.2 - 2+) for the second operator"
        read

        cd "$HOME"
        OPERATOR_BIN=$(find . -type f -name "drosera-operator" | head -n 1)
        [[ ! -x "$OPERATOR_BIN" ]] && chmod +x "$OPERATOR_BIN"

        echo "🚀 Виконую: $OPERATOR_BIN register ..."
        "$OPERATOR_BIN" register --eth-rpc-url "$Hol_RPC2" --eth-private-key "$private_key2"

        # Зупиняємо перший контейнер
        cd "$HOME/Drosera"
        docker compose down -v

        # Порти
        read -p "Enter P2P port for first operator (default: 31313): " P2P_PORT1
        read -p "Enter server port for first operator (default: 31314): " SERVER_PORT1
        read -p "Enter P2P port for second operator (default: 31315): " P2P_PORT2
        read -p "Enter server port for second operator (default: 31316): " SERVER_PORT2
        P2P_PORT1="${P2P_PORT1:-31313}"
        SERVER_PORT1="${SERVER_PORT1:-31314}"
        P2P_PORT2="${P2P_PORT2:-31315}"
        SERVER_PORT2="${SERVER_PORT2:-31316}"

        cat > docker-compose.yml <<EOF
version: '3'
services:
  drosera:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node
    ports:
      - "${P2P_PORT1}:31313"
      - "${SERVER_PORT1}:31314"
    volumes:
      - drosera_data:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31313 --server-port 31314 --eth-rpc-url ${Hol_RPC} --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key ${private_key} --listen-address 0.0.0.0 --network-external-p2p-address ${SERVER_IP} --disable-dnr-confirmation true
    restart: always

  drosera2:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node2
    ports:
      - "${P2P_PORT2}:31313"
      - "${SERVER_PORT2}:31314"
    volumes:
      - drosera_data2:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31313 --server-port 31314 --eth-rpc-url ${Hol_RPC2} --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key ${private_key2} --listen-address 0.0.0.0 --network-external-p2p-address ${SERVER_IP} --disable-dnr-confirmation true
    restart: always

volumes:
  drosera_data:
  drosera_data2:
EOF

        docker compose up -d
        cd $HOME
        break
        ;;


    "Uninstall")
        if [ ! -d "$HOME/Drosera" ]; then
            break
        fi
        read -r -p "Wipe all DATA? [y/N] " response
        case "$response" in
            [yY][eE][sS]|[yY])
                cd "$HOME/Drosera" && docker compose down -v
                rm -rf "$HOME/Drosera"
                ;;
            *)
                echo "❌ Операция отменена"
                ;;
        esac
        break
        ;;

    "Exit")
        exit
        ;;
    *) echo "Invalid option $REPLY" ;;
    esac

done
done
