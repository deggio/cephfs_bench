#!/bin/bash
set -x

BASE_DIR="$HOME/cephfs_bench"
WORK_DIR="`mktemp -d $BASE_DIR/benchmark_XXXXXXX`"
RUN_ID=`basename $WORK_DIR`
RESULT_DIR="$BASE_DIR/RESULTS"

##################
# PLEASE SET HERE
# ACCORDINGLY TO YOUR ENVIRONMENT
# where is the openmpi hostfile
HOSTFILE="$BASE_DIR/hostfile"
# how many cores per node
CORE_PER_NODE=16
# how many nodes do we have
N_NODES=8
##################


#### tests plan ####

# "1,100g,1m,1"
# 1 IOR process, writing 100g, using 1m blocksize, on 1 node
# then 1 md5sum process reads a single file of 100g

# "4,2g,1m,2"
# 4 IOR process, writing 2g *each*, using 1m blocksize, on 2 nodes
# then 4 md5sum processes read these 4 files of 2g each

# "10,100k,100k,10"
# IOR running on 10 cores of the server
# each IOR process writes a 100k file
# using 100k blocksize
# on 10 nodes

test_plan=(
	# total processes, filesize, transfersize, number of nodes
	"8,100k,100k,2"
	"16,100k,100k,4"
	"128,10m,1m,8"
)
###################

mpicc --version > $WORK_DIR/mpicc
lsof $BASE_DIR > $WORK_DIR/lsof


# create and change dir
mkdir -p $BASE_DIR && cd $BASE_DIR
mkdir -p $RESULT_DIR
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
        wget https://ftpmirror.gnu.org/parallel/parallel-20210522.tar.bz2
	tar -jxvf parallel-20210522.tar.bz2
        cd parallel-20210522
        ./configure --prefix=`pwd`/build &>> parallel_build.log
        make && make install
	cp $BASE_DIR/parallel-20210522/build/bin/* $BASE_DIR/bin
	rm -rf $BASE_DIR/ior_build
	rm -rf $BASE_DIR/parallel-*
	# drop client cache
	echo "sync; echo 3 > /proc/sys/vm/drop_caches" > $BASE_DIR/bin/drop_cache
	chmod +x $BASE_DIR/bin/drop_cache
fi

IOR=$BASE_DIR/bin/ior
MDTEST=$BASE_DIR/bin/mdtest
GNUP=$BASE_DIR/bin/parallel
DROPCACHE=$BASE_DIR/bin/drop_cache

mkdir -p $WORK_DIR && cd $WORK_DIR

# run ior
# run the test plan for this bunch of tests
for key in ${test_plan[@]}
do
	TOTAL_THREAD=`echo $key | cut -d"," -f1`
	FILESIZE=`echo $key | cut -d"," -f2`
	TRANSFERSIZE=`echo $key | cut -d"," -f3`
	N_NODES=`echo $key | cut -d"," -f4`
	PER_NODE=$((TOTAL_THREAD/N_NODES))
	# drop cache before run
	mpirun -np $N_NODES -npernode 1 --hostfile $HOSTFILE -oversubscribe --allow-run-as-root --mca btl self,tcp -display-map -display-allocation --bind-to core:overload-allowed bash $DROPCACHE
	# sleep a bit
	sleep 3
	# run
	mpirun -np $TOTAL_THREAD -npernode $PER_NODE --hostfile $HOSTFILE -oversubscribe --allow-run-as-root --mca btl self,tcp -display-map -display-allocation --bind-to core:overload-allowed $IOR -b $FILESIZE -t $TRANSFERSIZE -a POSIX \
		-wr -i1 -g -F -e -o $WORK_DIR/test -k \
		-O summaryFile=$WORK_DIR/ior.summary.threads-${TOTAL_THREAD}.nodes-${N_NODES}.filesize-${FILESIZE}.transfersize-${TRANSFERSIZE} > $WORK_DIR/ior.threads-${TOTAL_THREAD}.nodes-${N_NODES}.filesize-${FILESIZE}.transfersize-${TRANSFERSIZE}.out 2> $WORK_DIR/ior.threads-${TOTAL_THREAD}.nodes-${N_NODES}.filesize-${FILESIZE}.transfersize-${TRANSFERSIZE}.err

	# run gnu parallel
	case ${#TOTAL_THREAD} in
		1)
			$GNUP -j $PER_NODE --sshloginfile $HOSTFILE /usr/bin/time -v -o $WORK_DIR/md5sum.threads-${TOTAL_THREAD}.nodes-${N_NODES}.filesize-${FILESIZE}.\`hostname\`.{} md5sum $WORK_DIR/test.0000000{} ::: `seq -w 0 $((TOTAL_THREAD-1))`
			;;	
		2)
			$GNUP -j $PER_NODE --sshloginfile $HOSTFILE /usr/bin/time -v -o $WORK_DIR/md5sum.threads-${TOTAL_THREAD}.nodes-${N_NODES}.filesize-${FILESIZE}.\`hostname\`.{} md5sum $WORK_DIR/test.000000{} ::: `seq -w 00 $((TOTAL_THREAD-1))`
			;;
		3)
			$GNUP -j $PER_NODE --sshloginfile $HOSTFILE /usr/bin/time -v -o $WORK_DIR/md5sum.threads-${TOTAL_THREAD}.nodes-${N_NODES}.filesize-${FILESIZE}.\`hostname\`.{} md5sum $WORK_DIR/test.00000{} ::: `seq -w 000 $((TOTAL_THREAD-1))`
			;;
		4)
			$GNUP -j $PER_NODE --sshloginfile $HOSTFILE /usr/bin/time -v -o $WORK_DIR/md5sum.threads-${TOTAL_THREAD}.nodes-${N_NODES}.filesize-${FILESIZE}.\`hostname\`.{} md5sum $WORK_DIR/test.0000{} ::: `seq -w 0000 $((TOTAL_THREAD-1))`
			;;
	esac
	
	rm -rf $WORK_DIR/test.0*
done

# please choose carefully
# this mdtest will create a tree of 100 directories/files (-n)
# repeated 3 times (-i)
# every file/dir will be uniq
# write 200k for each file, and read it (-w -e)
# work in -d as root folder
HOW_MANY_FILES=25
for process in 8
do
	# drop cache before run
	mpirun -np $N_NODES -npernode 1 --hostfile $HOSTFILE -oversubscribe --allow-run-as-root --mca btl self,tcp -display-map -display-allocation --bind-to core:overload-allowed bash $DROPCACHE
	sleep 3
	mpirun -np $process -npernode 2 --hostfile $HOSTFILE -oversubscribe --allow-run-as-root --mca btl self,tcp -display-map -display-allocation --bind-to core:overload-allowed $MDTEST -n $HOW_MANY_FILES -i 3 -u -d $WORK_DIR/mdtest > $WORK_DIR/mdtest.thread-${process}_empty_files.out 2> $WORK_DIR/mdtest.thread-${process}_empty_files.err
	mpirun -np $N_NODES -npernode 1 --hostfile $HOSTFILE -oversubscribe --allow-run-as-root --mca btl self,tcp -display-map -display-allocation --bind-to core:overload-allowed bash $DROPCACHE	
	sleep 3
	mpirun -np $process -npernode 2 --hostfile $HOSTFILE -oversubscribe --allow-run-as-root --mca btl self,tcp -display-map -display-allocation --bind-to core:overload-allowed $MDTEST -n $HOW_MANY_FILES -i 3 -u -w 4k -e 4k -d $WORK_DIR/mdtest > $WORK_DIR/mdtest.thread-${process}_4k-files.out 2> $WORK_DIR/mdtest.thread-${process}_4k-files.err	
	mpirun -np $N_NODES -npernode 1 --hostfile $HOSTFILE -oversubscribe --allow-run-as-root --mca btl self,tcp -display-map -display-allocation --bind-to core:overload-allowed bash $DROPCACHE	
	sleep 3
	mpirun -np $process -npernode 2 --hostfile $HOSTFILE -oversubscribe --allow-run-as-root --mca btl self,tcp -display-map -display-allocation --bind-to core:overload-allowed $MDTEST -n $HOW_MANY_FILES -i 3 -u -w 32k -e 32k -d $WORK_DIR/mdtest > $WORK_DIR/mdtest.thread-${process}_32k-files.out 2> $WORK_DIR/mdtest.thread-${process}_32k-files.err		
done

cd $BASE_DIR
tar -zcvf $RESULT_DIR/$RUN_ID.tgz $RUN_ID
