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
            ports = ["{{private_ipv4}}:5007:5007"]
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
}
