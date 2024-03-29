#!/bin/bash 

#
# simulate RSN processing
#

# defines
base_dir=$(pwd)
protocol="rsn"
RTFEEDME_DT=200 # time between volumes in ms 

# flags to run or skip parts of this simulation
structural_processing=1
mask_processing=1
rest_processing=1
feedback_processing=1

# source tabs environment
# this sets up the path, etc.
tabs_cfg_host_file=../tabs_env_$(hostname).cfg
tabs_cfg_file=../tabs_env.cfg

if [ -f $tabs_cfg_host_file ]; then
  source $tabs_cfg_host_file
elif [ -f $tabs_cfg_file ]; then
  source $tabs_cfg_file
else
  echo "ERROR ($0): No configuration file found!"
  exit 1
fi

# functions
run_command() {
  echo ":: About to run: $1"
  echo ":: Press any key to continue and key: s to skip"
  read -s -n 1 answer
  if [ "$answer" == "s" ] || [ "$answer" == "S" ]; then
    echo ":: Key: s/S pressed skipping..."
    return
  fi

  echo ":: Key: $answer pressed running:"
  echo "   $1"
  eval $1
}

# structural processing #######################################################
if [ $structural_processing -eq 1 ]; then

  # start dicomserver 
  #   receives dicom, preforms structural processing based on study name and 
  #   starts afni controller with predefined settings set in tabs_env.cfg
  command="tabs_start_dicomserver.sh"
  echo ":: Starting dicom server: "
  run_command "$command"

  # send dicom using DCMTK's scu
  # TODO: port hard coded
  command="storescu localhost 5104 --scan-directories ${base_dir}/input/${protocol}/t1/*.dcm"
  run_command "$command"
fi

# mask EPI processing ##########################################################
if [ $mask_processing -eq 1 ]; then
  
  # send mask data using rtfeedme
  command="rtfeedme -3D -dt $RTFEEDME_DT $(pwd)/input/${protocol}/mask+orig"
  echo ":: About to send EPI mask data:"
  run_command "$command"

  # execute mask processing 
  command="tabs_process_mask_post+rsn_mask.sh > ${TABS_PATH}/log/tabs_process_mask_post+rsn_mask.log 2>&1"
  echo ":: About to execute mask processing:"
  run_command "$command"
fi

# rest EPI data processing & model training ############################################
if [ $rest_processing -eq 1 ]; then
  # send rest data using rtfeedme
  command="rtfeedme -3D -dt $RTFEEDME_DT $(pwd)/input/${protocol}/rest+orig"
  echo ":: About to send EPI rest data:"
  run_command "$command"

  # execute rest processing (preprocessing, dual regression [spatial + SV regression] )
  command="tabs_process_train_post+rsn_train.sh > ${TABS_PATH}/log/tabs_process_train_post+rsn_train.log 2>&1"
  echo ":: About to execute rest processing:"
  run_command "$command"
fi

# feedback EPI processing #########################################################
if [ $feedback_processing -eq 1 ]; then
  # execute feedback setup script (define preprocessing, connect to stimulus)
  command="tabs_process_test_pre+rsn_test.sh > ${TABS_PATH}/log/tabs_process_test_pre+rsn_test.log 2>&1"
  echo ":: About to set up afni for feedback processing:"
  run_command "$command"
  

  ## send feedback data using rtfeedme
  command="rtfeedme -3D -dt $RTFEEDME_DT $(pwd)/input/${protocol}/fb1+orig"
  echo ":: About to send EPI feedback data:"
  run_command "$command"
fi

# stop dicomserver ################################################################
echo ":: Processing done!"
echo ":: Stopping dicom server: "
command="tabs_start_dicomserver.sh -stop"
run_command "$command"
echo ":: Done!"