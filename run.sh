#!/bin/bash

DOCKER=$(which docker)
ETCDCTL=$(which etcdctl)
ETCD_PREFIX=/pulcy/arangodb3
ROLE=primary

need_docker() {
    if [ -z ${DOCKER} ]; then
        echo docker is not found
        exit 1
    fi
    if [ -z ${CONTAINER} ]; then
        echo CONTAINER is empty
        exit 1
    fi
    PORT=$(${DOCKER} port ${CONTAINER} 8259/tcp | cut -d ':' -f2)
    echo "Externally visible on '${HOST}:${PORT}'"
}

need_etcd() {
    if [ -z ${ETCDCTL} ]; then
        echo etcdctl is not found
        exit 1
    fi
    if [ -z ${ETCD_URL} ]; then
        echo ETCD_URL is empty
        exit 1
    fi
}

eset() {
    local key=$1
    local value=$2
    ${ETCDCTL} --endpoints=${ETCD_URL} set $key $value
}

els() {
    local key=$1
    ${ETCDCTL} --endpoints=${ETCD_URL} ls $key 2> /dev/null
}

need_instance() {
    if [ -z ${INSTANCE} ]; then
        echo INSTANCE is empty
        exit 1
    fi
    INSTANCE_ID=$[${INSTANCE}-1]
    echo "Using instance id: ${INSTANCE_ID}"
}

need_host() {
    if [ -z ${HOST} ]; then
        echo HOST is empty
        exit 1
    fi
}

get_agency_endpoints() {
    local key=$1
    agents=$(els ${ETCD_PREFIX}/agents/)
    ENDPOINTS=""
    for a in ${other}; do
        ENDPOINTS="$ENDPOINTS $key tcp://$a"
    done
    echo "Using endpoints: $ENDPOINTS"
}

run_agency() {
    eset "${ETCD_PREFIX}/agents/agency${INSTANCE_ID}" "$HOST:5007"
    get_agency_endpoints "--agency.endpoint"
    exec arangod \
        --server.endpoint "tcp://0.0.0.0:5007" \
        --server.authentication false \
        --agency.id "${INSTANCE_ID}" \
        --agency.size 3 \
        --agency.supervision true \
        $ENDPOINTS \
        --agency.notify true \
        "agency${INSTANCE_ID}"
}

run_primary() {
    get_agency_endpoints "--cluster.agency-endpoint"
    exec arangod \
        --server.authentication=false
        --server.endpoint "tcp://0.0.0.0:8529" \
        --cluster.my-address "tcp://$HOST:$PORT" \
        --cluster.my-local-info "primary${INSTANCE_ID}" \
        --cluster.my-role PRIMARY \
        $ENDPOINTS \
        "primary${INSTANCE_ID}"
}

run_coordinator() {
    get_agency_endpoints "--cluster.agency-endpoint"
    exec arangod \
        --server.authentication=false
        --server.endpoint "tcp://0.0.0.0:8529" \
        --cluster.my-address "tcp://$HOST:$PORT" \
        --cluster.my-local-info "coordinator${INSTANCE_ID}" \
        --cluster.my-role COORDINATOR \
        $ENDPOINTS \
        "coordinator${INSTANCE_ID}"
}

for i in "$@"
do
case $i in
    --container=*)
    CONTAINER="${i#*=}"
    ;;
    --host=*)
    HOST="${i#*=}"
    ;;
    --instance=*)
    INSTANCE="${i#*=}"
    ;;
    --role=*)
    ROLE="${i#*=}"
    ;;
    --etcd-prefix=*)
    ETCD_PREFIX="${i#*=}"
    ;;
    --etcd-url=*)
    ETCD_URL="${i#*=}"
    ;;
    *)
    echo "unknown option '${i}'"
    ;;
esac
done

need_docker
need_etcd
need_host
need_instance

case ${ROLE} in
    agency)
    run_agency
    ;;
    primary)
    run_primary
    ;;
    coordinator)
    run_coordinator
    ;;
    *)
    echo "unknown role '${ROLE}'"
    ;;
esac
