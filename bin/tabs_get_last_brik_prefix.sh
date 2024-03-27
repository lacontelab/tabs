#!/bin/bash

#
# extract the current brik prefix (i.e., "original_brik__001" from "original_brik__001+orig.BRIK.gz")
#

# source tabs environment
tabs_cfg_host_file=$(dirname $0)/../tabs_env_$(hostname).cfg
tabs_cfg_file=$(dirname $0)/../tabs_env.cfg

if [ -f $tabs_cfg_host_file ]; then
  source $tabs_cfg_host_file
elif [ -f $tabs_cfg_file ]; then
  source $tabs_cfg_file
else
  echo "ERROR($0): No configuration file found!"
  exit 1
fi

# prefix can be specified as argument
if [ -z "$1" ]; then
  prefix=$AFNI_REALTIME_Root
else
  prefix=$1
fi

# enter data directory 
cd ${TABS_PATH}/data

# find the most recent brik
last_brik=$(ls -1rt | grep ^${prefix}.*[0-9][0-9][0-9][+]orig[.]HEAD$ | tail -n 1)

# empty?! very first brik
if [ -z "$last_brik" ]; then
  echo ${prefix}__001
else
  echo ${last_brik%%+orig.HEAD}
fi
