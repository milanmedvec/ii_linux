#!/bin/bash

ETA_START=0
ETA_ELAPSED=0
LAST_RES=""

preexec() {
    LAST_RES=0
    ETA_START=$(date +%s)
    LAST_CMD=$1
}

precmd() {
    LAST_RES=$?
    ETA_END=$(date +%s)

    if [[ $ETA_START -gt 0 ]]
    then
        ETA_ELAPSED=$(($ETA_END-$ETA_START))
    else
        ETA_ELAPSED=0
    fi

    if [[ $LAST_RES -eq 0 ]]
    then
        if [[ $ETA_ELAPSED -gt 60 && $LAST_CMD ]]
        then
            dunstify -u low -t 3000 "Finished" "[${LAST_CMD}] in ${ETA_ELAPSED}s!"
        fi
    else
        dunstify -u critical -t 5000 "Failed" "[${LAST_CMD}] in ${ETA_ELAPSED}s!"
    fi

    LAST_CMD=""
}

source "$DIR_WORKSPACE/lib/bash-preexec/bash-preexec.sh"
