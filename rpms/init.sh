#!/bin/sh

if [ -d /root/rpms ]; then

  echo "Installing RPMs..."
  sudo rpm -Uvh /root/rpms/*.rpm

  # Don't do this if we're running it as part of image creation
  if [ -d "/root/spark-ec2" ]; then

    echo "RSYNC'ing /root/rpms to other cluster nodes..."
    parallel --quote rsync -e "ssh $SSH_OPTS" -az /root/rpms {}:/root ::: $SLAVES $OTHER_MASTERS

    echo "Installing RPMs on other cluster nodes..."
    for node in $SLAVES $OTHER_MASTERS; do
      echo -e "\n... Installing rpms on $node"
      ssh -t -t $SSH_OPTS root@$node "sudo rpm -Uvh /root/rpms/*.rpm" & sleep 0.3
    done
    wait
  fi

fi
