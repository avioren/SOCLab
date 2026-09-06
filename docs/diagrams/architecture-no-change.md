# Architecture impact: none

This change fixes installer teardown behavior only. It does not change the SOCLab steady-state topology, component boundaries, network model, or single-node Docker Swarm architecture.

For clean-install reliability, SOCLab now treats the existing one-node Swarm as disposable lab state. Cleanup first verifies that the local host is an active Swarm manager and that the Swarm contains exactly one node. It then stops Shuffle Orborus, removes every Swarm service object, waits for service removal, deletes residual Swarm task containers, tears down the Wazuh/Shuffle Compose projects, and runs `docker swarm leave --force` to clear stale Raft/service/overlay state. The later Shuffle installation step initializes a fresh one-node Swarm and recreates ingress plus `shuffle_swarm_executions`.

This is necessary because deleting a Swarm task container does not delete its owning service: the Swarm manager reconciles desired state and spawns a replacement task. Removing the service object (and, for a full clean install, resetting the dedicated one-node Swarm) prevents `frikky/shuffle-tools` and other dynamically created Shuffle app tasks from respawning during cleanup.

The destructive reset is refused if the existing Swarm has more than one node or the local Docker engine is not the manager. No global Docker system/image/volume prune is used.

The upstream Shuffle source/runtime tree under `/opt/soclab/Shuffle` is not modified by this repository change.
