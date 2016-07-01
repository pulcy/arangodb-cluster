#!/bin/bash

ETCDCTL=$(which etcdctl)
ETCD_PREFIX=/pulcy/arangodb3
ROLE=primary
LOGLEVEL=info

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

eget() {
    local key=$1
    ${ETCDCTL} --endpoints=${ETCD_URL} get $key
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
    if [ -z ${PORT} ]; then
        echo PORT is empty
        exit 1
    fi
}

get_agency_endpoints() {
    local key=$1
    agents=$(els ${ETCD_PREFIX}/agents/)
    ENDPOINTS=""
    for agentid in ${agents}; do
        addr=$(eget $agentid)
        ENDPOINTS="$ENDPOINTS $key tcp://$addr"
    done
    echo "Using endpoints: $ENDPOINTS"
}

run_agency() {
    eset "${ETCD_PREFIX}/agents/agency${INSTANCE_ID}" "$HOST:$PORT"
    ENDPOINTS=""
    NOTIFY=""
    if [ ${INSTANCE} -eq 3 ]; then
        get_agency_endpoints "--agency.endpoint"
        NOTIFY="--agency.notify true"
    fi
    exec arangod \
        --log.level "${LOGLEVEL}" \
        --server.endpoint "tcp://0.0.0.0:$PORT" \
        --server.authentication false \
        --agency.id "${INSTANCE_ID}" \
        --agency.size 3 \
        --agency.supervision true \
        $NOTIFY $ENDPOINTS
}

run_primary() {
    get_agency_endpoints "--cluster.agency-endpoint"
    exec arangod \
        --server.authentication=false
        --server.endpoint "tcp://0.0.0.0:$PORT" \
        --cluster.my-address "tcp://$HOST:$PORT" \
        --cluster.my-local-info "primary${INSTANCE_ID}" \
        --cluster.my-role PRIMARY \
        --log.level "${LOGLEVEL}" \
        $ENDPOINTS
}

run_coordinator() {
    get_agency_endpoints "--cluster.agency-endpoint"
    exec arangod \
        --server.authentication=false
        --server.endpoint "tcp://0.0.0.0:$PORT" \
        --cluster.my-address "tcp://$HOST:$PORT" \
        --cluster.my-local-info "coordinator${INSTANCE_ID}" \
        --cluster.my-role COORDINATOR \
        --log.level "${LOGLEVEL}" \
        $ENDPOINTS
}

for i in "$@"
do
case $i in
    --host=*)
    HOST="${i#*=}"
    ;;
    --port=*)
    PORT="${i#*=}"
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
    --log-level=*)
    LOGLEVEL="${i#*=}"
    ;;
    *)
    echo "unknown option '${i}'"
    ;;
esac
done

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
