#!/bin/sh

pushd /root

if [ -d "spark" ]; then
  echo "Spark seems to be installed. Exiting."
  return 0
fi

# Ensure these are set
echo "SPARK_VERSION=${SPARK_VERSION?}"
echo "HADOOP_VERSION=${HADOOP_VERSION?}"

if [ `python -c "print '$HADOOP_VERSION'[0:3] in ['2.4','2.5','2.6']"` == "True" ]; then
  HADOOP_PROFILE="hadoop-2.4"
else
  echo "Unknown hadoop profile. Exiting."
  return 1
fi

# Github tag:
if [[ "$SPARK_VERSION" == *\|* ]]
then

  # TODO find way of specifying Tachyon version in build via command line... probably not possible until they make it a property in their build.
  # TODO find way of selecting which modules to build, as we don't need all of them.

  repo=`python -c "print '$SPARK_VERSION'.split('|')[0]"`
  git_hash=`python -c "print '$SPARK_VERSION'.split('|')[1]"`

  echo "Building Spark from $repo, hash: $git_hash against Hadoop $HADOOP_VERSION using profile $HADOOP_PROFILE"
  mkdir spark
  pushd spark
  git init
  git remote add origin $repo
  git fetch origin
  git checkout $git_hash
  export MAVEN_OPTS="-Xmx2g -XX:MaxPermSize=512M -XX:ReservedCodeCacheSize=512m"
  # mvn install ??

  OPTS="-Pnetlib-lgpl" #for BLAS optimisations
  # Note: -Phadoop-provided causes failure when starting spark
  # Note: this takes a over an hour on an m3.medium, about 22 min on an m3.xlarge
  mvn -Pyarn -P$HADOOP_PROFILE -Dhadoop.version=${HADOOP_VERSION} $OPTS -DskipTests clean package
  popd

  # TODO re: BLAS - check whether so in there... and try building with sbt as per:
  #http://apache-spark-user-list.1001560.n3.nabble.com/MLLIB-usage-BLAS-dependency-warning-td18660.html


# Pre-packaged spark version:
else 

  echo "Getting pre-packaged Spark $SPARK_VERSION built against $HADOOP_PROFILE"
  wget http://s3.amazonaws.com/spark-related-packages/spark-$SPARK_VERSION-bin-$HADOOP_PROFILE.tgz

  echo "Unpacking Spark"
  tar xvzf spark-*.tgz > /tmp/spark-ec2_spark.log
  rm -f spark-*.tgz
  mv `ls -d spark-* | grep -v ec2` spark
fi

# Don't copy-dir if we're running this as part of image creation.
if [ -d "/root/spark-ec2" ]; then
  /root/spark-ec2/copy-dir /root/spark
fi

popd
