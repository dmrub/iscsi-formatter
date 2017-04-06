#!/bin/bash

message() {
    echo >&2 "$*"
}

infomsg() {
    message "info: bootstrap.sh: $*"
}

errmsg() {
    message "error: bootstrap.sh: $*"
}

if [ -e /usr/local/bin/bootstrap-args.sh ]; then
    source /usr/local/bin/bootstrap-args.sh
fi

infomsg "Starting iscsid ..."
supervisorctl start iscsid

usage() {
    echo "Bootstrap Script"
    echo
    echo ""
    echo "$0 [options]"
    echo "options:"
    echo "      --help      Display this help and exit"
    echo "      --portal    iSCSI portal (host [ ':' ] port)"
    echo "      --target    iSCSI target"
    echo "      --lun       iSCSI LUN"
    echo "      --format    format type (used with mkfs.type tool)"
    echo "      --force-format"
    echo "                  enforce formatting"
    echo "      --dont-exit Don't exit"
}

ISCSI_PORTAL=
ISCSI_TARGET=
ISCSI_LUN=
ISCSI_FORMAT=
ISCSI_FORCE_FORMAT=
ISCSI_DO_LOGOUT=
DONT_EXIT=

cleanup() {
    if [ "$ISCSI_DO_LOGOUT" = "true" ]; then
        iscsiadm -m node --targetname "$ISCSI_TARGET" --portal "$ISCSI_PORTAL" --logout
    fi
    if [ "$DONT_EXIT" != "true" ]; then
        supervisorctl shutdown
    fi
}

trap cleanup INT EXIT

ACTION=

while [[ $# > 0 ]]; do
    case "$1" in
        --help)
            usage
            exit
            ;;
        --discovery)
            ACTION=discovery
            shift
            ;;
        --portal)
            ISCSI_PORTAL="$2"
            shift 2
            ;;
        --portal=*)
            ISCSI_PORTAL="${1#*=}"
            shift
            ;;

        --target)
            ISCSI_TARGET="$2"
            shift 2
            ;;
        --target=*)
            ISCSI_TARGET="${1#*=}"
            shift
            ;;

        --lun)
            ISCSI_LUN="$2"
            shift 2
            ;;
        --lun=*)
            ISCSI_LUN="${1#*=}"
            shift
            ;;

        --format)
            ISCSI_FORMAT="$2"
            shift 2
            ;;
        --format=*)
            ISCSI_FORMAT="${1#*=}"
            shift
            ;;

        --force-format)
            ISCSI_FORCE_FORMAT=true
            shift
            ;;

        --dont-exit)
            DONT_EXIT=true
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

echo "ISCSI_PORTAL=$ISCSI_PORTAL"
echo "ISCSI_TARGET=$ISCSI_TARGET"

case "$ISCSI_PORTAL" in
    '')
        errmsg "iSCSI Portal is not specified"
        exit 1
        ;;
    *:*)
        # portal has a port number
        ;;
    *)
        # port number missing, we add default one
        ISCSI_PORTAL="${ISCSI_PORTAL}:3260"
        ;;
esac

# Remove discovery for specified portal
iscsiadm -m discoverydb -t st -p "$ISCSI_PORTAL" -o delete

if ! ISCSI_DISCOVERY=$(iscsiadm -m discovery -t st -p "$ISCSI_PORTAL"); then
    errmsg "Could not perform iSCSI discovery on portal $ISCSI_PORTAL"
    exit
fi

while IFS=$' \t' read -r portal_tag target; do
    portal_tag_arr=(${portal_tag//,/ })
    portal=${portal_tag_arr[0]}
    tag=${portal_tag_arr[1]}

    echo "portal=$portal"
    echo "tag=$tag"
    echo "target=$target"
    echo
done <<<"$ISCSI_DISCOVERY"

# login

if iscsiadm -m node --targetname "$ISCSI_TARGET" --portal "$ISCSI_PORTAL" --login; then
    ISCSI_DO_LOGOUT=true
else
    errmsg "Could not login to iSCSI target $ISCSI_TARGET @ portal $ISCSI_PORTAL"
    exit 1
fi

# find session

if ! ISCSI_SESSION=$(iscsiadm -m session); then
    errmsg "Could not get iSCSI sessions"
    exit
fi

trim() {
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    echo -n "$var"
}

sel_session_id=
sel_transport=
sel_target=
sel_portal=
sel_tag=

echo "iSCSI Session Info"

while IFS=: read -r transport info; do
    transport=$(trim "$transport")
    info_list=(${info//$' \t'/ })
    target=${info_list[2]}
    portal=${info_list[1]%%,*}
    tag=${info_list[1]#*,}
    case "${info_list[0]}" in
        '['*']') session_id=${info_list[0]:1:${#info_list[0]}-2} ;;
        *) session_id=
    esac

    echo "session_id=$session_id"
    echo "transport=$transport"
    echo "target=$target"
    echo "portal=$portal"
    echo "tag=$tag"

    if [ "$target" = "$ISCSI_TARGET" -a "$portal" = "$ISCSI_PORTAL" ]; then
        sel_session_id=$session_id
        sel_transport=$transport
        sel_target=$target
        sel_portal=$portal
        sel_tag=$tag
    fi
done <<<"$ISCSI_SESSION"

if [ -n "$sel_session_id" -a -n "$ISCSI_LUN" ]; then
    DISK_ID=ip-${sel_portal}-iscsi-${sel_target}-lun-"$ISCSI_LUN"
    DISK_PATH=/dev/disk/by-path/$DISK_ID

    num_tries=5
    for ((i=0; i<$num_tries; ++i)); do
        if [ -e "$DISK_PATH" ]; then
            break
        else
            infomsg "Waiting for $DISK_PATH $(($i+1))/$num_tries"
            sleep 1
        fi
    done

    if [ -e "$DISK_PATH" ]; then
        echo "Found iSCSI disk $DISK_PATH"
        DISK_INFO=$(blkid "$DISK_PATH")
        echo "Disk info: $DISK_INFO"

        if [ -n "$ISCSI_FORMAT" ]; then
            if [ -n "$DISK_INFO" -a "$ISCSI_FORCE_FORMAT" != "true" ]; then
                infomsg "iSCSI disk already formatted"
            else
                format_tool=$(type -p mkfs.$ISCSI_FORMAT)
                if [ -n "$format_tool" ]; then
                    if [ "$ISCSI_FORCE_FORMAT" = "true" ]; then
                        "$format_tool" -f "$DISK_PATH"
                    else
                        "$format_tool" "$DISK_PATH"
                    fi
                else
                    errmsg "No utility mkfs.$ISCSI_FORMAT found"
                    exit 1
                fi
            fi
        fi

    else
        echo "No such device $DISK_PATH"
        ls -Ad /dev/disk/*
        ls -Ad /dev/disk/by-path
        ls -Ad /dev/disk/by-path/ip-*-iscsi-*
    fi
fi
