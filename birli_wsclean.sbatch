#!/usr/bin/env bash
#SBATCH --partition=mwa-asvo
#SBATCH --qos=high
#SBATCH --ntasks=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=128
#SBATCH --exclusive
#SBATCH --mem-per-cpu=1840M
#SBATCH --exclusive
#SBATCH --time=8:00:00
#SBATCH --account=mwaasvo
#SBATCH --job-name=birli_wsclean
#SBATCH --nice=0
#SBATCH --open-mode=append
#SBATCH --output=/home/gsleap/birli_wsclean_%j.out
#SBATCH --error=/home/gsleap/birli_wsclean_%j.out
#SBATCH --parsable
set -e
echo "`date`: Starting Slurm Job: $SLURM_JOB_ID Birli WSClean Workflow..."
echo "Running on:  $HOSTNAME"

# Parse params
# Expect 1 or 2 arguments only
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <OBSID> [FITID] | [AOCAL_FILE]"
    exit 1
fi

MODULE_RCLONE="rclone/1.68.1"
MODULE_BIRLI="birli/0.18.1-vfaicag"
MODULE_WSCLEAN="wsclean/3.4-idg"

OBSID="$1"
FITID="${2:-}"   # Empty if not provided
AOCAL_FILE="${2:-}"   # Empty if not provided
OPTIONAL_PARAM="${2:-}"   # Empty if not provided

echo "Observation: $OBSID"

if [[ -z "$OPTIONAL_PARAM" ]]; then 
    echo "No FITID or AOCAL_FILE specified: will download best AOCAL solution for this calibrator"
else
    # If we passed a fit it is just a number
    # if we passed an aocal file it should be a file which exists
    if ls $DATA_PATH/*.bin >/dev/null 2>&1; then
        echo "Using $2 as an AOCAL_FILE"
        AOCAL_FILE=$2
    else
	echo "Using $2 as a FITID"
	FITID=$2
    fi
fi

BEAM_PATH=$HOME/bin

module use /software/projects/mwaeor/setonix/2025.08/modules/zen3/gcc/14.2.0/

echo "Setting up paths and variables"
DATA_PATH=/scratch/mwaasvo/gsleap/birli_wsclean/$OBSID
mkdir -p $DATA_PATH

OUT_PATH=/tmp
mkdir -p $OUT_PATH

IMG_PATH=$OUT_PATH/img
mkdir $IMG_PATH

FINAL_OUT_PATH=$DATA_PATH/out${SLURM_JOB_ID}
mkdir $FINAL_OUT_PATH

echo "Checking if files exist..."
if ls $DATA_PATH/*.fits >/dev/null 2>&1; then
    echo "Files exists. No need to copy."
else
    echo "Files do not exist. Starting rclone"
    module load $MODULE_RCLONE
    rclone copy acacia_mwa:/birli-wsclean $DATA_PATH
    echo "rclone complete"
fi

echo "Downloading latest metafits..."
wget --quiet "http://ws.mwatelescope.org/metadata/fits?obs_id=$OBSID" -O $DATA_PATH/${OBSID}_metafits.fits
echo "Done!"

if [[ -z "$AOCAL_FILE" ]]; then
    if [[ -z "$FITID" ]]; then
        echo "No fitid specified so we'll get the best one from the web service"
        echo "Downloading calibration solution... obsid=$OBSID"
        wget --quiet "https://ws.mwatelescope.org/calib/get_cal_solution?obs_id=$OBSID" -O $OUT_PATH/cal.zip
	echo "Done!"
    else
        echo "Using fitid $FITID"
        echo "Downloading calibration solution...fitid=$FITID"
        wget --quiet "https://ws.mwatelescope.org/calib/get_cal_solution?obs_id=$OBSID&prefer_fitid=$FITID" -O $OUT_PATH/cal.zip
	echo "Done!"
    fi

    echo "Unzipping calsolution..."
    unzip -o $OUT_PATH/cal.zip -d $OUT_PATH

    echo "Finding aocal file..."
    AOCAL_FILE="$(find $OUT_PATH -maxdepth 1 -type f -name '*.bin' -print -quit)"
    if [[ -z "$AOCAL_FILE" ]]; then
        echo "No AOCAL .bin file found in $OUT_PATH"
        exit 1
    else
        echo "Found $AOCAL_FILE"
    fi
else
    echo "Skipping getting cal solution as $AOCAL_FILE was specified"
fi

MS_PATH=$OUT_PATH/$OBSID.ms

echo "`date`: Running Birli..."
module load $MODULE_BIRLI
export RUST_LOG=birli=debug
srun -N 1 -n 1 -c 128 birli --metafits $DATA_PATH/${OBSID}_metafits.fits --apply-di-cal $AOCAL_FILE --no-draw-progress --max-memory=150 --avg-freq-res=40 --avg-time-res=2 --ms-out=$MS_PATH $DATA_PATH/${OBSID}_2*.fits | tee $OUT_PATH/birli.log

echo "`date`: Running WSClean..." 
module unload $MODULE_BIRLI
module load $MODULE_WSCLEAN
pushd $IMG_PATH
srun -N 1 -n 1 -c 128 wsclean -abs-mem 150 -mwa-path $BEAM_PATH -make-psf -save-uv -gridder idg -grid-with-beam -temp-dir /tmp -weight briggs 0 -size 4096 4096 -scale 20asec -niter 10000 -nmiter 2 -auto-threshold 1 -auto-mask 3 -mgain 0.85 -multiscale -multiscale-scale-bias 0.6 -name wsclean-$OBSID $MS_PATH
popd

#ls -lR $OUT_PATH

# Now cp the data from RAM (/tmp) back to the FINAL_OUT_PATH
cp -r $OUT_PATH/* $FINAL_OUT_PATH

echo "`date`: Finished Slurm Job: $SLURM_JOB_ID Birli WSClean"
exit $rc
