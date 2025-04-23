#!/bin/bash

while true; do
# === Главное меню ===
PS3='Select an action: '
options=("Docker" "Setup & Deploy Trap" "Installing and configuring the Operator" "CLI operator installation" "RUN Drosera" "Logs" "Uninstall" "Exit")
select opt in "${options[@]}"; do
    case $opt in

    "Docker")
        . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
        break
        ;;

    "Setup & Deploy Trap")
        # Drosera CLI
        curl -L https://app.drosera.io/install | bash || { echo "❌ Drosera install failed"; exit 1; }
        # Foundry CLI
        curl -L https://foundry.paradigm.xyz | bash || { echo "❌ Foundry install failed"; exit 1; }
        # Bun
        curl -fsSL https://bun.sh/install | bash || { echo "❌ Bun install failed"; exit 1; }

        # Add to PATH if not already present
        for dir in "$HOME/.drosera/bin" "$HOME/.foundry/bin" "$HOME/.bun/bin"; do
            grep -qxF "export PATH=\"\$PATH:$dir\"" "$HOME/.bashrc" || echo "export PATH=\"\$PATH:$dir\"" >> "$HOME/.bashrc"
        done
        source "$HOME/.bashrc"

        bash -c "droseraup"
        bash -c "foundryup"

        ENV_FILE="$HOME/.env.drosera"

        if [[ -f "$ENV_FILE" ]]; then
            source "$ENV_FILE"
            echo "🔁 Используется конфигурация из $ENV_FILE"
        else
            read -p "Enter GitHub email: " github_Email
            read -p "Enter GitHub username: " github_Username
            read -p "Enter your private key: " private_key
            read -p "Enter your public key: " public_key
            read -p "🌐 Holesky RPC URL (default: https://ethereum-holesky-rpc.publicnode.com): " Hol_RPC
            Hol_RPC="${Hol_RPC:-https://ethereum-holesky-rpc.publicnode.com}"

cat > "$ENV_FILE" <<EOF
github_Email="$github_Email"
github_Username="$github_Username"
private_key="$private_key"
public_key="$public_key"
Hol_RPC="$Hol_RPC"
EOF

            echo "💾 Конфигурация сохранена в $ENV_FILE"
        fi

        for dir in "$HOME/.foundry/bin" "$HOME/.drosera/bin" "$HOME/.bun/bin"; do
            grep -qxF "export PATH=\"\$PATH:$dir\"" "$HOME/.bashrc" || echo "export PATH=\"\$PATH:$dir\"" >> "$HOME/.bashrc"
        done
        source "$HOME/.bashrc"

        mkdir -p "$HOME/my-drosera-trap"
        cd "$HOME/my-drosera-trap"

        git config --global user.email "$github_Email"
        git config --global user.name "$github_Username"

        forge init -t drosera-network/trap-foundry-template
        forge build

        echo "📢 You'll need an EVM wallet & some Holesky ETH (0.2 - 2+)"
        read

        DROSERA_PRIVATE_KEY="$private_key" drosera apply

        cd "$HOME"
        break
        ;;

    "Installing and configuring the Operator")
        ENV_FILE="$HOME/.env.drosera"
        if [[ ! -f "$ENV_FILE" ]]; then
            echo "❌ Файл конфигурации $ENV_FILE не найден. Сначала запусти 'Deploy Trap'."
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

        DROSERA_PRIVATE_KEY="$private_key" drosera apply
        break
        ;;

    "CLI operator installation")
        source "$HOME/.env.drosera"
        cd "$HOME"
        curl -LO https://github.com/drosera-network/releases/releases/download/v1.16.2/drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
        tar -xvf drosera-operator-v1.16.2-x86_64-unknown-linux-gnu.tar.gz
        docker pull ghcr.io/drosera-network/drosera-operator:latest
        drosera-operator register --eth-rpc-url "$Hol_RPC" --eth-private-key "$private_key"
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
        docker logs -f drosera-node
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
