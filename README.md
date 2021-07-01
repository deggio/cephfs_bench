# cephfs_bench

Small scripts to test a filesystem with IOR and md5sum. Tested on a Ubuntu 18.04.

The run_ior.sh script will
- download and build IOR
- download and build gnu parallel
- run IOR with fixed transfersize and filesize (edit them in the script)
- run md5sum on the files produced by IOR
- save results and pack them in an archive under the RESULT dir

For the requirement, please run:

    apt update
    apt install mpi-default-dev
    apt install autoconf
    apt install make

To run the script:

    git clone https://github.com/deggio/cephfs_bench.git
    cd cephfs_bench
    chmod +x run_ior.sh
    ./run_ior.sh
