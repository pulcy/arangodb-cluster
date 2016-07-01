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
                "/usr/share/ca-certificates/:/usr/share/ca-certificates/:ro"
            ]
            ports = [5007]
            args = [
            "--container=${container}",
            "--host=",
            "--instance=",
            "--role=agency",
            "--etcd-prefix=/pulcy/arangodb3/sample",
            "--etcd-url=http://${private_ipv4}:2379",
            ]
        }
    }
}
