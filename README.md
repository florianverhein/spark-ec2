# spark-ec2 for Data Science

This repository contains a set of scripts used to setup a functional data science cluster on EC2 using the Spark stack and common data science tools.

The focus is on reliability, stability, speed of cluster deployment and code-as-configuration.

There are two parts to this:
* Automatically build and register an AMI that is pre-configured as much as possible, starting with a CentOS 6 minimal image.
* Deploy and configure a working cluster (on top of this AMI) as fast as possible

This work is based on [spark-ec2](https://github.com/mesos/spark-ec2) and forks, but has diverged considerably. Please see the README.md there for additional details. 

As of this writing, these scripts are compatible with recent versions of [spark/ec2](https://github.com/apache/spark/blob/master/ec2/).

## Components

### Modules

spark-ec2 modules:

* Spark in standalone mode (yarn not yet enabled)
* Tachyon
* Hadoop DFS running on the instances' local disks.
* Ganglia cluster monitoring

Generic modules for customisation:

* [rpms](./rpms) - supports RPM installation and initialisation (optional - for additional software)
* [extra](./extra) - supports extra `init.sh`, `setup.sh` and `test.sh` scripts by delegation (optional - for even greater flexibility)

Spark, Tachyon, HDFS and Ganglia are configured to work together by these scripts. By default, they are pre-installed on the image in order to optimise cluster start time.
The default versions are: `Spark 1.2`, `Tachyon 0.5`, `Protobuf 2.5.0` and `Hadoop 2.4.1`. These are *compiled from source against each other* to ensure compatibility and to get the 
native hadoop libraries. 
You may change these versions or use pre-built distributions, but be aware of the dependencies between them and with the configuration files in [./templates](./templates).

`rpms` and `extra` are generic modules. These allow you to further customise the cluster at deployment time without code changes.
For example, install extra RPMs, install additional R libraries, install an entirely new module, etc...
**Aside**: In theory, it should also be possible to do this at image build time if you add an appropriate file provisioner in the packer configuration.  

### Data Science Software
 
These are installed on the image, mostly from source:

* Python 2.7 and SciPy libraries
* R (TODO add libraries)
* Vowpal Wabbit


## Usage

Build the image according to [the README.md here](./packer).

Obtain a recent version of `spark/ec2/` from [Spark](https://github.com/apache/spark) (clone it). Make sure it supports the 
`--spark-ec2-git-repo` and `--spark-ec2-git-branch` arguments. This should be the case in `master` and in the (yet to be released as of this writing) 1.4 and later releases. 
If it does not (or you choose a different version), you will need to modify `spark_ec2.py` to clone this repo and branch instead of the hard coded one. 
 
Run `spark_ec2.py`, being sure to pass the new image id using the `--ami` argument and pointing `--spark-ec2-git-repo` and `--spark-ec2-git-branch` at this repo and branch.

### Advanced

To make use of the `rpms` or `extra` modules, first place files in `/some_path/root/rpms/` or `/some_path/root/extra/` as appropriate. Then 
use `--deploy-root-dir /some_path`, which will copy them to the cluster, where they will be detected and used.
**NOTE**: Requires `[SPARK-5641]`.

## Details

This assumes you are familiar with how [spark-ec2](https://github.com/mesos/spark-ec2) works.

The primary structural differences are: 

* The modules' optional `init.sh` scripts can be run as part of the image build. They are always run at cluster deploy time.
 They will detect the situation and act appropriately. 
 This is the mechanism that allows you to decide what you want on the AMI vs what is installed at deployment time. 
* The modules' optional `setup.sh` scripts generally start services and do anything that cannot be done at image build time. 
 Typically, these require information that is only available at deployment time, such as the list of masters and slaves, etc. 
 They should not be used to install software.  
* The modules' optional `test.sh` scripts are run after all the setup is complete. They allow simple tests/checks of the cluster modules. 

