#!/bin/bash

echo "Setting up slave on `hostname`..."

# Make sure we are in the spark-ec2 directory
cd /root/spark-ec2

# Must source these, because this script is run directly on slaves.
# This is not strictly necessary, but it allows variables to be overriden.
source ec2-variables.sh
if [[ -e ec2-user-variables.sh ]]; then
    source ec2-user-variables.sh
fi

# Defaults
VERBOSE=${VERBOSE-false}
EXT_MOUNT_OPTS=${EXT_MOUNT_OPTS-"defaults,noatime,nodiratime"}
DEVICE_PREFIX=${DEVICE_PREFIX-"xvd"}
XFS_MOUNT_OPTS=${XFS_MOUNT_OPTS-"defaults,noatime,nodiratime,allocsize=8m"}


# Disable Transparent Huge Pages (THP)
# THP can result in system thrashing (high sys usage) due to frequent defrags of memory.
# Most systems recommends turning THP off.
if [[ -e /sys/kernel/mm/transparent_hugepage/enabled ]]; then
  echo never > /sys/kernel/mm/transparent_hugepage/enabled
fi

# Set hostname based on EC2 private DNS name, so that it is set correctly
# even if the instance is restarted with a different private DNS name
PRIVATE_DNS=`wget -q -O - http://instance-data.ec2.internal/latest/meta-data/local-hostname`
hostname $PRIVATE_DNS
echo $PRIVATE_DNS > /etc/hostname
HOSTNAME=$PRIVATE_DNS  # Fix the bash built-in hostname variable too


#instance_type=$(curl http://169.254.169.254/latest/meta-data/instance-type 2> /dev/null)
#echo "Instance type: $instance_type"

function setup_instance_volume {

  device=$1
  mount_point=$2

  if [[ -e $device ]]; then

    if grep -qs "$mount_point" /proc/mounts; then
      umount $mount_point
    fi

    rm -rf $mount_point
    mkdir $mount_point

    # Check if device is already formatted
    if ! blkid $device; then
      echo "Formatting $device..."

      # To turn TRIM support on, uncomment the following line.
      #echo "$device $mount_point  ext4  defaults,noatime,nodiratime,discard 0 0" >> /etc/fstab

      # Format using ext4, which has the best performance among ext3, ext4, and xfs based
      # on our shuffle heavy benchmark
      mkfs.ext4 -E lazy_itable_init=0 $device
    else
      echo "$device appears to be formatted. Leaving as is."
      blkid $device
    fi

    echo "Mounting $device onto $mount_point..."
    mount -o $EXT_MOUNT_OPTS $device $mount_point

    # Make data dirs writable by non-root users, such as CDH's hadoop user
    chmod -R a+w $mount_point

  elif $VERBOSE; then
    echo "$device does not exist."
  fi
}

# This will hopefully work for most hvm instance types.
echo "Setting up ephemeral instance volumes..."

root_device="$(mount | grep 'on / type'| awk '{print $1}')"
all_disk_devs=(/dev/$DEVICE_PREFIX[a-z])
echo "Detected root device as: $root_device"
let count=0
for disk_dev in ${all_disk_devs[@]}; do
    if [[ $root_device != $disk_dev* ]]; then
        ((count++))
        mount_point=/mnt
        if [[ $count != 1 ]]; then
            mount_point="/mnt${count}"
        fi
        setup_instance_volume $disk_dev $mount_point
        echo "$disk_dev $mount_point"
    else
      echo "Skipping $disk_dev because it looks to be the root device."
    fi
done


function setup_ebs_volume {
  device=$1
  mount_point=$2
  if [[ -e $device ]]; then
    # Check if device is already formatted
    if ! blkid $device; then
      mkdir $mount_point
      yum install -q -y xfsprogs
      if mkfs.xfs -q $device; then
        mount -o $XFS_MOUNT_OPTS $device $mount_point
        chmod -R a+w $mount_point
      else
        # mkfs.xfs is not installed on this machine or has failed;
        # delete /vol so that the user doesn't think we successfully
        # mounted the EBS volume
        rmdir $mount_point
      fi
    else
      # EBS volume is already formatted. Mount it if its not mounted yet.
      if ! grep -qs '$mount_point' /proc/mounts; then
        mkdir $mount_point
        mount -o $XFS_MOUNT_OPTS $device $mount_point
        chmod -R a+w $mount_point
      fi
    fi
  elif $VERBOSE; then
    echo "$device does not exist."
  fi
}

# Format and mount EBS volume (/dev/sd[s, t, u, v, w, x, y, z]) as /vol[x] if the device exists
echo "Setting up EBS volumes..."
setup_ebs_volume /dev/sds /vol0
setup_ebs_volume /dev/sdt /vol1
setup_ebs_volume /dev/sdu /vol2
setup_ebs_volume /dev/sdv /vol3
setup_ebs_volume /dev/sdw /vol4
setup_ebs_volume /dev/sdx /vol5
setup_ebs_volume /dev/sdy /vol6
setup_ebs_volume /dev/sdz /vol7

# Alias vol to vol3 for backward compatibility: the old spark-ec2 script supports only attaching
# one EBS volume at /dev/sdv.
if [[ -e /vol3 && ! -e /vol ]]; then
  ln -s /vol3 /vol
fi


# Remove ~/.ssh/known_hosts because it gets polluted as you start/stop many
# clusters (new machines tend to come up under old hostnames)
rm -f /root/.ssh/known_hosts

# Create swap space on /mnt
/root/spark-ec2/create-swap.sh $SWAP_MB

# Allow memory to be over committed. Helps in pyspark where we fork
echo 1 > /proc/sys/vm/overcommit_memory

# Add github to known hosts to get git@github.com clone to work
# TODO(shivaram): Avoid duplicate entries ?
cat /root/spark-ec2/github.hostkey >> /root/.ssh/known_hosts

# /usr/bin/realpath now done on image
