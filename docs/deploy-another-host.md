# Deploy SOCLab on Another Windows 11 Host

This guide reproduces SOCLab on another workstation using the same supported platform:

**Windows 11 -> WSL2 Ubuntu -> Docker Desktop with WSL2 integration -> Wazuh + Shuffle**

The repository contains the installer and configuration logic. Runtime credentials, GitLab credentials, generated certificates, tokens, and host-specific state are intentionally **not** included and must be created separately on every host.

## Important: use your own GitLab identity and repository access

If you import, fork, mirror, or develop this project through GitLab, you must configure GitLab using **your own GitLab account, credentials, SSH key or access token, namespace, and repository permissions**.

Do not reuse the original author's GitLab credentials, tokens, SSH keys, OAuth session, project access tokens, deploy tokens, or private repository URLs. They are not part of SOCLab and are not required to run the lab.

Never commit GitLab credentials or other secrets into this repository. Store authentication in your local Git/SSH credential configuration or GitLab's protected CI/CD variables as appropriate.

## 1. Prepare the Windows 11 host

Install WSL2 with an Ubuntu distribution from an elevated Windows terminal if it is not already available:

```powershell
wsl --install -d Ubuntu
```

Reboot Windows when requested, start Ubuntu, and complete the Linux user setup.

Install Docker Desktop for Windows and configure it to use the WSL2 backend. In Docker Desktop, enable WSL integration for the Ubuntu distribution that will run SOCLab.

SOCLab expects the Docker CLI, Docker Compose plugin, and Docker daemon to be reachable from inside Ubuntu/WSL2.

From Ubuntu, verify:

```bash
docker version
docker compose version
```

Both commands must succeed before continuing.

## 2. Confirm the host is suitable for SOCLab

The current lab profile expects at least:

- Windows 11
- WSL2 Ubuntu
- Docker Desktop with WSL2 integration
- 4 CPUs
- 8 GiB RAM minimum; more is recommended
- 50 GiB free storage available to WSL
- Internet access for source repositories and container registries during installation

### Dedicated Docker/Swarm requirement

The Docker Desktop engine should be dedicated to this SOCLab instance.

A clean SOCLab installation intentionally removes existing Swarm services on a validated **single-node Swarm**, tears down the previous lab, leaves that one-node Swarm, and creates a fresh one-node Swarm for Shuffle.

Do **not** run the installer against a Docker engine that hosts unrelated Swarm workloads. The installer refuses to reset a multi-node Swarm, but a one-node Swarm is treated as disposable SOCLab state.

## 3. Install basic tools inside WSL2

From Ubuntu:

```bash
sudo apt update
sudo apt install -y git curl ca-certificates
```

If you want to use the GitLab CLI for repository development, install `glab` using the method appropriate for your Ubuntu release, then authenticate with your own GitLab account.

## 4. Obtain the SOCLab repository

### Option A - clone the public GitHub repository for a local lab

For a read-only upstream copy used only to deploy the lab:

```bash
git clone https://github.com/avioren/SOCLab.git
cd SOCLab
```

This does not require the original author's GitLab account or credentials.

### Option B - import the project into your own GitLab

Use this option if you want the same GitLab CI, Merge Request, documentation, and diagram-as-code workflow under your own control.

Create or import a project in **your own GitLab namespace** using the public GitHub repository as the source, or create an empty GitLab project and push the cloned repository to it.

Example after cloning:

```bash
cd SOCLab
git remote rename origin upstream
git remote add origin git@gitlab.com:<your-namespace>/<your-project>.git
git push -u origin main
```

Replace `<your-namespace>/<your-project>` with a GitLab project that **you own or are authorized to access**.

Keep the public GitHub repository as an optional upstream reference:

```bash
git remote -v
```

A typical result is:

```text
origin   git@gitlab.com:<your-namespace>/<your-project>.git
upstream https://github.com/avioren/SOCLab.git
```

## 5. Configure GitLab authentication with your own credentials

Choose one local authentication method.

### GitLab CLI / OAuth

```bash
glab auth login
```

Authenticate to GitLab using **your own account** and confirm that account has access to your imported project.

### SSH

Generate a new SSH key on the new host if you do not already have an appropriate key:

```bash
ssh-keygen -t ed25519 -C "your-email@example.com"
cat ~/.ssh/id_ed25519.pub
```

Add only the **public key** to your own GitLab account. Keep the private key on the host and never commit it.

Test access:

```bash
ssh -T git@gitlab.com
git ls-remote origin
```

### Access tokens

If your workflow requires a personal, project, or deploy token, create it in **your own GitLab account/project** with only the permissions required for that workflow. Store it outside Git and use GitLab protected CI/CD variables for pipeline secrets.

Never copy a token into `README.md`, `.gitlab-ci.yml`, `.env`, shell scripts, screenshots, issues, Merge Requests, or chat messages.

## 6. Review the deployment before running it

From the repository root:

```bash
pwd
git status
git remote -v
docker version
docker compose version
```

Read the installation behavior before executing it:

```bash
less docs/installation.md
```

The installer writes SOCLab runtime state under `/opt/soclab` and generates runtime credentials locally. Those generated credentials are not retrieved from GitLab.

## 7. Install SOCLab

From Ubuntu/WSL2:

```bash
chmod +x install.sh
sudo ./install.sh install
```

The installer provisions the pinned Wazuh and Shuffle components, applies required Linux settings, creates the dedicated one-node Shuffle Swarm execution plane, and runs health gates.

## 8. Verify the new host

After installation:

```bash
./install.sh verify
./install.sh status
```

For the reusable health check:

```bash
./install.sh healthcheck
```

The deployment should not be considered complete until `verify`/`healthcheck` passes.

## 9. Retrieve local runtime credentials

Use the installer command:

```bash
./install.sh credentials
```

The generated credential inventory is stored locally at:

```text
/opt/soclab/state/credentials.txt
```

It is intentionally excluded from Git. Do not push it to GitHub or GitLab.

## 10. Keep your GitLab project and the public upstream separate

If you use your own GitLab project for development, pull public SOCLab updates from the GitHub upstream intentionally rather than replacing your GitLab credentials or remote configuration.

Example:

```bash
git fetch upstream
git checkout main
git merge upstream/main
```

Review and test upstream changes before merging them into your own environment.

## What is portable and what is host-specific

Portable through Git:

- installer code
- tests
- documentation
- CI definitions
- architecture and product-story diagrams
- non-secret configuration templates

Created independently on each host/account:

- GitLab identity and repository permissions
- GitLab OAuth sessions, SSH keys, and access tokens
- runtime passwords and API credentials
- generated TLS material
- `.env` files
- `/opt/soclab` runtime data
- Docker volumes, containers, networks, and Swarm state

This separation is intentional: cloning the repository reproduces the **product definition and automation**, while the new host creates its own trusted runtime and authentication context.
