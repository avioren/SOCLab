# GitLab Workflow

## Authentication

Do not store GitLab passwords, personal access tokens, or SSH private keys in this repository or paste them into chat.

For local WSL development, prefer either:

```bash
glab auth login
```

or SSH authentication using a locally generated key whose **public** key is added to GitLab.

For ChatGPT-side GitLab access, use the GitLab connection/OAuth flow rather than sharing raw credentials.

## Branch model

- `main`: always deployable.
- Feature/fix branches: `feat/<name>` or `fix/<name>`.
- Merge Requests are required for changes to `main`.
- CI must pass before merge.
- Every installer incident should result in a regression test before the fix is merged.

## Initial repository push

After creating an empty GitLab project:

```bash
git init
git checkout -b main
git add .
git commit -m "Initial SOC lab installer"
git remote add origin git@gitlab.com:<group>/<project>.git
git push -u origin main
```

Replace `<group>/<project>` with the actual GitLab namespace and project path.


## Repository secret policy

Never commit GitLab tokens, SSH private keys, passwords, `.env` files, generated PEM/key files, or `/opt/soclab/state/credentials.txt`. The pipeline blocks commits that contain high-confidence secret formats or credential-like literal assignments. Runtime secrets stay on the lab host only.
