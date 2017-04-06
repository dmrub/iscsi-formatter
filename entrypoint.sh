#!/bin/bash

message() {
    echo >&2 "$*"
}

infomsg() {
    message "info: entrypoint.sh: $*"
}

infomsg "EUID=$EUID args: $*"

usage() {
    echo "Entrypoint Script"
    echo
    echo ""
    echo "$0 [options]"
    echo "options:"
    echo "      --print-env            Display environment"
    echo "      --help-entrypoint      Display this help and exit"
}

while [[ $# > 0 ]]; do
    case "$1" in
        --help-entrypoint)
            usage
            exit
            ;;
        --print-env)
            env >&2
            shift
            ;;
        --)
            shift
            break
            ;;
        -*)
            break
            ;;
        *)
            break
            ;;
    esac
done

if [ -d /host/dev ]; then
    infomsg "Host device directory exists, we bind mount it to /dev"
    infomsg "mount --rbind /host/dev /dev"
    mount --rbind /host/dev /dev || exit 1
fi

write-set-args() {
    local set_cmd="set -- " arg val
    for arg in "$@"; do
        printf -v val "%q" "$arg"
        set_cmd="$set_cmd $val"
    done

    echo "$set_cmd"
}

write-set-args "$@" > /usr/local/bin/bootstrap-args.sh

mkdir -p /var/run/supervisor /var/log/supervisor || exit 1
exec /usr/bin/supervisord -c /etc/supervisord.conf
