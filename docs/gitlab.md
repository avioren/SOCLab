# GitLab Workflow

## Authentication - use your own GitLab credentials

**Every person importing, cloning, mirroring, or developing SOCLab through GitLab must configure GitLab with their own identity and access.**

Use your own:

- GitLab account
- project/group namespace
- repository permissions
- OAuth/`glab` login
- SSH key, or access token when required
- protected CI/CD variables for pipeline secrets

Do not use, request, copy, or depend on the original author's passwords, personal access tokens, SSH private keys, OAuth session, deploy tokens, project access tokens, or private repository credentials. None of those credentials are part of this project.

Do not store GitLab passwords, personal/project access tokens, deploy tokens, CI secrets, or SSH private keys in this repository or paste them into chat.

For local WSL development, prefer either:

```bash
glab auth login
```

or SSH authentication using a locally generated key whose **public** key is added to your own GitLab account.

For ChatGPT-side GitLab access, connect your own GitLab account through the GitLab connection/OAuth flow rather than sharing raw credentials.

Before pushing, verify that the repository remote belongs to a namespace you control or are authorized to use:

```bash
git remote -v
git ls-remote origin
```

See [Deploy SOCLab on Another Windows 11 Host](deploy-another-host.md) for a complete GitHub clone -> personal GitLab import -> Windows 11/WSL2 deployment workflow.

## Branch model

- `main`: always deployable.
- Feature/fix branches: `feat/<name>` or `fix/<name>`.
- Merge Requests are required for changes to `main`.
- CI must pass before merge.
- Every installer incident should result in a regression test before the fix is merged.

## Initial repository push

After creating an empty project in **your own GitLab namespace**:

```bash
git init
git checkout -b main
git add .
git commit -m "Initial SOC lab installer"
git remote add origin git@gitlab.com:<your-group>/<your-project>.git
git push -u origin main
```

Replace `<your-group>/<your-project>` with the GitLab namespace and project path that **you own or have explicit permission to write to**.

## Importing the public SOCLab repository into your own GitLab

A convenient model is to keep GitHub as the public/read-only upstream and your GitLab project as your development origin:

```bash
git clone https://github.com/avioren/SOCLab.git
cd SOCLab
git remote rename origin upstream
git remote add origin git@gitlab.com:<your-group>/<your-project>.git
git push -u origin main
git remote -v
```

Authenticate `origin` using your own GitLab account before pushing.

## Repository secret policy

Never commit GitLab tokens, SSH private keys, passwords, `.env` files, generated PEM/key files, or `/opt/soclab/state/credentials.txt`. The pipeline blocks commits that contain high-confidence secret formats or credential-like literal assignments. Runtime secrets stay on the lab host only.
