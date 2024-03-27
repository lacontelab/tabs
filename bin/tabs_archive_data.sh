#!/bin/bash

#
#  moves content of ${TABS_PATH}/data to a time-stampted direcotry 
#  in $TABS_PATH/archive
#  kills all processes wit pids stored in ${TABS_PATH}/log BUT storescp
#  archives all log files in $TABS_PATH/log

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

# move data if it exists
archive_dir=''
if [ -d "${TABS_PATH}/data" ]; then
  echo "${LID}: INFO: Archiving imaging data in: ${TABS_PATH}/data"

  # get a file with imaging data
  file=$(find ${TABS_PATH}/data/ -type f \( -name '*.HEAD' -o -name '*.nii*' \) -print -quit)

  if [ -z "${file}" ]; then
    echo "${LID}: WARNING: No data in ${TABS_PATH}/data/ found!"
  else
    # crateate time stamp based on file 
    date_str=$(date -r $file "+%Y-%m-%d.%H%M%S")
    archive_dir=${TABS_PATH}/archive/tabs_data_${date_str}
    
    if [ ! -d ${archive_dir} ]; then
      mkdir -p ${archive_dir}
    fi

    mv ${TABS_PATH}/data/* ${archive_dir}/.
  fi
else
  echo "${LID}: WARNING: Data directory: ${TABS_PATH}/data does not exist!"
fi


# kill all processes but storescp
# TODO: This is tricky if name of pid file of storescp changes
pid_files=$(find ${TABS_PATH}/log/ -type f -name '*.pid' ! -name 'storescp.pid')
echo DBG: $pid_files

# now kill all the processes with pid files
for pid_file in $pid_files; do
  pid=$(cat $pid_file)
  echo "${LID}: INFO: Killing process with pid: $pid"
  kill -9 $pid
  rm $pid_file
done

if [ ! -z "${archive_dir}" ]; then
  # store log files in archive
  mkdir ${archive_dir}/logs

  # move all logfiles, but storescp
  log_files=$(find ${TABS_PATH}/log/ -type f -name '*.log' ! -name 'storescp.log')

  for log_file in $log_files; do
    mv $log_file ${archive_dir}/logs/.
  done

  # copy (do not move) storescp log
  # TODO: Append timesamp to storescp.log. Tricky since am not sure how storescp writes to the log
  cp ${TABS_PATH}/log/storescp.log  ${archive_dir}/logs/.
fi