#!/bin/bash

docker run -ti --net=host --privileged \
           --rm \
           -v /lib/modules:/lib/modules \
           -v /dev:/host/dev \
           iscsi-formatter "$@"
