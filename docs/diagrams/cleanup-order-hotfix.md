# Shuffle cleanup ordering hotfix

This installer-only hotfix does not change the SOCLab runtime architecture.

It corrects teardown dependency order for the existing single-node Shuffle Swarm design:

1. Quiesce `shuffle-orborus` so it cannot recreate execution services during teardown.
2. Remove the old Shuffle/Wazuh Compose containers and project-owned resources.
3. Remove SOCLab-owned Swarm execution services such as `shuffle-workers` and app services.
4. Remove the external `shuffle_swarm_executions` overlay after no containers/services remain attached.
5. Preserve Docker Swarm membership itself.

Reason: Docker does not permit removal of a network while containers remain attached. `shuffle-backend` and `shuffle-orborus` are intentionally attached to the execution overlay in this architecture, so Compose teardown must precede overlay deletion.
