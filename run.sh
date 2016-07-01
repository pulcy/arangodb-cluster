#!/bin/bash

ETCDCTL=$(which etcdctl)
ETCD_PREFIX=/pulcy/arangodb3
ROLE=primary
LOGLEVEL=info

export ARANGO_NO_AUTH=1

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
        --server.endpoint "tcp://0.0.0.0:8529" \
        --server.authentication false \
        --cluster.my-address "tcp://$HOST:$PORT" \
        --agency.id "${INSTANCE_ID}" \
        --agency.size 3 \
        --agency.supervision true \
        --agency.wait-for-sync false \
        $NOTIFY $ENDPOINTS
}

wait_for_agency() {
    echo "Waiting for agency..."
    while true ; do
        has_ready_agents=""
        agents=$(els ${ETCD_PREFIX}/agents/)
        for agentid in ${agents}; do
            addr=$(eget $agentid)
            curl -s -f -X GET "http://$addr/_api/version" > /dev/null 2>&1
            if [ "$?" != "0" ] ; then
                echo Server on address $addr does not answer yet.
            else
                echo Server on address $addr is ready for business.
                has_ready_agents="1"
                break
            fi
        done
        if [ ! -z "$has_ready_agents" ]; then
            break
        fi
        sleep 1
    done
}

run_primary() {
    wait_for_agency
    get_agency_endpoints "--cluster.agency-endpoint"
    exec arangod \
        --log.level "${LOGLEVEL}" \
        --server.authentication false \
        --server.endpoint "tcp://0.0.0.0:8529" \
        --cluster.my-address "tcp://$HOST:$PORT" \
        --cluster.my-local-info "primary${INSTANCE_ID}" \
        --cluster.my-role "PRIMARY" \
        $ENDPOINTS
}

run_coordinator() {
    wait_for_agency
    get_agency_endpoints "--cluster.agency-endpoint"
    exec arangod \
        --log.level "${LOGLEVEL}" \
        --server.authentication false \
        --server.endpoint "tcp://0.0.0.0:8529" \
        --cluster.my-address "tcp://$HOST:$PORT" \
        --cluster.my-local-info "coordinator${INSTANCE_ID}" \
        --cluster.my-role "COORDINATOR" \
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
