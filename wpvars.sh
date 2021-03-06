#!/bin/bash
#set -x

export APISERVER="apiserverurl"
export REGISTRY="registry.net"
export REGISTRYNS="helloworld"
export PORTNUMBER="8080"
export BUILDVERSION="$BUILD_NUMBER"
export SKIPLOCALTEST="true"
export APIKEY="@/wcloud/token/bxapikey.json"
export KUBECTL="/usr/local/bin/kubectl"
export CONTAINERMEMMIN="500Mi"
#export SPRINGPRFVALUE="dev"
export REPLICACOUNT=1
export CONTAINERMEMMAX="4000Mi"
export IMAGENAME="devopsfiles"
export DEPLOYMENTNAME="devopsfiles"
export DEPLOYTARGET="dev-v2"
export CLUSTERNAME="ClusterDev"
export USESECUREINGRESS="true"
#export SKIPBUILD="true"
export EXTINGRESS="true"
export VOLUMENAME="commonpropertiesvolume"
export VOLUMEMOUNTPOINT="/share/vol/files"
export PVCNAME="commonproperties"