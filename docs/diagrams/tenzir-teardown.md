# Tenzir teardown ownership

Status: **adopted for the single-host SOCLab**

Shuffle/Orborus creates `tenzir-node` as a standalone Docker container on a dedicated bridge network named `tenzir-network`. It is not guaranteed to be represented as a Docker Swarm service and it is not guaranteed to be attached to `shuffle_shuffle` or `shuffle_swarm_executions`.

Because of that, clean install/reset must not rely on Swarm-service cleanup or Shuffle-overlay membership to remove Tenzir.

Required teardown order:

```text
stop/quiesce Orborus
        ↓
remove Swarm services and residual Swarm tasks
        ↓
remove tenzir-node explicitly
        ↓
remove any residual containers on tenzir-network
        ↓
remove tenzir-network
        ↓
stop/remove Compose projects
        ↓
leave/reset the old dedicated one-node Swarm
        ↓
rebuild clean runtime
```

Installer invariants:

- `tenzir-node` must be removed with `docker rm -f -v` when present.
- `tenzir-network` must be removed during clean install/reset.
- Cleanup fails if either `tenzir-node` or `tenzir-network` still exists after teardown.
- Absence of `tenzir-node` and `tenzir-network` is a successful cleanup state; Docker's expected non-zero `inspect` status for an absent object must not propagate as a function failure under `set -e`.
- Tenzir remains enabled for the rebuilt Shuffle runtime.
- No upstream Shuffle source files are modified.

The return-status correction does not change the runtime topology or teardown ordering; it only makes the implemented health/cleanup semantics match the architecture above.
