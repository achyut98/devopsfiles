#!/bin/bash
set -x

if [ -n "$TMPHOMEDIR" ]; then
    export HOME=$TMPHOMEDIR
fi

# check for alternate api server (i.e. region)
# if this is changed, make sure to change REGISTRY as well
if [ -z "$APISERVER" ]; then
    # defaults to us south
    export APISERVER="apiserverurl"
fi

# check if using an alternate deployment name
if [ -z "$DEPLOYMENTNAME" ]; then
    # default to the Helloword service deployment
    export DEPLOYMENTNAME="HelloWorldproject"
fi

# check if using an alternate deployment target
# if [ -z "$DEPLOYTARGET" ]; then
    # default to targeting dev
    # export DEPLOYTARGET="dev"
# fi
export DEPLOYMENTNAME=${DEPLOYMENTNAME}${DEPLOYTARGET}

# check for alternate name for the kube service on this deploy
if [ -z "$KUBESVCNAME" ]; then
    # default to the deployment name + "svc"
    export KUBESVCNAME="${DEPLOYMENTNAME}svc"
fi

# check for alternate image name
if [ -z "$IMAGENAME" ]; then
    # default is Helloword service image
    export IMAGENAME="devopsfiles"
fi

# check for alternate templates
if [ -z "$TEMPLATEPREFIX" ]; then
    # use the defaults
    export TEMPLATEPREFIX="`dirname $0`/tpl"
fi

# check for alternate deployment space
if [ -z "$SPACENAME" ]; then
    # default space is cloud dev
    export SPACENAME="devenvname"
fi

# check for alternate registry
if [ -z "$REGISTRY" ]; then
    
    export REGISTRY="registry.net"
fi

# check for alternate registry namespace
if [ -z "$REGISTRYNS" ]; then
    # default is clouddev registry namespace
    export REGISTRYNS="hellocode"
fi

# check for alternate cluster name
if [ -z "$CLUSTERNAME" ]; then
    # default clustername is "mycluster"
    export CLUSTERNAME="mycluster"
fi

# check for alternate port
if [ -z "$PORTNUMBER" ]; then
    # default port is 8080
    export PORTNUMBER="8080"
fi

# default kubectl?
if [ -z "$KUBECTL" ]; then
    # look for it in the path
    export KUBECTL="kubectl"
fi

# check build version parms
if [ -z "$BUILD_NUMBER" ]; then
    if [ -z "$BUILDVERSION" ]; then
        # nope, use timestamp for the build version
        export BUILDVERSION=`date +%Y%m%d%H%M%S`
    fi
else
    export BUILDVERSION=$BUILD_NUMBER
fi

# check to see that we have the plugins we need
bx plugin list | grep "container-service"
if [ $? != 0 ]; then
    #bx plugin install container-service -r Bluemix -f
bx plugin install -f https://jgarwdc06.us-east.containers.appdomain.cloud/container-service-linux-amd64-0.3.112
fi
bx plugin list | grep "container-registry"
if [ $? != 0 ]; then
    #bx plugin install container-registry -r Bluemix -f
bx plugin install -f https://jgarwdc06.us-east.containers.appdomain.cloud/container-registry-linux-amd64-0.1.404
fi


# if passed parameters, login
if [ -n "$APIKEY" ]; then
    # login using apikey
    bx login -a $APISERVER --apikey $APIKEY
elif [ -n "$USERID" ] && [ -n "$PWD" ]; then
    # login with userid and apikey
    bx login -a $APISERVER -u $USERID -p $PWD
fi

# set replicacount, based on target
if [ -z "$REPLICACOUNT" ]; then
    if [ "$DEPLOYTARGET" != "prod" ]; then
        # 2 replicas in non-prod
        export REPLICACOUNT=1
    else
        # 4 replicas in prod
        export REPLICACOUNT=1
    fi
fi

# check max memory size
if [ -z "$CONTAINERMEMMAX" ]; then
    # default max is 2GB - 2000Mi
    export CONTAINERMEMMAX="2000Mi"
fi

# check min memory size
if [ -z "$CONTAINERMEMMIN" ]; then
    # default min is 1/2GB - 500Mi
    export CONTAINERMEMMIN="500Mi"
fi

# set spring profile based on deploy target
if [ -z "$SPRINGPRFVALUE" ]; then
    if [ "$DEPLOYTARGET" == "prod" ]; then
        # in prod, use profile "prod"
        export SPRINGPRFVALUE="prod"
    elif [ "$DEPLOYTARGET" == "stg" ]; then
        # in staging, use "stage" profile
        export SPRINGPRFVALUE="stg"
    elif [ "$DEPLOYTARGET" == "qa" ]; then
        # in qa, use "test" profile
        export SPRINGPRFVALUE="test"
    else
        # default profile is "dev"
        export SPRINGPRFVALUE="dev"
    fi
fi

# make sure we're on the correct space
bx target --cf -s "$SPACENAME"

#export RUNTIMEPARAMS="file:/share/vol/files/"

# make sure correct targeting and login for cs and docker
if [ -z "$TARGETREGION" ]; then
    # using default datacenter for this region
    bx cs init
else
    # force specific datacenter
    bx cs init --host $TARGETREGION
fi

# should we build at all?
if [ "$SKIPBUILD" == "true" ]; then
    echo "Skipping build docker image"
else
    # build image, remote or local
    if [ "$USEREMOTEBUILD" == "true" ]; then
        # building docker image locally
        bx cr build -t $REGISTRY/$REGISTRYNS/$IMAGENAME:$BUILDVERSION .
    else
        # building docker image locally
        docker build -t $IMAGENAME:$BUILDVERSION .

        # run it locally for testing here
        if [ "$SKIPLOCALTEST" != "true" ]; then
            docker run -i -t  -p 8080:8080 $IMAGENAME:$BUILDVERSION
        fi

        # get docker login
        bx cr login

        # tag for push to cloud, then push it
        docker tag $IMAGENAME:$BUILDVERSION $REGISTRY/$REGISTRYNS/$IMAGENAME:$BUILDVERSION
        docker push $REGISTRY/$REGISTRYNS/$IMAGENAME:$BUILDVERSION
    fi
fi

# get cluster config for kubernetes access and set the env vars
$(bx cs cluster-config --export --admin $CLUSTERNAME)
RC=$?
if [ $RC -ne 0 ]; then
    echo "ERROR - failed to get the config for cluster $CLUSTERNAME"
    exit 1
fi

# always regen the deployment, let kube decide if initial or update!
# check if we need the volume mount template, or no volume
if [ ! -z "$VOLUMENAME" ] && [ ! -z "$VOLUMEMOUNTPOINT" ] && [ ! -z "$PVCNAME" ]; then
    echo "All Volume vars not empty, using volume template"
    cp ${TEMPLATEPREFIX}vol.yml.template ${DEPLOYMENTNAME}.yml

    # and replace the volume specific vars
    sed -i "s/VOLUMENAME_REPLACEME/$VOLUMENAME/g" ${DEPLOYMENTNAME}.yml
    sed -i "s/VOLUMEMOUNTPOINT_REPLACEME/${VOLUMEMOUNTPOINT//\//\\/}/g" ${DEPLOYMENTNAME}.yml
    sed -i "s/PVCNAME_REPLACEME/$PVCNAME/g" ${DEPLOYMENTNAME}.yml
else
    echo "Using non-volume template"
    cp ${TEMPLATEPREFIX}.yml.template ${DEPLOYMENTNAME}.yml
fi

# check service type (ingress/secure-ingress or nodeport)
if [ "$USEINGRESS" == "true" ] || [ "$USESECUREINGRESS" == "true" ]; then
    # copy over the service template (shared)
    cat ${TEMPLATEPREFIX}-svcing.yml.template >> ${DEPLOYMENTNAME}.yml
    # get hostname to use first
    if [ -z "$DEPLOYMENTHOSTNAME" ]; then
        export DEPLOYMENTHOSTNAME=`bx cs cluster-get $CLUSTERNAME | grep "Ingress subdomain:" | awk '{print $3}'`
        if [ -z "$DEPLOYMENTHOSTNAME" ]; then
            echo "ERROR - unable to find the cluster name automatically, please set DEPLOYMENTHOSTNAME to the hostname for your cluster"
            exit 2
        fi
        export DEPLOYMENTHOSTNAME="${DEPLOYMENTNAME}.${DEPLOYMENTHOSTNAME}"
    fi
    # only build ingress into the deploy if not configured to use an external one
    if [ "$EXTINGRESS" == "true" ]; then
        echo "External ingress config set, not including ingress in deployment"
        export BASEURL="unknown"
    else
        if [ "$USESECUREINGRESS" == "true" ]; then
            cat ${TEMPLATEPREFIX}-secingress.yml.template >> ${DEPLOYMENTNAME}.yml
            if [ -z "$TLSSECRET" ]; then
                export TLSSECRET=`bx cs cluster-get $CLUSTERNAME | grep "Ingress secret:" | awk '{print $3}'`
                if [ -z "$TLSSECRET" ]; then
                    echo "ERROR - unable to find the tls secret automatically, please set TLSSECRET to the Kubernetes secret name"
                    exit 3
                fi
            fi
            sed -i "s/TLSSECRET_REPLACEME/$TLSSECRET/g" ${DEPLOYMENTNAME}.yml
            export BASEURL="https://$DEPLOYMENTHOSTNAME"
            export URLTYPE="secure ingress"
        else
            cat ${TEMPLATEPREFIX}-ingress.yml.template >> ${DEPLOYMENTNAME}.yml
            export BASEURL="http://$DEPLOYMENTHOSTNAME"
            export URLTYPE="ingress"
        fi
    fi
    # set the hostname
    sed -i "s/HOSTNAME_REPLACEME/$DEPLOYMENTHOSTNAME/g" ${DEPLOYMENTNAME}.yml
    export BASEURL="${BASEURL}/"
else
    # include nodeport version of the service
    cat ${TEMPLATEPREFIX}-svcnp.yml.template >> ${DEPLOYMENTNAME}.yml
    export BASEURL=`bx cs workers $CLUSTERNAME | grep "kube-" | head -n 1 | awk '{print $2}'`
    export URLTYPE="nodeport"
fi
sed -i "s/IMAGENAME_REPLACEME/$REGISTRY\/$REGISTRYNS\/$IMAGENAME\:$BUILDVERSION/g" ${DEPLOYMENTNAME}.yml
sed -i "s/DEPLOYMENTNAME_REPLACEME/$DEPLOYMENTNAME/g" ${DEPLOYMENTNAME}.yml
sed -i "s/KUBESVCNAME_REPLACEME/$KUBESVCNAME/g" ${DEPLOYMENTNAME}.yml
sed -i "s/REPLICAS_REPLACEME/$REPLICACOUNT/g" ${DEPLOYMENTNAME}.yml
sed -i "s/PORTNUMBER_REPLACEME/$PORTNUMBER/g" ${DEPLOYMENTNAME}.yml
sed -i "s/RUNTIMEPARAMS_REPLACEME/$RUNTIMEPARAMS/g" ${DEPLOYMENTNAME}.yml
sed -i "s/SPRINGVALUE_REPLACEME/$SPRINGPRFVALUE/g" ${DEPLOYMENTNAME}.yml
sed -i "s/CONTAINERMEMMAX_REPLACEME/$CONTAINERMEMMAX/g" ${DEPLOYMENTNAME}.yml
sed -i "s/CONTAINERMEMMIN_REPLACEME/$CONTAINERMEMMIN/g" ${DEPLOYMENTNAME}.yml
$KUBECTL apply -f ${DEPLOYMENTNAME}.yml

if [ "$URLTYPE" == "nodeport" ]; then
    export NODEPORT=`$KUBECTL describe svc ${KUBESVCNAME} | grep "NodePort:" | awk '{print $3}' | awk -F"/" '{print $1}'`
    export BASEURL="$BASEURL:$NODEPORT"
fi

if [ "$EXTINGRESS" == "true" ]; then
    echo "Service $DEPLOYMENTNAME exposed through ingress via external config - URL not generated"
else
    echo "Service $DEPLOYMENTNAME exposed as type $URLTYPE on url $BASEURL"
fi
echo "  deployment file used is ${DEPLOYMENTNAME}.yml"