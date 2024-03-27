# Temporarily Adaptive Brain State (TABS)

Scripts to simulate and run realtime fMRI experiments for neurofeedback.

## Software Requirements

### AFNI (tested: commit: c8444f5fe3c4c33825c07c19279dddda151501f5)
- For receiving and processing of EPI data.
- For sending neurofeedback data over TCP/IP.
- For visualization.

### DCMTK
- For receiving structural DICOMs at the beginning of the session:
  - To archive old data.
  - To start up AFNI.
  - To run processing of structural data based on DICOM header entries.

### FSL (tested: version 5.0)
- For alignment, preprocessing, etc.

### FREESURFER (tested with: freesurfer-linux-centos7_x86_64-7.4.0-20230510-e558e6e)
- For skull stripping.

## Configure TABS

Take a look at `tabs_env.cfg` and:
1. Provide the paths for the software requirements listed above.
2. Set IP address of the machine receiving the neurofeedback (`SVM_STIM_IP`, `SVM_STIM_PORT`).
3. Set `AFNI_TRUST_HOST`.

## Simulate

Simulate feedback based on resting-state networks:
```bash
cd simulation
./simulate+rsn.sh
```
