#!/bin/bash

ETCDCTL=$(which etcdctl)
ETCD_PREFIX=/pulcy/arangodb3
ROLE=primary
LOGLEVEL=info
DATADIR=/var/lib/arangodb3

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

init_database() {
    if [ ! -f $DATADIR/SERVER ]; then
        echo "Initializing database...Hang on..."

        arangod \
            --server.statistics false \
            --frontend.version-check false \
            --server.authentication false \
            --server.endpoint=tcp://127.0.0.1:3333 \
            --database.directory $DATADIR \
            --log.file /tmp/init-log \
            --log.foreground-tty false &
        pid="$!"
        echo "arangod pid: $pid"

        counter=0
        ARANGO_UP=""
        while [ -z "$ARANGO_UP" ];do
            sleep 1

            if [ "$counter" -gt 100 ];then
                echo "ArangoDB didn't start correctly during init"
                cat /tmp/init-log
                exit 1
            fi
            let counter=counter+1
            version=$(curl --noproxy localhost -s http://localhost:3333/_api/version 2>/dev/null)
            if [ ! -z "$version" ]; then
                ARANGO_UP=1
                echo "Arango is up: $version"
            fi
        done

        for f in /docker-entrypoint-initdb.d/*; do
            case "$f" in
                *.sh)     echo "$0: running $f"; . "$f" ;;
                *.js)     echo "$0: running $f"; arangosh --javascript.execute "$f" ;;
                */dumps)    echo "$0: restoring databases"; for d in $f/*; do echo "restoring $d";arangorestore --server.endpoint=tcp://127.0.0.1:8529 --create-database true --include-system-collections true --input-directory $d; done; echo ;;
            esac
        done

        echo "Stopping init arangod with pid $pid"
        if ! kill -s TERM "$pid" || ! wait "$pid"; then
            echo >&2 'ArangoDB Init failed.'
            exit 1
        fi

        echo "Database initialized...Starting System..."
    fi
}

run_agency() {
    init_database
    eset "${ETCD_PREFIX}/agents/agency${INSTANCE_ID}" "$HOST:$PORT"
    ENDPOINTS=""
    NOTIFY=""
    if [ ${INSTANCE} -eq 3 ]; then
        get_agency_endpoints "--agency.endpoint"
        NOTIFY="--agency.notify true"
    fi
    exec arangod \
        --frontend.version-check false \
        --log.level "${LOGLEVEL}" \
        --database.directory $DATADIR \
        --server.endpoint "tcp://0.0.0.0:8529" \
        --server.authentication false \
        --server.statistics false \
        --cluster.my-address "tcp://$HOST:$PORT" \
        --agency.id "${INSTANCE_ID}" \
        --agency.size 3 \
        --agency.supervision true \
        --agency.wait-for-sync true \
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
    init_database
    wait_for_agency
    get_agency_endpoints "--cluster.agency-endpoint"
    exec arangod \
        --frontend.version-check false \
        --log.level "${LOGLEVEL}" \
        --database.directory $DATADIR \
        --server.authentication=false \
        --server.endpoint "tcp://0.0.0.0:8529" \
        --server.statistics false \
        --cluster.my-address "tcp://$HOST:$PORT" \
        --cluster.my-local-info "primary${INSTANCE_ID}" \
        --cluster.my-role "PRIMARY" \
        $ENDPOINTS
}

run_coordinator() {
    init_database
    wait_for_agency
    get_agency_endpoints "--cluster.agency-endpoint"
    exec arangod \
        --frontend.version-check false \
        --log.level="${LOGLEVEL}" \
        --database.directory $DATADIR \
        --server.authentication false \
        --server.endpoint="tcp://0.0.0.0:8529" \
        --server.statistics false \
        --cluster.my-address="tcp://$HOST:$PORT" \
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

mkdir -p $DATADIR
mkdir -p /var/lib/arangodb3-apps
chown -R arangodb $DATADIR
chown -R arangodb /var/lib/arangodb3-apps

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
