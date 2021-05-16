#!/bin/bash
#SBATCH --nodes=2
#SBATCH --exclusive
#SBATCH --time=0:10:00
#SBATCH -e cephfs_bench/slurm-%j.err
#SBATCH -o cephfs_bench/slurm-%j.out

BASE_DIR="$HOME/cephfs_bench"
WORK_DIR="$BASE_DIR/benchmark_`date +%s`"

# find an mpicc
if  [ "x`which mpicc`" == "x" ]
then
  module=`module avail 2>&1 | grep openmpi | head -1  | awk '{print $1}'`
  module load $module
fi

echo "print mpicc version"
mpicc --version
# print other useful info
echo "print modules"
module avail
echo "print slurm version"
srun --version
echo "print sinfo"
sinfo -a
echo "print slurm nodelist"
echo $SLURM_JOB_NODELIST

# create and change dir
mkdir -p $BASE_DIR && cd $BASE_DIR

# check if IOR already exists, otherwise clone and build
if [ ! -f $BASE_DIR/bin/ior ]
then
	mkdir $BASE_DIR/bin
	git clone https://github.com/hpc/ior ./ior_build && cd ior_build/
	./bootstrap &> ior_build.log
	./configure --prefix=`pwd`/build &>> ior_build.log
	make &>> ior_build.log
	make install &>> ior_build.log
	ldd build/bin/ior &>> ior_build.log
	cp $BASE_DIR/ior_build/build/bin/* $BASE_DIR/bin
        cd $BASE_DIR
        wget https://ftpmirror.gnu.org/parallel/parallel-latest.tar.bz2
	tar -jxvf parallel-latest.tar.bz2
        cd parallel-20210422/       
        ./configure --prefix=`pwd`/build &>> parallel_build.log
        make && make install
	cp $BASE_DIR/parallel-20210422/build/bin/* $BASE_DIR/bin
	rm -rf $BASE_DIR/ior_build
	rm -rf $BASE_DIR/parallel-*
fi

IOR=$BASE_DIR/bin/ior
GNUP=$BASE_DIR/bin/parallel
    
mkdir -p $WORK_DIR && cd $WORK_DIR

# THREAD
TOTAL_THREAD=$((SLURM_JOB_NUM_NODES*SLURM_CPUS_ON_NODE))
THREAD_PER_NODE=$SLURM_CPUS_ON_NODE
# run ior
mpirun -np $TOTAL_THREAD -npernode $THREAD_PER_NODE --mca btl self,tcp $IOR -b 8m -t 4m -a POSIX -wr -i1 -g -F -e -o $WORK_DIR/test -k # -O summaryFormat=CSV -O summaryFile=$WORK_DIR/ior.summary

# run gnu parallel to read md5sum
scontrol show hostnames  $SLURM_JOB_NODELIST > nodelist
$GNUP  -j 0 --sshloginfile  nodelist /usr/bin/time -v -o $WORK_DIR/md5sum.\`hostname\`.{} md5sum $WORK_DIR/test.000000{} ::: `seq -w 00 $((TOTAL_THREAD-1))`
rm -rf $WORK_DIR/test.00000*


