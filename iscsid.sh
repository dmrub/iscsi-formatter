#!/bin/bash

message() {
    echo >&2 "$*"
}

infomsg() {
    message "info: iscsid.sh: $*"
}

INITIATORNAME_FILE=/etc/iscsi/initiatorname.iscsi

if [ -z "$IQN" ]; then
    IQN=iqn.$(date +%Y-%m).$(hostname -f | awk 'BEGIN { FS=".";}{x=NF; while (x>0) {printf $x ;x--; if (x>0) printf ".";} print ""}'):openiscsi
    IQN=${IQN}-$(echo ${RANDOM}${RANDOM}${RANDOM}${RANDOM}${RANDOM} | md5sum | sed -e "s/\(.*\) -/\1/g" -e 's/ //g')
    infomsg "Creating InitiatorName ${IQN} in ${INITIATORNAME_FILE}"
    echo "InitiatorName=${IQN}" > "${INITIATORNAME_FILE}"
fi

exec /usr/sbin/iscsid -f
