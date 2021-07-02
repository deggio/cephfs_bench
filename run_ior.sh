#!/bin/bash

BASE_DIR="$HOME/cephfs_bench"
WORK_DIR="`mktemp -d $BASE_DIR/benchmark_XXXXXXX`"
RUN_ID=`basename $WORK_DIR`
RESULT_DIR="$BASE_DIR/RESULTS"

# THREAD
TOTAL_THREAD=`nproc`
# transfer size is fixed
TRANSFERSIZE=1m

mpicc --version > $WORK_DIR/mpicc
lsof $BASE_DIR > $WORK_DIR/lsof

#### tests plan ####

# "1,100g,1m"
# 1 IOR process, writing 100g, using 1m blocksize
# then 1 md5sum process reads a single file of 100g

# "4,2g,1m"
# 4 IOR process, writing 2g *each*, using 1m blocksize
# then 4 md5sum processes read these 4 files of 2g each

# "$TOTAL_THREAD,100k,100k"
# IOR running on all the cores of the server (TOTAL_THREAD == nproc)
# each IOR process writes a 100k file
# using 100k blocksize

test_plan=(
	"$TOTAL_THREAD,100k,100k"
	"$TOTAL_THREAD,200k,100k"	
	"$TOTAL_THREAD,1m,1m"		
	"$TOTAL_THREAD,2m,1m"		
	"$TOTAL_THREAD,8m,1m"			
	"1,1000m,1m"
	"2,1000m,1m"	
	"4,1000m,1m"		
	"8,1000m,1m"			
	"$TOTAL_THREAD,1000m,1"
	"1,8000m,1m"
	"1,16000m,1m"
	"1,64000m,1m"
	"1,100000m,1m"
	"1,100000m,1m"
	"1,200000m,1m"	
)
###################

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
fi

IOR=$BASE_DIR/bin/ior
GNUP=$BASE_DIR/bin/parallel

mkdir -p $WORK_DIR && cd $WORK_DIR

# run ior
# run the test plan for this bunch of tests
for key in ${test_plan[@]}
do
	TOTAL_THREAD=`echo $key | cut -d"," -f1`
	FILESIZE=`echo $key | cut -d"," -f2`
	TRANSFERSIZE=`echo $key | cut -d"," -f3`
	mpirun -np $TOTAL_THREAD --allow-run-as-root --mca btl self,tcp $IOR -b $FILESIZE -t $TRANSFERSIZE -a POSIX \
		-wr -i1 -g -F -e -o $WORK_DIR/test -k \
		-O summaryFile=$WORK_DIR/ior.summary.threads-${TOTAL_THREAD}.filesize-${FILESIZE}.transfersize-${TRANSFERSIZE}

	# run gnu parallel
	$GNUP -j $TOTAL_THREAD  /usr/bin/time -v -o $WORK_DIR/md5sum.threads-${TOTAL_THREAD}.filesize-${FILESIZE}.\`hostname\`.{} md5sum $WORK_DIR/test.000000{} ::: `seq -w 00 $((TOTAL_THREAD-1))`
	rm -rf $WORK_DIR/test.00000*
done

cd $BASE_DIR
tar -zcvf $RESULT_DIR/$RUN_ID.tgz $RUN_ID
