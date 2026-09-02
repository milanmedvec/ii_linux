#!/bin/bash

alias mkdir_today="mkdir -p $TODAY"
alias mkdir_today_hash="mkdir -p $HOME/tmp/$TODAY-`shuf -i 1-100 -n 1`"
alias cdd="cd $HOME/Downloads"
alias cdw="cd ${DIR_WORKDIR}"
alias tmp="mkdir -p '${DIR_TODAY_HOME}/tmp'; cd ${DIR_TODAY_HOME}/tmp"
alias tmpt='mkdir_today_hash; cd $_'
