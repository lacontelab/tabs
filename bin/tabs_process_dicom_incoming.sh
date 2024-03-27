#!/bin/bash

#
# written to be executed by DCMTK's storescp upon end-of-study
#

# arguments
DICOM_DIR=$1

n_args=1
if [ $# -ne $n_args ]; then
  echo "Usage $0 <dicom dir>"
  echo "ERROR ($0): Need $n_args input arguments $# given!"
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
  echo "ERROR($0): No configuration file found!"
  exit 1
fi

# realtive paths should be avoided, but...
if [ ${DICOM_DIR:0:1} != '/' ]; then
  DICOM_DIR=$(pwd)/$DICOM_DIR
fi

if [ ! -d $DICOM_DIR ]; then
  echo "${LID}: ERROR: Dicom directory: $DICOM_DIR does not exist!"
  exit 1
fi

# archive data from previous session with new DICOM transfer
echo "${LID}: INFO: Archiving data..."
tabs_archive_data.sh

# change to directory with DICOMs
cd $DICOM_DIR

# find a DICOM file to use as a representative of the study
dcm_file=$(ls -1 | grep "[.]dcm$" | head -n 1)

if [ -z "$dcm_file" ]; then
  # see if there a files ending in .ima insetad of .dcm
  dcm_file=$(ls -1 | grep "[.]ima$" | head -n 1)
fi

if [ -z "$dcm_file" ]; then
  echo "$LID: ERROR: No files ending with .dcm or .ima found in dicom directory: ${DICOM_DIR}"
  exit 1
fi

# extract dicom header entires to determine study parameters
echo "$LID: INFO: Extracting information from DICOM file: $dcm_file"

dcmdump_file=${dcm_file}.txt
dcmdump $dcm_file > $dcmdump_file

dcm_storage_type=$(cat $dcmdump_file | grep '(0002,0002)' | sed -e 's/^.*=\(.*\)\#.*$/\1/')

if [[ "$dcm_storage_type" == MRImageStorage* ]]; then
  dcm_study_name=$(cat $dcmdump_file| grep '(0008,1030)' | tr "[:upper:]" "[:lower:]" | sed -e 's/^.*\[\(.*\)\].*$/\1/' -e "s/^\[\(.*\)\]$/\1/" -e "s/[^\^a-z0-9.]/_/g")
  dcm_study_name_a=${dcm_study_name%^*}
  dcm_study_name_b=${dcm_study_name#*^}
  dcm_study_date=$(cat $dcmdump_file | grep '(0008,0020)' | sed -e 's/^.*\[\(.*\)\].*$/\1/')
  dcm_study_time=$(cat $dcmdump_file | grep '(0008,0030)' | sed -e 's/^.*\[\(.*\)\].*$/\1/')
  dcm_seq_name=$(cat $dcmdump_file | grep '(0018,0024)' | sed -e 's/^.*\[\(.*\)\].*$/\1/')

  echo "$LID: INFO: STUDY: $dcm_study_name"

  # export study names for use in processing scripts
  export TABS_STUDY_NAME_A=$dcm_study_name_a
  export TABS_STUDY_NAME_B=$dcm_study_name_b

elif [[ "$dcm_storage_type" == EnhancedMRImageStorage* ]]; then
  # TODO: Need to figure study name
  dcm_study_date=$(cat $dcmdump_file | grep '(0008,0020)' | sed -e 's/^.*\[\(.*\)\].*$/\1/')
  dcm_study_time=$(cat $dcmdump_file | grep '(0008,0030)' | sed -e 's/^.*\[\(.*\)\].*$/\1/')
  dcm_seq_name=$(cat $dcmdump_file | grep '(0018,9005)' | sed -e 's/^.*\[\(.*\)\].*$/\1/')
  echo "$LID: INFO: Enhanced DICOM: $dcm_seq_name @ $dcm_study_date $dcm_study_time"
else
  echo 
  echo "$LID: ERROR: Unknown DICOM storage type"
  exit 1
fi

rm $dcmdump_file

# check if functional or anatomical scan and call corresponding scripts accordingly
# TODO: This only works for Siemens 

if [ -z "$dcm_seq_name" ]; then
  echo "${LID}: WARNING: Sequence name can not be extracted from DICOM. Not Siemens?"
elif [[ $dcm_seq_name == *epfid2d* ]]; then
  echo "${LID}: INFO: Functional scan (epfid2d)"

  # set script for functional scans
  # allow processing of functional data (e.g motion evaluation, etc.)
  hook_script="${TABS_PATH}/bin/tabs_process_dicom_functional+default.sh"

elif [[ $dcm_seq_name == *tfl3d* ]]; then
  echo "${LID}: INFO: Anatomical scan (tfl3d)"
     
  # set study-specific naming for script
  hook_script=${TABS_PATH}/bin/tabs_process_dicom_structural+${dcm_study_name_b}.sh

  # check if study-specific script exists
  if [ ! -f $hook_script ]; then
    echo "${LID}: INFO: Study-specific structural processing script: $hook_script not found!"

    # if study specific script does not exists, use default
    hook_script=${TABS_PATH}/bin/tabs_process_dicom_structural+default.sh
    echo "${LID}: INFO: Using default structural processing script: $hook_script"
  fi
else
  echo "${LID}: ERROR: No processing implemented for sequence name: $dcm_seq_name"
  exit 1
fi

hook_script_basename=$(basename ${hook_script%.*})
logfile="${TABS_PATH}/log/${hook_script_basename}.log"
pidfile="${TABS_PATH}/log/${hook_script_basename}.pid"

# check if script is already running, and kill it if necessary
if [ -f ${pidfile} ]; then
  pid=$(cat ${pidfile})
  if [ "$(ps -p ${pid} -o comm=)" == "${hook_script_basename:0:15}" ]; then

    # retrieve group pid (so child-processes can be terminated as well)
    pgid=$(ps opgid= "$pid" | tr -d ' ')

    if [ -z "${pgid}" ]; then
      echo "${LID}: WARNING: Retriving process group id failed!"
      echo "${LID}: WARNING: Killing ${hook_script_basename} with with PID: ${pid}"
      echo "${LID}: WARNING: Killing ${hook_script_basename} with with PID: ${pid}" >> $logfile
      kill -9 ${pid}
    else
      echo "${LID}: WARNING: Killing ${hook_script_basename} and all other processes with PGID: ${pgid}"
      echo "${LID}: WARNING: Killing ${hook_script_basename} and all other processes with PGID: ${pgid}" >> $logfile
      kill -- -${pgid}
    fi

    # wait one second for process kill
    sleep 1
  fi
fi

# execute hook script using a new process group id
#   this is only necessary in simulation, since all processes (including AFNI) have the same pgid
if [ -f $hook_script ]; then
  echo "${LID}: INFO: Calling DICOM processing script: $hook_script"

  setsid $hook_script $DICOM_DIR > $logfile 2>&1 &
  
  # record pid and wait until processing complete 
  echo $! > ${pidfile}

else
  echo "${LID}: ERROR: DICOM processing script: $hook_script not found!"
fi