#!/bin/bash

if [[ -z "$(which docker)" ]]; then
    echo "Please install Docker"
    exit 1
fi

# get the architecture
if [[ "$(uname)" = "Darwin" ]]; then
    arch="$(uname -m)"
else
    arch="$(uname -i)"
fi

if [[ "$arch" != "x86_64" ]]; then
    echo "The architecture is not x86_64, which is the expected architecture for Ubuntu cloud VMs. I'll still build it, but be warned this may not be what you want."
fi

pushd "$(dirname $0)" >> /dev/null

cd ..

# build it on linux
docker run -v $(pwd):/app golang:1.21.4 /bin/bash -c "cd /app && go build"

# rename it so I know which one it is
mv clarinet-sample-app cloud/clarinet-sample-app-linux-${arch}

popd >> /dev/null