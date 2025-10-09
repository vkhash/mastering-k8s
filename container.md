# Description: Containerization workshop
####
## Install stress tool
sudo apt-get install stress cgroup-tools

#####
## Create a unified/cg1 cgroup
sudo mkdir /sys/fs/cgroup/unified
sudo mount -t cgroup2 none /sys/fs/cgroup/unified
sudo cgcreate -g cpuset,memory:unified/cg1
#####
## Check the cgroup
sudo cgget -g cpuset unified/cg1
sudo cgget -g memory unified/cg1

#####
## Set the CPU and memory limits
sudo cgset -r memory.max=100M unified/cg1
sudo cgexec -g cpu:unified/cg1 top
sudo cgset -r memory.max=100K unified/cg1

#####
## Run the stress tool
sudo cgexec -g cpu:unified/cg1 stress --cpu 2 --timeout 60
htop
sudo cgset -r cpuset.cpus=0-2 unified/cg1

#####
## Create a container rootfs
mkdir rootfs
docker run busybox
docker ps -a
docker export b70ea04e6ed7 | tar xf - -C rootfs
sudo unshare --pid --fork chroot rootfs sh
## Copy the stress tool to the rootfs
cp /usr/bin/stress rootfs
# Run the stress tool in the container
sudo cgexec -g cpu:unified/cg1 unshare --mount-proc --pid --fork chroot rootfs sh
####
#
## Create a container spec and run the container
runc spec
sudo runc run demo
