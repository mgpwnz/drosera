#!/bin/bash

while true; do
# === MAIN ===
PS3='Select an action: '
options=("Install Dependencies" "Setup CLI & add env" "Create trap" "Installing and configuring the Operator" "CLI operator installation" "RUN Drosera" "Logs" "Check" "Change rpc" "Update CLI operator" "Uninstall" "Exit")
select opt in "${options[@]}"; do
    case $opt in

    "Install Dependencies")
        # === Install dependencies ===
        sudo apt-get update && sudo apt-get upgrade -y
        sudo apt install curl ufw iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev  -y
        # === Install Docker ===
        . <(wget -qO- https://raw.githubusercontent.com/mgpwnz/VS/main/docker.sh)
        break
        ;;

    "Setup CLI & add env")
        curl -L https://app.drosera.io/install | bash || { echo "❌ Drosera install failed"; exit 1; }
        curl -L https://foundry.paradigm.xyz | bash || { echo "❌ Foundry install failed"; exit 1; }
        curl -fsSL https://bun.sh/install | bash || { echo "❌ Bun install failed"; exit 1; }

        for dir in "$HOME/.drosera/bin" "$HOME/.foundry/bin" "$HOME/.bun/bin"; do
          grep -qxF "export PATH=\"\$PATH:$dir\"" "$HOME/.bashrc" || echo "export PATH=\"\$PATH:$dir\"" >> "$HOME/.bashrc"
        done
        source "$HOME/.bashrc"

        "$HOME/.drosera/bin/droseraup"
        "$HOME/.foundry/bin/foundryup"

        ENV_FILE="$HOME/.env.drosera"
        touch "$ENV_FILE"
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

        read -r -p "Add secondary operator? [y/N] " response
        if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
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
        fi

        echo "🔁 Using conf $ENV_FILE"
        break
        ;;

    "Create trap")
        ENV_FILE="$HOME/.env.drosera"
        if [[ ! -f "$ENV_FILE" ]]; then
          echo "❌ $ENV_FILE not found. Run 'Setup CLI & add env'."
          exit 1
        fi
        source "$ENV_FILE"

        mkdir -p "$HOME/my-drosera-trap"
        cd "$HOME/my-drosera-trap"

        git config --global user.email "$github_Email"
        git config --global user.name "$github_Username"

        "$HOME/.foundry/bin/forge" init -t drosera-network/trap-foundry-template
        "$HOME/.bun/bin/bun" install
        "$HOME/.foundry/bin/forge" build

        echo "📲 You'll need an EVM wallet & some Holesky ETH (0.2 - 2+)"
        read -p "Press Enter to continue..."

        if [[ -n "$Hol_RPC" ]]; then
          DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/droseraup" apply --eth-rpc-url "$Hol_RPC"
        else
          DROSERA_PRIVATE_KEY="$private_key" "$HOME/.drosera/bin/droseraup" apply
        fi

        "$HOME/.drosera/bin/drosera" dryrun
        cd "$HOME"
        break
        ;;

    "Installing and configuring the Operator")
        ENV_FILE="$HOME/.env.drosera"
        if [[ ! -f "$ENV_FILE" ]]; then
            echo "❌ $ENV_FILE not found. Run 'Setup & Deploy Trap'."
            exit 1
        fi
        source "$ENV_FILE"

        SERVER_IP=$(hostname -I | awk '{print $1}')
        cd "$HOME/my-drosera-trap" || { echo "❌ Drosera directory not found"; exit 1; }

        sed -i '/^private/d' drosera.toml
        sed -i '/^whitelist/d' drosera.toml
        sed -i '/^\[network\]/,$d' drosera.toml
        if [[ -z "$public_key2" ]]; then
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
        # === Apply ===
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

        # === Check ver ===
        VERSION=$(curl -s https://api.github.com/repos/drosera-network/releases/releases/latest \
        | jq -r '.tag_name')

        ASSET="drosera-operator-${VERSION}-x86_64-unknown-linux-gnu.tar.gz"
        URL="https://github.com/drosera-network/releases/releases/download/${VERSION}/${ASSET}"

        curl -L "$URL" -o "$ASSET"
        tar -xvf "$ASSET"
        rm -f "$ASSET"

        OPERATOR_BIN=$(find . -type f -name "drosera-operator" | head -n 1)

        if [[ ! -x "$OPERATOR_BIN" ]]; then
            chmod +x "$OPERATOR_BIN"
        fi

        echo "🚀 Running: $OPERATOR_BIN register ..."

        "$OPERATOR_BIN" register --eth-rpc-url "$Hol_RPC" --eth-private-key "$private_key"
        if [[ -n "$private_key2" ]]; then
            echo "🚀 Running: $OPERATOR_BIN register ... for second key"
            "$OPERATOR_BIN" register --eth-rpc-url "$Hol_RPC2" --eth-private-key "$private_key2"
        fi
        break
        ;;

    "Update CLI operator")
        SERVER_IP=$(hostname -I | awk '{print $1}')
        cd "$HOME/Drosera"
        docker compose down -v
        cd "$HOME"
        # === Check ver ===
        VERSION=$(curl -s https://api.github.com/repos/drosera-network/releases/releases/latest \
        | jq -r '.tag_name')

        ASSET="drosera-operator-${VERSION}-x86_64-unknown-linux-gnu.tar.gz"
        URL="https://github.com/drosera-network/releases/releases/download/${VERSION}/${ASSET}"

        curl -L "$URL" -o "$ASSET"
        tar -xvf "$ASSET"
        rm -f "$ASSET"

        echo " $VERSION"

        curl -L https://app.drosera.io/install | bash || { echo "❌ Drosera install failed"; exit 1; }

        docker pull ghcr.io/drosera-network/drosera-operator:latest

        ENV_FILE="$HOME/.env.drosera"
        if [[ ! -f "$ENV_FILE" ]]; then
            echo "❌ $ENV_FILE not found. Run 'Setup & Deploy Trap'."
            exit 1
        fi
        source "$ENV_FILE"

        cd "$HOME/my-drosera-trap" || { echo "❌Drosera directory not found"; exit 1; }
                
        # === Update drosera.toml whitelist entries ===
        if grep -qE '^(drosera_team|drosera_rpc) = ' drosera.toml; then
            # backup original file
            cp drosera.toml drosera.toml.bak

            # replace drosera_team or drosera_rpc with the desired RPC endpoint
            sed -i -e 's|^drosera_team = .*|drosera_rpc = "https://relay.testnet.drosera.io"|' \
                -e 's|^drosera_rpc = .*|drosera_rpc = "https://relay.testnet.drosera.io"|' \
                drosera.toml
            sed -i '/^\[network\]/,$d' drosera.toml
            sed -i '/^external_p2p_address/,$d' drosera.toml
            echo "✅ drosera.toml updated: drosera_rpc set to https://relay.testnet.drosera.io"
        else
            echo "ℹ️ drosera_team or drosera_rpc not found in drosera.toml, skipping update"
        fi

        if [[ -n "$Hol_RPC" ]]; then
            DROSERA_PRIVATE_KEY="$private_key" \
            "$HOME/.drosera/bin/drosera" apply --eth-rpc-url "$Hol_RPC"
        else
            DROSERA_PRIVATE_KEY="$private_key" \
            "$HOME/.drosera/bin/drosera" apply
        fi

        cd "$HOME/Drosera"
        # Create new docker-compose.yml with updated configuration
        if [[ -z "$private_key2" ]]; then
            
        cat > docker-compose.yml <<EOF
version: '3'
services:
  drosera:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node
    network_mode: host
    volumes:
      - drosera_data:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31313 --server-port 31314 --eth-rpc-url ${Hol_RPC} --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key ${private_key} --listen-address 0.0.0.0 --network-external-p2p-address ${SERVER_IP} --disable-dnr-confirmation true
    restart: always

  drosera2:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node2
    network_mode: host
    volumes:
      - drosera_data2:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31315 --server-port 31316 --eth-rpc-url ${Hol_RPC2} --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key ${private_key2} --listen-address 0.0.0.0 --network-external-p2p-address ${SERVER_IP} --disable-dnr-confirmation true
    restart: always

volumes:
  drosera_data:
  drosera_data2:
EOF
        else
                cat > docker-compose.yml <<EOF
version: '3'
services:
  drosera:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node
    network_mode: host
    volumes:
      - drosera_data:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31313 --server-port 31314 --eth-rpc-url ${Hol_RPC} --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key ${private_key} --listen-address 0.0.0.0 --network-external-p2p-address ${SERVER_IP} --disable-dnr-confirmation true
    restart: always

volumes:
  drosera_data:
EOF
        fi
        # === Start the operator ===
        docker compose up -d
        cd "$HOME"
        break
        ;;

    "RUN Drosera")
        source "$HOME/.env.drosera"
        SERVER_IP=$(hostname -I | awk '{print $1}')

        mkdir -p "$HOME/Drosera"
        cd "$HOME/Drosera"
        # Create new docker-compose.yml with updated configuration
        if [[ -z "$private_key2" ]]; then
            
        cat > docker-compose.yml <<EOF
version: '3'
services:
  drosera:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node
    network_mode: host
    volumes:
      - drosera_data:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31313 --server-port 31314 --eth-rpc-url ${Hol_RPC} --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key ${private_key} --listen-address 0.0.0.0 --network-external-p2p-address ${SERVER_IP} --disable-dnr-confirmation true
    restart: always

volumes:
  drosera_data:
EOF
        else
            cat > docker-compose.yml <<EOF
version: '3'
services:
  drosera:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node
    network_mode: host
    volumes:
      - drosera_data:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31313 --server-port 31314 --eth-rpc-url ${Hol_RPC} --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key ${private_key} --listen-address 0.0.0.0 --network-external-p2p-address ${SERVER_IP} --disable-dnr-confirmation true
    restart: always

  drosera2:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node2
    network_mode: host
    volumes:
      - drosera_data2:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31315 --server-port 31316 --eth-rpc-url ${Hol_RPC2} --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key ${private_key2} --listen-address 0.0.0.0 --network-external-p2p-address ${SERVER_IP} --disable-dnr-confirmation true
    restart: always

volumes:
  drosera_data:
  drosera_data2:
EOF
        fi
        docker compose up -d
        break
        ;;

    "Logs")
        echo "Select logs to view:"
        select logopt in "Main Operator (drosera-node)" "Secondary Operator (drosera-node2)" "Both (combined)" "Back"; do
            case $logopt in
                "Main Operator (drosera-node)")
                    docker logs -f drosera-node --tail 100
                    break
                    ;;
                "Secondary Operator (drosera-node2)")
                    docker logs -f drosera-node2 --tail 100
                    break
                    ;;
                "Both (combined)")
                    cd "$HOME/Drosera" || { echo "❌ Drosera directory not found"; break; }
                    echo "🔎 Showing combined logs. Press Ctrl+C to stop."
                    docker compose logs -f --tail 100
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

    "Change rpc")
        ENV_FILE="$HOME/.env.drosera"
        if [[ -f "$ENV_FILE" ]]; then
            if [[ ! -f "${ENV_FILE}.bak" ]]; then
                cp "$ENV_FILE" "${ENV_FILE}.bak"
                echo "🔄 Backup created at ${ENV_FILE}.bak"
            else
                echo "🔄 Backup already exists at ${ENV_FILE}.bak"
            fi
        else
            echo "❌ $ENV_FILE not found. Run 'Setup & Deploy Trap'."
            exit 1
        fi
        source "$ENV_FILE"
        echo "Current Main RPC: $Hol_RPC"
        echo "Current Secondary RPC: $Hol_RPC2"
        echo "Select RPC to change:"
        select rpcopt in "Main RPC" "Secondary RPC" "Apply Host mode" "Back"; do
            case $rpcopt in
                "Main RPC")
                    read -p "Enter new Main RPC URL: " Hol_RPC
                    sed -i "s|^Hol_RPC=.*|Hol_RPC=\"$Hol_RPC\"|" "$ENV_FILE"
                    break
                    ;;
                "Secondary RPC")
                    read -p "Enter new Secondary RPC URL: " Hol_RPC2
                    sed -i "s|^Hol_RPC2=.*|Hol_RPC2=\"$Hol_RPC2\"|" "$ENV_FILE"
                    break
                    ;;
                "Back")
                    break
                    ;;
                "Apply Host mode")
                    cd "$HOME/Drosera"
                    SERVER_IP=$(hostname -I | awk '{print $1}')
                    docker compose down -v
                    cat > docker-compose.yml <<EOF
version: '3'
services:
  drosera:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node
    network_mode: host
    volumes:
      - drosera_data:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31313 --server-port 31314 --eth-rpc-url ${Hol_RPC} --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key ${private_key} --listen-address 0.0.0.0 --network-external-p2p-address ${SERVER_IP} --disable-dnr-confirmation true
    restart: always

  drosera2:
    image: ghcr.io/drosera-network/drosera-operator:latest
    container_name: drosera-node2
    network_mode: host
    volumes:
      - drosera_data2:/data
    command: node --db-file-path /data/drosera.db --network-p2p-port 31315 --server-port 31316 --eth-rpc-url ${Hol_RPC2} --eth-backup-rpc-url https://holesky.drpc.org --drosera-address 0xea08f7d533C2b9A62F40D5326214f39a8E3A32F8 --eth-private-key ${private_key2} --listen-address 0.0.0.0 --network-external-p2p-address ${SERVER_IP} --disable-dnr-confirmation true
    restart: always

volumes:
  drosera_data:
  drosera_data2:
EOF

                    docker compose up -d
                    cd $HOME
                    break
                    ;;
                *) echo "Invalid option $REPLY" ;;
            esac
        done
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

            * )
                echo "❌ Cancelled"
                echo "Drosera directory not removed."
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
