#!/bin/bash

BASE_DIR="$HOME/cephfs_bench"
WORK_DIR="`mktemp -d $BASE_DIR/benchmark_XXXXXXX`"
RUN_ID=`basename $WORK_DIR`
RESULT_DIR="$BASE_DIR/RESULTS"


# THREAD
TOTAL_THREAD=`nproc`

## IOR parameters
# filesize (-b) is how much a single IOR thread will write/read
FILESIZE="1000m"
# transfer size (-t) is how much is used for I/O
TRANSFERSIZE="1m"

echo "print mpicc version"
mpicc --version
lsof $BASE_DIR

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
mpirun -np $TOTAL_THREAD --allow-run-as-root --mca btl self,tcp $IOR -b $FILESIZE -t $TRANSFERSIZE -a POSIX -wr -i1 -g -F -e -o $WORK_DIR/test -k -O summaryFile=$WORK_DIR/ior.summary.$RUN_ID

# run gnu parallel
$GNUP -j $TOTAL_THREAD  /usr/bin/time -v -o $WORK_DIR/md5sum.\`hostname\`.{} md5sum $WORK_DIR/test.000000{} ::: `seq -w 00 $((TOTAL_THREAD-1))`
rm -rf $WORK_DIR/test.00000*

cd $BASE_DIR
tar -zcvf $RESULT_DIR/$RUN_ID.tgz $RUN_ID
