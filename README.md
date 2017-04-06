# iscsi-formatter

Build
-----

    docker build -t iscsi-formatter .

Run
---

    docker run -ti --net=host --privileged \
           --rm \
           -v /lib/modules:/lib/modules \
           -v /dev:/host/dev \
           iscsi-formatter "$@"

Options
-------

    --portal    iSCSI portal (host [ ':' ] port)
    --target    iSCSI target
    --lun       iSCSI LUN
    --format    format type (used with mkfs.type tool)
    --force-format
                enforce formatting
    --dont-exit Don't exit
