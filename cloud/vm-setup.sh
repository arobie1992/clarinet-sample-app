#!/bin/bash

create_configs() {
    local num_configs=$1
    local directory_url=$2
    local num_peers=$3
    local min_peers=$4
    local activity_period=$5
    local total_actions=$6

    local config_template='{
    \"libp2p\": {
        \"port\": $port,
        \"certPath\": \"\",
        \"dbPath\": \"file::memory:?cache=shared\"
    },
    \"admin\": {
        \"port\": $admin_port
    },
    \"sampleApp\": {
        \"directory\": \"$directory_url\",
        \"numPeers\": $num_peers,
        \"minPeers\": $min_peers,
        \"activityPeriodSecs\": $activity_period,
        \"totalActions\": $total_actions
    }
}
'

    for i in $(seq 1 $num_configs); do
        local port=$((4000+i))
        local admin_port=$((8000+i))
        local config_name="gen-config${i}.json"
        echo "creating config $config_name"
        eval "echo \"$config_template\"" > "$config_name"
    done
}

install_app() {
    if [[ -z "$(which wget)" ]]; then
        sudo apt update
        sudo apt install wget -y
    fi

    wget https://github.com/arobie1992/clarinet-sample-app/raw/main/cloud/clarinet-sample-app-linux-x86_64
    if [[ ! -f "clarinet-sample-app-linux-x86_64" ]]; then
        echo "failed to download executable"
        exit 1
    fi
    chmod +x clarinet-sample-app-linux-x86_64
}

start_nodes() {
    if [[ ! -f "clarinet-sample-app-linux-x86_64" ]]; then
        echo "app not present -- will now install"
        install_app
    fi

    for cf in gen-config*.json; do
        local qualifier="$(echo $cf | cut -f1 -d '.')"
        echo "starting $cf"
        ./clarinet-sample-app-linux-x86_64 "$cf" > "node-${qualifier}.log" 2>&1 &
        if [[ "$(ps -ef | grep "$cf" -m 1 | cut -f 2 -d ".")" != "/clarinet-sample-app-linux-x86_64 $qualifier" ]]; then
            echo "failed to start $cf"
            exit 1
        fi
    done
}

num_configs=50
directory_url=directory-vm:8080
num_peers=15
min_peers=15
activity_period=0.25
total_actions=1000

mkdir /clarinet
cd /clarinet
create_configs "$num_configs" "$directory_url" "$num_peers" "$min_peers" "$activity_period" "$total_actions"
start_nodes