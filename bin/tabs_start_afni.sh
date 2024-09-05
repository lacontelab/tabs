#!/bin/bash

#
# start afni controller window A and B
# if afni is running with logged pid, kill if first 
# kill afni only if arg -kill is passed
#
# default args
kill=0

# check args
if [ ! -z "$@" ]; then
  for arg in "$@"; do
    if [[ "$arg" == "-kill" ]]; then
      kill=1
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
  echo "${LID}: ERROR: No configuration file found!"
  exit 1
fi

# pid and logfile
pidfile=${TABS_PATH}/log/afni.pid
logfile=${TABS_PATH}/log/afni.log

# change pat to data directory
# the afni controller writes to $pwd by default
cd ${TABS_PATH}/data

# check if afni is already running, and kill it if necessary
if [ -f ${pidfile} ]; then
  pid=$(cat ${pidfile})
  if [ "$(ps -p ${pid} -o comm=)" == "afni" ]; then
    echo ${LID}: INFO: Killing afni with PID: ${pid}
    kill -9 ${pid}
  fi
fi

# exit and don't start afni if -kill option is set
if [ $kill -eq 1 ]; then
  exit 0
fi

# keep track of which afni binary is executed in logfile
# TODO: Loosing log if afni is restarted within session
which afni > $logfile

# open afni controller A
echo "${LID}: Starting afni controller A"
afni &>> $logfile -rt -yesplugouts -geom +2+28 -no_detach \
  -com "CLOSE_WINDOW A.axialimage " \
  -com "CLOSE_WINDOW A.sagittalimage " \
  -com "CLOSE_WINDOW A.coronalimage " $* &

echo $! > $pidfile
echo "${LID}: INFO: afni controller A started with pid: [$(cat $pidfile)]"

# wait until controller A is up
echo "${LID}: INFO: Waiting 5 seconds until afni is up..."
sleep 5

# open controller B with 3 plane view 
echo "${LID}: INFO: Starting afni controller B"

tabs_drive_afni.sh -v -name open_afni_controller_b -quit \
  -com "SWITCH_UNDERLAY anat" \
  -com "OPEN_WINDOW B geom=+777+784" \
  -com "OPEN_WINDOW B.axialimage geom=+445+0 widgets=0" \
  -com "ALTER_WINDOW B.axialimage geom=315x415" \
  -com "OPEN_WINDOW B.coronalimage geom=+446+446 widgets=0" \
  -com "ALTER_WINDOW B.coronalimage geom=340x400" \
  -com "OPEN_WINDOW B.sagittalimage geom=+10+445 widgets=0" \
  -com "ALTER_WINDOW B.sagittalimage geom=470x371" \
  -com "SEE_OVERLAY B.-" 