#!/bin/bash

alias dps='docker ps'
alias dstop='docker stop `docker ps -q`'
alias dkill='docker kill `docker ps -q`'

dexec1() {
    docker exec -it `docker ps | tail -n 1 | awk '{ print $1 }'` sh
}

dexec() {
    docker exec -it $1 sh
}
