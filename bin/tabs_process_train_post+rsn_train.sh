#!/bin/bash -xef 

#
# RSN rest processing for EPI data after it has been acquired (post)
#
# Credit: Cameron Craddock
#

# rest EPI processing depends on the structural and mask processing 
# which might not be finished when this script is executed. 
# Wait MAX_WAIT_COUNT for processing to finish.
MAX_WAIT_COUNT=60 # in seconds 

# RSN number to extract rom template: 3=DMN
rsn_nr=3

# spatial smooting
smoothing_fwhm=6

# overlay weight vector if done processing 
show_overlay=1

# required files created by structural/mask processing
mean_brik=mean+orig
mask_brik=mask+orig
pnas_epi_nii=rm_epi_pnas.nii
segmask_nii=rm_segmask.nii

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
  for file in ${mask_brik}.HEAD ${mean_brik}.HEAD $segmask_nii $wm_mask_nii; do
    if [ ! -f $file ]; then
      return 1
    fi
  done

  return 0
}

# wait for t1 processing to finish
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

# get last brik witten to disc
last_brik_prefix=$(tabs_get_last_brik_prefix.sh)
last_brik=${last_brik_prefix}+orig

# define some output filenames to help keep everything consistent, and readable
train_name_nii=${last_brik_prefix}_vr.nii
motion_file=${last_brik_prefix}_motion.1D
nuisance_file=${last_brik_prefix}_nuisance.1D
orts_file=${last_brik_prefix}_orts.1D

echo "${LID}: INFO: Motion correction aka volume registration."
3dvolreg -Fourier -prefix ${train_name_nii} -base ${mean_brik} \
  -1Dfile ${motion_file} ${last_brik}

echo "${LID}: INFO: Forming Nuisance ORTs"
3dROIstats -quiet -mask ${segmask_nii} ${train_name_nii} > ${nuisance_file}

echo "${LID}: INFO: Combining mition and nuisiance regressors into orts file"
1dcat ${motion_file} ${nuisance_file} > ${orts_file}

# calucate order for detrending based on run length
nvols=$( fslnvols ${train_name_nii} )
polort=$(( 1+${nvols}/150 ))

echo "${LID}: INFO: Detrending using order: $polort"
3dDetrend -prefix ${train_name_nii%%.nii}_det.nii -polort ${polort} \
  -vector ${orts_file} ${train_name_nii}

# append det postfix to name
train_name_nii=${train_name_nii%%.nii}_det.nii

if [ ! -z "${smoothing_fwhm}" ]; then
  echo "${LID}: INFO: Spatial smoothing FWHM=$smoothing_fwhm"
  3dmerge -1blur_fwhm $smoothing_fwhm -doall -quiet \
      -prefix ${train_name_nii%%.nii}_sm.nii \
      ${train_name_nii}

  # append sm postfix to name
  train_name_nii=${train_name_nii%%.nii}_sm.nii
fi

echo "${LID}: INFO: Spatial regression"
fsl_glm -i ${train_name_nii} -d ${pnas_epi_nii} -o RSN_TCs.xmat

echo "${LID}: INFO: Extracting time course for RSN: $rsn_nr"
1deval -a RSN_TCs.xmat"[${rsn_nr}]" -expr 'a' > RSN_TC.1D

echo "${LID}: INFO: Z-scoring time course "
tc_mean=$(3dTstat -prefix - -mean RSN_TC.1D\' 2>/dev/null)
tc_stdev=$(3dTstat -prefix - -stdev RSN_TC.1D\' 2>/dev/null)
1deval -a RSN_TC.1D -expr "(a-$tc_mean)/$tc_stdev" > zRSN_TC.1D

echo "${LID}: INFO: Convert training dataset to HEAD/BRIK "
3dcopy ${train_name_nii} ${train_name_nii%%.nii}
train_brik=${train_name_nii%%.nii}+orig

echo "${LID}: INFO: SV-regression using $train_brik"
3dsvm -type regression \
  -trainvol ${train_brik} \
  -trainlabels zRSN_TC.1D \
  -mask ${mask_brik} \
  -model svr_model_${rsn_nr} \
  -bucket svr_model_${rsn_nr}_w

echo "${LID}: INFO: Display svr weight vector as overlay"

if [ $show_overlay -eq 1 ]; then
  echo "${LID}: INFO: Displaying svr weight vector as overlay"

  tabs_drive_afni.sh -port 7101 -v -name $(basename ${0%.*}) \
    -com "RESCAN_THIS A" \
    -com "RESCAN_THIS B" \
    -com "SET_UNDERLAY B.anat" \
    -com "SET_OVERLAY B.svr_model_${rsn_nr}_w" \
    -com "SET_FUNC_RESAM B.Li.Li" \
    -com "SET_PBAR_ALL B.-99 1 Spectrum:yellow_to_cyan+gap" \
    -com "SET_THRESHOLD B.3000" \
    -com "SEE_OVERLAY B.+" \
    -com "OPEN_WINDOW B.axialimage keypress=v" \
    -quit
fi

