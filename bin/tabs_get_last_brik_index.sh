#!/bin/bash

# extract the index (i.e., "001" from original_brik__001+orig) from the
# last real-time dataset written to disc

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

# find the last brik with given prefix
last_brik_pefix=$(tabs_get_last_brik_prefix.sh $prefix)

# empty?! very first brik
if [ -z "$last_brik_pefix" ]; then
  echo ${prefix}_001
fi

# extract the index 
last_brik_index=$(echo ${last_brik_prefix} | sed -e "s/^${prefix}.*\([0-9][0-9][0-9]\)$/\1/")

echo $last_brik_index
