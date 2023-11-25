#!/bin/bash

validate_go() {
    if [[ "$(go version)" = "go version go1.21.4 linux/amd64" ]]; then
        echo "OK"
    else
        echo "FAILED"
    fi
}

setup_go() {
    sudo add-apt-repository ppa:longsleep/golang-backports -y
    sudo apt update
    sudo apt install golang -y

    if [[ "$(validate_go)" != "OK" ]]; then
        echo "Failed to install Go"
        exit 1
    fi
}

install_app() {
    if [[ -z "$(which git)" ]]; then
        sudo apt update
        sudo apt install git -y
    fi

    git clone https://github.com/arobie1992/clarinet-sample-app.git
}

build_app() {
    if [[ "$(validate_go)" != "OK" ]]; then
        setup_go
    fi

    if [[ ! -d "clarinet-sample-app" ]]; then
        install_app
    fi

    cd clarinet-sample-app/
    go build
}

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
        eval "echo \"$config_template\"" > "gen-config${i}.json"
    done
}

start_nodes() {
    if [[ -z "$(ls clarinet-sample-app/clarinet-sample-app)" ]];
        build_app
    fi

    for cf in ./gen-config*.json; do
        clarinet-sample-app/clarinet-sample-app "$cf" > "node-${cf}.log" 2>&1 &
    done
}

num_configs=3
directory_url=directory-vm:8080
num_peers=5
min_peers=2
activity_period=5
total_actions=10

create_configs 2 "directory:8080" 10 5 5 1000
start_nodes
