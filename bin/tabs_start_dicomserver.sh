#!/bin/bash

#
# Start DCMTK's storescp for receiving DICOM data
# 

# default args
stop=0

# check args
if [ ! -z "$@" ]; then
  for arg in "$@"; do
    if [[ "$arg" == "-stop" ]]; then
      stop=1
    fi
  done
fi

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
  echo "${LID}: ERROR: storescp not installed or in PATH"
  exit 1
fi

logfile=${TABS_PATH}/log/${prog}.log
pidfile=${TABS_PATH}/log/${prog}.pid

# top storescp if desired
if [ $stop -eq 1 ]; then
  if [ -f $pidfile ]; then
    if [ "$(ps -p $(cat $pidfile) -o comm=)" == "$prog" ]; then
      echo "${LID}: INFO: Killing storescp with PID: $(cat $pidfile)"
      kill -9 $(cat $pidfile)
      exit 0
    else
      echo "${LID}: WARNING: storescp with PID: $(cat $pidfile) not running"
      exit 0
    fi
  fi

  echo "${LID}: WARNING: No process file: $pidfile) found"
  exit 0
else
  if [ -f $pidfile ]; then
    if [ "$(ps -p $(cat $pidfile) -o comm=)" == "$prog" ]; then
      echo "${LID}: storescp already running with PID: $(cat $pidfile)"
      exit 0
    fi
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
  echo "${LID}: storescp successfully started with PID: $(cat $pidfile)"
fi

exit 0