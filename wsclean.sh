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
echo "`date`: Starting Slurm Job: $SLURM_JOB_ID WSClean Workflow..."
echo "Running on:  $HOSTNAME"

# Parse params
# Expect 2 arguments only OBSID and (measurement set path)
if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 OBSID MS_PATH"
    exit 1
fi

OBSID=$1
MS_PATH=$2

MODULE_RCLONE="rclone/1.68.1"
MODULE_WSCLEAN="wsclean/3.4-idg"
BEAM_PATH=$HOME/bin

echo "OBSID to image: $OBSID"
echo "MS to image: $MS_PATH"

module use /software/projects/mwaeor/setonix/2025.08/modules/zen3/gcc/14.2.0/

echo "Setting up paths and variables"
OUT_PATH=$MYSCRATCH/birli_wsclean/$OBSID/out$SLURM_JOB_ID
mkdir $OUT_PATH
chmod g+rw $OUT_PATH
IMG_PATH=$OUT_PATH/img
mkdir $IMG_PATH

echo "`date`: Running WSClean..." 
module load $MODULE_WSCLEAN
pushd $IMG_PATH
srun -N 1 -n 1 -c 128 wsclean -mwa-path $BEAM_PATH -make-psf -save-uv -gridder idg -grid-with-beam -temp-dir /tmp -weight briggs 0 -size 4096 4096 -scale 20asec -niter 10000 -nmiter 2 -auto-threshold 1 -auto-mask 3 -mgain 0.85 -multiscale -multiscale-scale-bias 0.6 -name wsclean-$OBSID $MS_PATH
popd

echo "`date`: Finished Slurm Job: $SLURM_JOB_ID WSClean"
exit $rc
