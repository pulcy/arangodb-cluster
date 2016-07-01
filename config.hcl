job "arangodb3_sample" {

    group "agency" {
        count = 3
        constraint {
            attribute = "meta.core"
            value = "true"
        }

        task "agency" {
            image = "pulcy/arangodb-cluster:latest"
            volumes = [
                "/etc/ssl/:/etc/ssl/:ro",
                "/usr/share/ca-certificates/:/usr/share/ca-certificates/:ro",
                "/usr/bin/etcdctl:/usr/bin/etcdctl:ro",
            ]
            ports = ["{{private_ipv4}}:5007:8529"]
            args = [
                "--host={{private_ipv4}}",
                "--port=5007",
                "--instance=${instance}",
                "--role=agency",
                "--etcd-prefix=/pulcy/arangodb3/sample",
                "--etcd-url=http://{{private_ipv4}}:2379",
            ]
        }
    }

    group "server" {
        count = 2
        constraint {
            attribute = "meta.arangodb"
            value = "1"
        }

        task "db" {
            image = "pulcy/arangodb-cluster:latest"
            volumes = [
                "/etc/ssl/:/etc/ssl/:ro",
                "/usr/share/ca-certificates/:/usr/share/ca-certificates/:ro",
                "/usr/bin/etcdctl:/usr/bin/etcdctl:ro",
            ]
            ports = ["{{private_ipv4}}:5008:8529"]
            args = [
                "--host={{private_ipv4}}",
                "--port=5008",
                "--instance=${instance}",
                "--role=primary",
                "--etcd-prefix=/pulcy/arangodb3/sample",
                "--etcd-url=http://{{private_ipv4}}:2379",
            ]
        }

        task "coordinator" {
            image = "pulcy/arangodb-cluster:latest"
            volumes = [
                "/etc/ssl/:/etc/ssl/:ro",
                "/usr/share/ca-certificates/:/usr/share/ca-certificates/:ro",
                "/usr/bin/etcdctl:/usr/bin/etcdctl:ro",
            ]
            ports = ["{{private_ipv4}}:5009:8529"]
            args = [
                "--log-level=info",
                "--host={{private_ipv4}}",
                "--port=5008",
                "--instance=${instance}",
                "--role=coordinator",
                "--etcd-prefix=/pulcy/arangodb3/sample",
                "--etcd-url=http://{{private_ipv4}}:2379",
            ]
        }
    }
}
