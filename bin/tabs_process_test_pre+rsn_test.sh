#!/bin/bash -xef 

#
# sets up afni controller for real-time processing before EPI data is acquired (pre)
#   pre-processing is set up through plug_realtime.c
#   SVR processing is set up through plug_3dsvm.c 
#
#  Credit: Cameron Craddock
#

# this script depends on several files (see below)
# Wait MAX_WAIT_COUNT for files to be written.
MAX_WAIT_COUNT=60 # in seconds 

# RSN number to extract rom template: 3=DMN
rsn_nr=3

# smoothing:
#TODO: Needs to be defined across training/testing
rt_smoothing_fwhm=6

# trend order 
rt_detrend_polort=1

# detrending options
# bit mask defining real-time detrending options to be used
rt_detrend_mode=7

  # motion: 1
  # global mean: 2
  # mask averages: 4
  # 1+2+4=7

  # more details in plug_realtime.c:
    # define RT_DETREND_MOTION  0x01  /* remove motion params */
    # define RT_DETREND_GM      0x02  /* remove global mean */
    # define RT_DETREND_MASK    0x04  /* remove mask averages */
    # define RT_DETREND_FRISTON 0x08  /* remove Friston 24 regressors */

# required files created by structural, mask, rest processing 
mean_brik=mean+orig
segmask_nii=rm_segmask.nii
svr_model_w_brik=svr_model_${rsn_nr}_w+orig

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

# check if all files exist
all_files_exist() {
  for file in ${mean_brik}.HEAD $segmask_nii ${svr_model_w_brik}.HEAD; do
    if [ ! -f $file ]; then
      return 1
    fi
  done

  return 0
}

# wait for files 
count=0
while [ $count -lt $MAX_WAIT_COUNT ]; do
  count=$((count+1))
  
  if all_files_exist; then
    break
  fi

  echo "${LID}: INFO: Waiting for processing to finish (${count}s out of ${MAX_WAIT_COUNT}s)"
  sleep 1
done

if ! all_files_exist; then
  echo "${LID}: ERROR: Previous processing did not finish in time"
  exit 1
fi

# get the index of the last brik for naming of prediction file
last_brik_index=$(tabs_get_last_brik_index.sh)
next_brik_index=$((last_brik_index+1))
svr_pred_prefix=svr_pred_model_${rsn_nr}_test_brik__${next_brik_index}

echo "${LID}: INFO: Setting up afni controller for real-time processing"
echo "${LID}: INFO: Smoothing FWHM: $rt_smoothing_fwhm"
echo "${LID}: INFO: Detrend mode: $rt_detrend_mode"
echo "${LID}: INFO: Trend order: $rt_detrend_polort"

tabs_drive_afni.sh -port 7102 -v -name $(basename ${0%.*}) \
  -com "SETENV AFNI_REALTIME_Verbose 2" \
  -com "SETENV AFNI_REALTIME_Mask_Dset ${segmask_nii}" \
  -com "SETENV AFNI_REALTIME_Mask_Vals ROI_means" \
  -com "SETENV AFNI_REALTIME_External_Dataset ${mean_brik}" \
  -com "SETENV AFNI_REALTIME_DETREND_MODE ${rt_detrend_mode}" \
  -com "SETENV AFNI_REALTIME_DETREND_POLORT ${rt_detrend_polort}" \
  -com "SETENV AFNI_REALTIME_DETREND_FWHM ${rt_smoothing_fwhm}" \
  -com "3DSVM -rt_test -bucket ${svr_model_w_brik} -pred ${svr_pred_prefix} -nopredscale -stim_ip ${SVM_STIM_IP} -stim_port ${SVM_STIM_PORT}" \
  -com "OPEN_WINDOW B.axialimage keypress=' '" \
  -com "OPEN_WINDOW B.coronalimage keypress=' '" \
  -com "OPEN_WINDOW B.sagittalimage keypress=' '" \
  -quit
