#!/bin/sh

export TODAY=`date '+%Y-%m-%d'`
export DIR_WORKDIR="$HOME/_workdir"
export DIR_WORKSPACE="${DIR_WORKDIR}/workspace"
export DIR_DATA="${DIR_WORKSPACE}/data"
export DIR_DAILY_HOME="${DIR_WORKDIR}/daily-home"
export DIR_TODAY_HOME="${DIR_DAILY_HOME}/${TODAY}"

export PATH="$PATH:$DIR_WORKSPACE/bin:$HOME/.local/bin"
