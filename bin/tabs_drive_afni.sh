#!/bin/bash

#
# wraps the plugout_drive command in a retry loop (re-tries 3 times or until success)
#

if [[ -z "$@" ]]; then
	echo "Usage: $0 <arguments> ..."
	echo "ERROR ($0): No arguments given!"
	exit 1
fi

# source tabs environment 
tabs_cfg_host_file=$(dirname $0)/../tabs_env_$(hostname).cfg
tabs_cfg_file=$(dirname $0)/../tabs_env.cfg

if [ -f $tabs_cfg_host_file ]; then
  source $tabs_cfg_host_file
elif [ -f $tabs_cfg_file ]; then
  source $tabs_cfg_file
else
  echo "${LID}: ERROR: No configuration file found!"
  exit 1
fi

# loop plugout_drive
response=""
count=0
max_count=4

while [ -z "${response}" ] && [ $count -lt $max_count ]; do
  if [ $count -gt 0 ]; then
    echo "${LID}: WARNING: retrying $(($count+1)) out of $(($max_count-1)) ***"
  fi

  response=$(plugout_drive -maxwait 2 "$@" | grep "AFNI response string: OK!")

  count=$(($count+1))
done

if [ -z "${response}" ]; then
  echo "${LID}: ERROR: plugout_dirve -maxwait 2 $@ failed!"
fi

exit 1