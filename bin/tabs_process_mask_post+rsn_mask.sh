#!/bin/bash

#
# RSN mask processing for EPI data after it has been acquired (post)
#
# Credit: Cameron Craddock
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

# The RSN mask processing depends on the structural processing 
# which might not be finished when this script is executed. 
# Wait MAX_WAIT_COUNT for structural processing to finish.
MAX_WAIT_COUNT=600 # in seconds 

# files created by structural processing
anat=rm_anat_rpi_ss_cropped_2mm.nii
anat_mni_xform=rm_anat_2_mni_xform.mat
mni_anat_xform=rm_mni_2_anat_xform.mat
lv_mask_nii=rm_lv_mask.nii
wm_mask_nii=rm_wm_mask.nii

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

# run default mask processing 
tabs_process_mask_post+default.sh -no_overlay

# enter data directory for further processing
cd ${TABS_PATH}/data

# define templates
# TODO: These defines are used across scripts and should be in a common
# configuration file for the rsn processing
FLIRT_TEMPLATE=${TABS_PATH}/templates/MNI152_T1_2mm_brain.nii
PNAS_TEMPLATES=${TABS_PATH}/templates/PNAS_Smith09_rsn10.nii

if [ ! -f $FLIRT_TEMPLATE ]; then
  echo "${LID}: ERROR: template: $FLIRT_TEMPLATE not found found!"
  exit 1
fi

if [ ! -f $PNAS_TEMPLATE ]; then
  echo "${LID}: ERROR: template: $PNAS_TEMPLATE not found found!"
  exit 1
fi

# check if all files generated during t1 processing exist
all_files_exist() {
  for file in $anat $anat_mni_xform $mni_anat_xform $lv_mask_nii $wm_mask_nii; do
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

  echo "${LID}: INFO: Waiting structural processing to finish (${count}s out of ${MAX_WAIT_COUNT}s)"
  sleep 1
done

if ! all_files_exist; then
  echo "${LID}: ERROR: Structural processing did not finish in time"
  exit 1
fi

# continue with RSN  mask processing
mean_brik=mean+orig

if [ ! -f ${mean_brik}.HEAD ]; then
  echo "${LID}: ERROR: Brik with mean across mask: ${mean_brik}.HEAD does not exist!"
  exit 1
fi

name_nii=rm_mk_${mean_brik%%+orig}.nii
echo "${LID}: INFO: Copy mean brik to $name_nii"
3dcopy ${mean_brik} ${name_nii}

# replace transformation marix with cardinal matrix, which FSL likes
3drefit -deoblique ${name_nii}

echo "${LID}: INFO: Reorient to RPI"
3dresample -orient RPI -prefix ${name_nii%%.nii}_rpi.nii -inset ${name_nii}
name_nii=${name_nii%%.nii}_rpi.nii

echo "${LID}: INFO: Align EPI to T1 using flirt"
epi_anat_xform=rm_epi_2_anat_xform.mat
flirt -ref ${anat} -in ${name_nii} -dof 6 -omat rm_mk_init.mat 

echo "${LID}: INFO: Refine EPI alignment using boundry based registration"
flirt -ref ${anat} -in ${name_nii} -dof 6 \
  -cost bbr -wmseg ${wm_mask_nii} -init rm_mk_init.mat \
  -omat ${epi_anat_xform} -schedule ${FSLDIR}/etc/flirtsch/bbr.sch

#older version of flirt: -cost bbr
echo "${LID}: INFO: Invert linear transfrom"
anat_epi_xform=rm_anat_2_epi_xform.mat
convert_xfm -omat ${anat_epi_xform} \
  -inverse ${epi_anat_xform}

echo "${LID}: INFO: Combining xforms ${anat_epi_xform} and ${mni_anat_xform}"
mni_epi_xform=rm_mni_2_epi_xform.mat
convert_xfm -omat ${mni_epi_xform} \
  -concat ${anat_epi_xform} ${mni_anat_xform}

echo "${LID}: INFO: Copy PNAS templates to subject space (in RPI)"
epi_pnas=rm_epi_pnas.nii

flirt -in ${PNAS_TEMPLATES} -ref ${name_nii} \
  -applyxfm -init ${mni_epi_xform} \
  -out rm_mk_epi_pnas_rpi.nii

echo "${LID}: INFO: Copy  PNAS template to RAI"
3dresample -orient RAI -prefix ${epi_pnas} \
  -inset rm_mk_epi_pnas_rpi.nii

echo "${LID}: INFO: Creating segmentation masks in EPI space"
flirt -in ${lv_mask_nii} -ref ${name_nii} \
  -applyxfm -init ${anat_epi_xform} \
  -out rm_mk_lv.nii -interp nearestneighbour

flirt -in ${wm_mask_nii} -ref ${name_nii} \
  -applyxfm -init ${anat_epi_xform} \
  -out rm_mk_wm.nii -interp nearestneighbour

echo "${LID}: INFO: Erode masks"
3dcalc -prefix rm_mk_lv_dil.nii -a rm_mk_lv.nii \
  -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k \
  -expr 'a*(1-amongst(0,b,c,d,e,f,g))'

3dcalc -prefix rm_mk_wm_dil.nii -a rm_mk_wm.nii \
  -b a+i -c a-i -d a+j -e a-j -f a+k -g a-k \
  -expr 'a*(1-amongst(0,b,c,d,e,f,g))'

echo "${LID}: INFO: Combine masks"
3dAutomask -prefix rm_mk_mask_rpi.nii ${name_nii}

segmask=rm_segmask.nii

3dcalc -prefix rm_mk_segmask_rpi.nii \
 -a rm_mk_lv.nii \
 -b rm_mk_wm.nii \
 -c rm_mk_mask_rpi.nii \
 -expr 'step(c)*(a+2*b)' \
 -datum byte

echo "${LID}: Convert segmask to RAI"
3dresample -orient RAI -prefix ${segmask} \
  -inset rm_mk_segmask_rpi.nii

# overlay mask
if [ $show_overlay -eq 1 ]; then
  echo "${LID}: INFO: Overlay segmentation mask: ${segmask}"
  if [ -f ${segmask} ]; then
    tabs_drive_afni.sh -port 7100 -v -name $(basename ${0%.*}) \
      -com "RESCAN_THIS A" \
      -com "RESCAN_THIS B" \
      -com "SET_UNDERLAY B.anat" \
      -com "SET_OVERLAY B.${segmask}" \
      -com "SET_FUNC_RESAM B.Li.Li" \
      -com "SET_PBAR_ALL B.-99 1 ROI_i32" \
      -com "SET_THRESHOLD B.000" \
      -com "SEE_OVERLAY B.+" \
      -quit 
  else 
    echo "${LID}: ERROR: Segmentation mask: ${segmask} does not exist!"
  fi
fi

echo "${LID}: INFO: Done! RSN mask processing complete."

