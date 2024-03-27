#!/bin/bash 

#
# T1 processing for tracking of resting state networks (RSNs)
# Credit to Cameron Craddock
#

# arguments
DICOM_DIR=$1

n_args=1
if [ $# -ne $n_args ]; then
  echo "    Usage $0 <dicom dir>"
  echo "**  Need $n_args input arguments $# given!"
  exit 1
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

script_name="$(basename ${0%%.sh})"

echo
echo ======================================================
echo "${LID}: INFO: Processing: $DICOM_DIR"
echo =======================================================
echo

if [ ! -d $DICOM_DIR ]; then
  echo "${LID}: ERROR: Dicom directory: $DICOM_DIR does not exist!"
  exit 1
fi

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

# change directory to where the dicoms are
cd $DICOM_DIR

echo "${LID}: INFO: Converting DCM to NII using dcm2niix"
dcm2niix -o . -f anat .

echo "${LID}: INFO: Converting NII to AFNI HEAD/BRIK"
3dcopy anat.nii anat+orig


echo "${LID}: INFO: Moving anatomical to data directory"
mv anat* $TABS_PATH/data/.

echo "${LID}: INFO: Start afni controller A/B"
tabs_start_afni.sh

echo "${LID}: INFO: Moving transferred dicoms to data directory"
echo DBG: DICOM_DIR=$DICOM_DIR
mv -v $DICOM_DIR ${TABS_PATH}/data/dicom

# change to the data directory for further analysis 
cd ${TABS_PATH}/data

echo "${LID}: INFO: Make a copy of the anatomical"
3dcopy anat+orig rm_anat

echo "${LID}: INFO: Debliuqe the anatomical"
3drefit -deoblique rm_anat+orig

echo "${LID}: INFO: Orient anatomical to RPI"
3dresample -orient RPI -prefix rm_anat_rpi.nii -inset rm_anat+orig

#Use Freesurfer's mri_synthstrip. Seems a lot faster and more accurate than AFNI's 3dSkullStrip
echo "${LID}: INFO: Remove skull using mri_synthstrip"
mri_synthstrip  -i rm_anat_rpi.nii -o rm_anat_rpi_ss.nii -m rm_anat_rpi_ss_mask.nii
#3dSkullStrip -orig_vol -input rm_anat_rpi.nii -prefix rm_anat_rpi_ss.nii

echo "${LID}: INFO: Crop anatomical"
3dAutobox -prefix rm_anat_rpi_ss_cropped.nii -input rm_anat_rpi_ss.nii 

echo "${LID}: INFO: Resample to 2mm iso"
3dresample -dxyz 2 2 2 -prefix rm_anat_rpi_ss_cropped_2mm.nii \
  -inset rm_anat_rpi_ss_cropped.nii

anat=rm_anat_rpi_ss_cropped_2mm.nii 

echo "${LID}: INFO: Linear alignment to template space: ${FLIRT_TEMPLATE}"
flirt -ref ${FLIRT_TEMPLATE} \
  -in rm_anat_rpi_ss_cropped_2mm.nii \
  -omat rm_anat_2_mni_xform.mat

anat_mni_xform=rm_anat_2_mni_xform.mat
mni_anat_xform=rm_mni_2_anat_xform.mat

echo "${LID}: INFO: Invert linear transformation matrix"
convert_xfm -omat ${mni_anat_xform} -inverse ${anat_mni_xform}

echo "${LID}: INFO: Segmenting right lateral ventricle"
(run_first -i ${anat} \
  -t ${anat_mni_xform} \
  -n 40 -o rm_mh_R_LV \
  -m ${FSLDIR}/data/first/models_336_bin/R_Late_bin.bmv \
  > ${TABS_PATH}/log/${script_name}_first1.log 2>&1 )&

pid_first1=$!

echo "${LID}: INFO: Segmenting left lateral ventricle"
(run_first -i ${anat} \
  -t ${anat_mni_xform} \
  -n 40 -o rm_mh_L_LV  \
  -m ${FSLDIR}/data/first/models_336_bin/L_Late_bin.bmv \
  > ${TABS_PATH}/log/${script_name}_first2.log 2>&1 )&
pid_first2=$!

echo "${LID}: INFO: FAST segmentation"
fast -g -o rm_mh ${anat} > ${TABS_PATH}/log/${script_name}_fast.log 2>&1 &

pid_fast=$!

echo "${LID}: INFO: Waiting for FSL segmentations processes to finish"
wait $pid_first1 $pid_first2 $pid_fast

echo "${LID}: INFO: Combining CSF and LVs segmentation masks"
3dcalc -prefix rm_lv_mask.nii \
  -a rm_mh_seg_0.nii \
  -b rm_mh_L_LV.nii \
  -c rm_mh_R_LV.nii \
  -expr 'step(a*(b+c))' \
  -datum byte

# rename WM mask
mv rm_mh_seg_2.nii rm_wm_mask.nii

echo "${LID}: INFO: Clean up rm_mh files"
rm -f rm_mh*

echo "${LID}: INFO: Done! RSN structural processing complete." 