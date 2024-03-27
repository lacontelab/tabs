#!/bin/bash

#
# default mask processing for EPI data after is has been acquired (post)
#

# default args
show_overlay=1

# check args
if [ ! -z "$@" ]; then
  for arg in "$@"; do
    if [[ "$arg" == "-no_overlay" ]]; then
      show_overlay=0
    fi
  done
fi

# source environment
# TABS_PATH and other important variables are defined in tabs_env.cfg
tabs_cfg_host_file=$(dirname $0)/../tabs_env_$(hostname).cfg
tabs_cfg_file=$(dirname $0)/../tabs_env.cfg

if [ -f $tabs_cfg_host_file ]; then
  source $tabs_cfg_host_file
elif [ -f $tabs_cfg_file ]; then
  source $tabs_cfg_file
else
  echo "ERROR ($0): No configuration file found!"
  exit 1
fi

# enter data directory for further processing
cd ${TABS_PATH}/data

# get last brik prefix 
last_brik_prefix=$(tabs_get_last_brik_prefix.sh)

# wait for dataset to be written to disk 
count=0
max_count=5
while [ ! -f "${last_brik_prefix}+orig.HEAD" ] && [ $count -lt $max_count ]; do
  count=$(($count+1))
  echo "${LID}: INFO: Waiting for mask brik: ${last_brik_prefix}+orig.HEAD (${count}s out of ${max_count}s)"
  last_brik_prefix=$(tabs_get_last_brik_prefix.sh)
  sleep 1
done

# wait another second after .HEAD has been written for .BRIK
if [ -f "${last_brik_prefix}+orig.HEAD" ]; then 
  sleep 1
else
  echo "${LID}: ERROR: mask brik: ${last_brik_prefix}+orig.HEAD was not written to disk. Abort..."
  exit 1
fi

# calculate mean
mean_brik_prefix=$(echo ${last_brik_prefix} | sed -e "s/original_/mean_/")

echo "${LID}: INFO: Calculating mean: ${mean_brik_prefix} for ${last_brik_prefix}+orig"
3dTstat -mean -prefix ${mean_brik_prefix} ${last_brik_prefix}+orig
if [ $? -ne 0 ]; then
  echo "${LID}: ERROR: Calculating mean failed!"
fi

# calculate mask
mask_brik_prefix=$(echo ${last_brik_prefix} | sed -e "s/original_/mask_/")

echo "${LID}: INFO: Calculating mask: ${mask_brik_prefix} for ${last_brik_prefix}+orig"
3dAutomask  -prefix ${mask_brik_prefix} ${last_brik_prefix}+orig
if [ $? -ne 0 ]; then
  echo "${LID}: ERROR: Mask failed! Abort..."
  exit 1
fi

# copy origin
echo "${LID}: INFO: Copying origin from: ${last_brik_prefix}+orig to ${mask_brik_prefix}+orig"
3drefit -duporigin ${last_brik_prefix}+orig ${mask_brik_prefix}+orig
if [ $? -ne 0 ]; then
  echo "${LID}: ERROR: Copying origin failed!"
fi

# rename to mask and mean
if [ -f mask+orig.HEAD ]; then rm -f mask+orig.*; fi 
3dcopy ${mask_brik_prefix}+orig mask

if [ -f mean+orig.HEAD ]; then rm -f mean+orig.*; fi; 
3dcopy ${mean_brik_prefix}+orig mean

# overlay mask
if [ $show_overlay -eq 1 ]; then
  echo "${LID}: INFO: Overlay mask: ${mask_brik_prefix}+orig"
  if [ -f ${mask_brik_prefix}+orig.HEAD ]; then
    tabs_drive_afni.sh -port 7100 -v -name $(basename ${0%.*}) \
      -com "RESCAN_THIS A" \
      -com "RESCAN_THIS B" \
      -com "SET_UNDERLAY B.anat" \
      -com "SET_OVERLAY B.${mask_brik_prefix}" \
      -com "SET_FUNC_RESAM B.Li.Li" \
      -com "SET_PBAR_NUMBER B.10" \
      -com "SET_THRESHOLD B.000" \
      -com "SEE_OVERLAY B.+" \
      -com "OPEN_WINDOW B.axialimage keypress=v" \
      -quit 
  else 
    echo "${LID}: ERROR: Overlaying mask: ${mask_brik_prefix}+orig failed!"
  fi
fi