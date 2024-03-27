#!/bin/bash

#
# Start DCMTK's storescp for receiving DICOM data
# 

# source tabs environment
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

# Define parameters for storescp
prog=storescp
storescp=$(command -v $prog)
aet='STORESCP_TABS'
ext=".dcm"
port=5104
script=${TABS_PATH}/bin/tabs_process_dicom_incoming.sh
dicomdir=${TABS_PATH}/dicom
prefix=sorted
timeoutsec=2

if [ -z "${storescp}" ]; then
  echo "${LID}: storescp not installed or in PATH"
  exit 1
fi

logfile=${TABS_PATH}/log/${prog}.log
pidfile=${TABS_PATH}/log/${prog}.pid

# Check if storescp is already running
if [ -f $pidfile ]; then
  if [ "$(ps -p $(cat $pidfile) -o comm=)" == "$prog" ]; then
     echo "${LID}: storescp already running with PID: $(cat $pidfile)"
     exit 1
  fi
fi

## initialize logfile
date > $logfile

${storescp} \
  --output-directory ${dicomdir} \
  --aetitle ${aet} \
  --filename-extension ${ext} \
  --eostudy-timeout ${timeoutsec} \
  --sort-conc-studies ${prefix} \
  --exec-on-eostudy "${script} #p" \
  ${port} \
>> ${logfile} 2>&1 &

# Save process id 
echo $! > ${pidfile}

if [ "$(ps -p $(cat $pidfile) -o comm=)" == "$prog" ]; then
  echo "${LID}: storescp sucssfullly started with PID: $(cat $pidfile)"
fi

exit 0