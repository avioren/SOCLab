# Personas & Jobs To Be Done

## SOC Analyst
**Job:** When an alert fires, help me understand the context and move to a defensible action without reconstructing the entire workflow manually.

**Friction:** disconnected tools, unclear workflow state, weak evidence continuity.

**Success signal:** fewer manual steps between alert and decision; provable workflow completion.

## SOC Lead
**Job:** When the environment changes, help me know the operating flow still works and that important decisions are auditable.

**Friction:** integration drift, stale documentation, hidden architecture assumptions.

**Success signal:** faster diagnosis of broken contracts; material changes accompanied by product/architecture evidence.

## Security Engineer
**Job:** When a dependency fails, help me identify the broken contract and recover without guesswork.

**Friction:** a process or container can be running while the actual product journey is broken.

**Success signal:** repeatable deployment/rebuild and actionable health output.

## Current product fit

SOCLab already serves the **Security Engineer** persona strongly through install/reset/verify workflows, health gates, port/API/network contracts, regression tests, and recovery documentation. The **SOC Analyst** outcome remains partially unproven until a committed end-to-end detection-to-Shuffle scenario exists.
