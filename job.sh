#!/bin/bash
#SBATCH -J recurse
#SBATCH -A SUPPORT-CPU
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --time=00:15:00
#SBATCH --mail-type=FAIL
#SBATCH --no-requeue
#send signal 10 840 seconds before end (about 14 mins)
#SBATCH --signal=10@850 
#SBATCH -p skylake

numnodes=$SLURM_JOB_NUM_NODES
numtasks=$SLURM_NTASKS
mpi_tasks_per_node=$(echo "$SLURM_TASKS_PER_NODE" | sed -e  's/^\([0-9][0-9]*\).*$/\1/')

#! Rest of script does not execute on failure?
set -e 

export FORT_BUFFERED=FALSE

CNS="~/lcns"
#! Full path to application executable: 
application="$CNS/pSolid_Cyl/pSolid_Cyl"
settings="settings/001*"
#! Grep some data
output_path=$(cat $settings | grep -e Output/directory | cut -d { -f2 | cut -d } -f1)
output_path="$(echo -e "${output_path}" | sed -e 's/[[:space:]]*$//')"
finalTime=$(cat $settings | grep -e Amr/finalTime | cut -d { -f2 | cut -d } -f1)
options="~/coating/materials_entropy.amr $settings --disable-fpe"

if [ -f "$1" ]; then
  echo "checkpoint file exists: "$1
  options="--restart-file=$1 --disable-fpe"
else 
  echo "checkpoint file doesn't exist"
fi

workdir="$SLURM_SUBMIT_DIR"  
export OMP_NUM_THREADS=1

np=$[${numnodes}*${mpi_tasks_per_node}]

export I_MPI_PIN_DOMAIN=omp:compact # Domains are $OMP_NUM_THREADS cores in size
export I_MPI_PIN_ORDER=scatter # Adjacent domains have minimal sharing of caches/sockets

. ~/envs/cns-intel-18
CMD="mpirun -ppn $mpi_tasks_per_node -np $np $application $options"

cd $workdir
echo -e "Changed directory to `pwd`.\n"

JOBID=$SLURM_JOB_ID

echo -e "JobID: $JOBID\n======"
echo "Time: `date`"
echo "Running on master node: `hostname`"
echo "Current directory: `pwd`"

if [ "$SLURM_JOB_NODELIST" ]; then
        #! Create a machine file:
        export NODEFILE=`generate_pbs_nodefile`
        cat $NODEFILE | uniq > machine.file.$JOBID
        echo -e "\nNodes allocated:\n================"
        echo `cat machine.file.$JOBID | sed -e 's/\..*$//g'`
fi

echo -e "\nnumtasks=$numtasks, numnodes=$numnodes, mpi_tasks_per_node=$mpi_tasks_per_node (OMP_NUM_THREADS=$OMP_NUM_THREADS)"

echo -e "\nExecuting command:\n==================\n$CMD\n"

eval $CMD 

#! SLURM_SUBMIT_DIR is the directory in which sbatch is invoked
#! we can use --output to redirect stdout and stderr to a specified file named 

exitCode=$?
cd $SLURM_SUBMIT_DIR

# t=$(date +%H)
# duration=01:59:00
# if [ $t -ge 8 -a $t -lt 17 ]; then
#   duration=12:00:00
# fi

currentTime=$(tac $workdir/slurm-$JOBID.out | grep -m 1 'T=' | cut -d "=" -f 2 | awk '{print $1}' | tr [a-z] [A-Z])

echo "The slurm job name is $SLURM_JOB_NAME"
echo "current time is $currentTime"
echo "final time is $finalTime"

if [ $(echo "$currentTime == $finalTime" | bc -l) -eq 0 ]; then 
	echo "resubmitting job from $SLURM_SUBMIT_DIR"
	# 0 is true, 1 is false 
	# echo "The exit code (in if) $exitCode"
	echo "The output path is $output_path" 
	checkpoint=$(ls -1v $output_path/*.chk | tail -1) # was -At
	echo "Job name is: $SLURM_JOB_NAME"
	echo "Slurm submit directory is: $SLURM_SUBMIT_DIR"
	echo "Command is $CMD"
	cd $workdir
	currScript=$(readlink -f "$0")
	echo $currScript
	# sbatch -J "$SLURM_JOB_NAME" --qos=intr --time=00:15:00 $currScript "$checkpoint"
	sbatch -J "$SLURM_JOB_NAME" --time=00:15:00 $currScript "$checkpoint"
fi

echo "The exit code (in if) " $exitCode
