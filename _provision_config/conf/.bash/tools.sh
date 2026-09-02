#!/bin/bash

alias json='python3 -m json.tool'
alias blank_image='convert -size 32x32 xc:white empty.jpg'
alias qr='zbarimg'
alias usage="du -sh ./* | sort -h"
alias lshw1='lshw -short -C memory'

port_inspect() {
    netstat -ltnp | grep $1
}

p_name() {
    ps -p $1 -o comm=
}

repeat() {
    while true; do $@; sleep 1; done
}

top1() {
    top -p `pgrep $1`
}

top0() {
    top -b -o %MEM -n 1 | grep -v chrome | head -n 55
}

e() {
    xe $1 &
}
