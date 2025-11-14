# Security Best Practices: Container Registry Authentication

This guide documents secure credential management, authentication patterns, and security validation procedures for multi-registry Docker image publishing.

---

## Authentication Mechanisms

### GITHUB_TOKEN (Primary Authentication)

**What it is**: Automatically generated token provided by GitHub Actions in every workflow run.

**Permissions**:
- By default: Can read public and internal repositories
- With `packages:write` scope: Can also publish packages to GitHub Container Registry (GHCR)

**How to configure** (in `.github/workflows/build-image.yml`):
```yaml
permissions:
  contents: read
  packages: write  # Required for GHCR push

jobs:
  build-arch:
    permissions:
      packages: write  # Inherited from workflow
    steps:
      - name: Log in to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}      # GitHub Actions username (bot)
          password: ${{ secrets.GITHUB_TOKEN }}  # Automatic token
```

**Advantages**:
- Automatic: No configuration required
- Isolated: Token only valid for workflow run
- Rotated: Changes on every workflow run
- Logged: All actions traceable to workflow

**Scope**: GHCR only (not Docker Hub or other registries)

**Rate limits**: 500 requests/hour for package registry (per-user, not per-token)

---

### Repository Secrets (PAT Authentication)

**What they are**: Personal Access Tokens (PATs) stored securely in GitHub repository settings.

**When to use**: Adding credentials for Docker Hub, Quay.io, or other registries.

**How to create** (GitHub personal access token):
1. Go to GitHub Settings → Developer settings → Personal access tokens
2. Click "Generate new token (classic)"
3. Select scopes:
   - `write:packages` - For pushing to registries
   - `read:packages` - For pulling from private registries (if needed)
4. Generate token
5. Copy token (cannot see again after closing page)

**How to configure** (in GitHub repository):
1. Go to repository Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `DOCKER_HUB_PAT` (or custom name)
4. Value: Paste GitHub PAT
5. Click "Add secret"

**How to use** (in `.github/workflows/build-image.yml`):
```yaml
      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          registry: docker.io
          username: ${{ secrets.DOCKER_HUB_USERNAME }}  # Set in repo secrets
          password: ${{ secrets.DOCKER_HUB_PAT }}       # Set in repo secrets
```

**Example secrets configuration**:
```
DOCKER_HUB_USERNAME = "myusername"
DOCKER_HUB_PAT = "ghp_..."  # 40+ character token
QUAY_USERNAME = "quay_user"
QUAY_PAT = "..."
```

**Advantages**:
- Flexible: Works with any registry
- Controllable: Can rotate anytime
- Scoped: Can limit permissions per token
- Logged: Activity traceable to token

**Important**: Tokens are stored encrypted in GitHub, visible only in workflow logs if accidentally logged.

---

## Credential Storage Patterns

### Do's (Secure Practices)

1. **Use GitHub repository secrets for all credentials**:
   ```yaml
   password: ${{ secrets.MY_TOKEN }}  # Correct
   ```

2. **Use GITHUB_TOKEN for GHCR**:
   ```yaml
   password: ${{ secrets.GITHUB_TOKEN }}  # Correct - automatic
   ```

3. **Store long-lived secrets in repository secrets**:
   - GitHub Settings → Secrets and variables

4. **Use least-privilege scopes**:
   - Only grant `write:packages` if pushing
   - Don't grant `delete:packages` unless needed
   - Don't grant `admin` scope

5. **Rotate credentials regularly**:
   - Monthly or quarterly recommended
   - Immediately if leaked or compromised

6. **Use short-lived tokens when possible**:
   - GitHub Personal Access Tokens (classic) are permanent
   - GitHub Personal Access Tokens (fine-grained) support expiration (beta)

### Don'ts (Insecure Practices)

**Never do these**:

```yaml
# WRONG: Hardcoded credentials
password: ghp_abc123def456...  # Don't hardcode!

# WRONG: Credentials in environment variables without secrets
env:
  PASSWORD: "token123"  # Don't put in env!

# WRONG: Credentials as workflow input
workflow_dispatch:
  inputs:
    token:
      description: 'API token'
      required: true  # Don't do this!

# WRONG: Embedding in Dockerfile
RUN docker login -u user -p token123  # Never in Dockerfile!

# WRONG: Embedding in shell script that's committed
#!/bin/bash
docker login -u user -p ghp_abc123...  # Never commit!
```

---

## Multi-Registry Configuration

### GHCR (GitHub Container Registry) - Primary

**When to use**: Always - primary registry for this project

**Configuration**:
```yaml
      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Push image to GHCR
        run: |
          docker buildx build \
            --tag ghcr.io/${{ github.repository }}/{image}:latest \
            --push \
            {image}
```

**Advantages**:
- Automatic authentication (no secrets needed)
- Integrated with GitHub (same account)
- Good rate limits (500 req/hr per user)
- No additional setup

---

### Docker Hub - Secondary

**When to use**: Additional distribution channel (optional)

**Setup steps**:
1. Create Docker Hub account (docker.com)
2. Create Docker Hub Personal Access Token:
   - Docker Hub → Account Settings → Security → New Access Token
3. Add to repository secrets:
   - `DOCKER_HUB_USERNAME`
   - `DOCKER_HUB_PAT`

**Configuration**:
```yaml
      - name: Log in to Docker Hub
        uses: docker/login-action@v3
        with:
          username: ${{ secrets.DOCKER_HUB_USERNAME }}
          password: ${{ secrets.DOCKER_HUB_PAT }}

      - name: Push image to Docker Hub
        run: |
          docker buildx build \
            --tag docker.io/${{ secrets.DOCKER_HUB_USERNAME }}/{image}:latest \
            --push \
            {image}
```

**Note**: Docker Hub rate limits are strict for free tier (100 pulls per 6 hours). Use authenticated requests to increase limit to 500 pulls per 6 hours.

---

### Quay.io - Secondary

**When to use**: Alternative registry (optional)

**Setup steps**:
1. Create Quay.io account (quay.io)
2. Create OAuth token:
   - Account Settings → Generate encrypted password
3. Add to repository secrets:
   - `QUAY_USERNAME`
   - `QUAY_PAT`

**Configuration**:
```yaml
      - name: Log in to Quay.io
        uses: docker/login-action@v3
        with:
          registry: quay.io
          username: ${{ secrets.QUAY_USERNAME }}
          password: ${{ secrets.QUAY_PAT }}

      - name: Push image to Quay.io
        run: |
          docker buildx build \
            --tag quay.io/${{ secrets.QUAY_USERNAME }}/{image}:latest \
            --push \
            {image}
```

---

## Security Validation Checklist

Use this checklist to audit credential security after workflow changes.

### Pre-Commit (Before Pushing)

- [ ] No hardcoded credentials in code
  ```bash
  # Search for common patterns
  grep -r "ghp_" .github/workflows/ --include="*.yml"
  grep -r "password:" .github/workflows/ --include="*.yml" | grep -v "\${"
  grep -r "token:" .github/workflows/ --include="*.yml" | grep -v "\${"
  ```

- [ ] No secrets in shell scripts
  ```bash
  grep -r "secrets" .github/scripts/ --include="*.sh"
  # Should only appear in comments or usage documentation
  ```

- [ ] Workflow uses secrets correctly
  ```bash
  grep "secrets\." .github/workflows/build-image.yml
  # Should show: ${{ secrets.GITHUB_TOKEN }}, ${{ secrets.DOCKER_HUB_PAT }}, etc.
  ```

### Post-Commit (After Merging)

- [ ] No secrets in git history
  ```bash
  # Check recent commits for credential patterns
  git log -p --all -S "ghp_" -- .github/  # Search for leaked PAT
  git log -p --all -S "password:" -- .github/workflows/
  ```

- [ ] Repository secrets configured correctly
  - Go to repo Settings → Secrets and variables
  - Verify all needed secrets are present:
    - GITHUB_TOKEN (automatic, don't add)
    - DOCKER_HUB_PAT (if using Docker Hub)
    - QUAY_PAT (if using Quay.io)

### Workflow Execution

- [ ] Secrets not logged in workflow output
  - GitHub Actions automatically masks secrets in logs
  - Verify no `***` replacements suggest credential leaks:
    ```bash
    # In workflow logs, secrets should be masked:
    Log in with password: ***
    # NOT: Log in with password: ghp_abc123...
    ```

- [ ] GITHUB_TOKEN has correct permissions
  - Workflow run summary should show `packages: write`
  - Without it: GHCR push will fail with 403 Unauthorized

---

## Incident Response: Credential Leak

If you suspect credentials were exposed, follow these steps immediately.

### Step 1: Detect Leak

**Symptoms**:
- Unauthorized push to container registry
- Suspicious commit in build history
- Unexpected builds from unknown sources
- Unknown images pushed to registry

**Detection commands**:
```bash
# Check git history for credentials
git log -p --all -S "ghp_" -- .

# Check workflow logs (if still visible)
# GitHub Actions → Workflow run → Job logs
# Search for credential patterns

# Check container registry for unauthorized images
# GHCR → Packages → Look for unfamiliar tags
```

### Step 2: Immediate Containment (First 5 minutes)

1. **Revoke compromised token**:
   ```bash
   # For GitHub PAT:
   # GitHub Settings → Developer settings → Personal access tokens
   # Click "Delete" on compromised token
   # Token becomes invalid immediately
   ```

2. **Revoke registry credentials** (if not GitHub PAT):
   ```bash
   # For Docker Hub:
   # Docker Hub → Account Settings → Security
   # Regenerate Access Token
   # Old token becomes invalid

   # For Quay.io:
   # Quay.io → Account Settings → Generate new password
   ```

3. **Disable workflow temporarily** (if affected):
   ```bash
   # Edit .github/workflows/build-image.yml
   on:
     push:
       branches: [] # Disable workflow temporarily
   git commit -m "security: temporarily disable workflow due to credential leak"
   git push
   ```

### Step 3: Audit (Next 30 minutes)

1. **Check all builds in last 24 hours**:
   ```bash
   # Review workflow runs
   # GitHub Actions → All workflows → Look for suspicious activity
   # Check build history files for unauthorized entries
   ```

2. **Review registry activity logs**:
   - GHCR: repository → Activity log
   - Docker Hub: Account → Security → Activity
   - Look for pushes from unknown IP addresses or times

3. **Check for lateral movement**:
   - Did attacker push to other repositories?
   - Did attacker modify Dockerfiles?
   - Check git log for unauthorized commits:
     ```bash
     git log --all --format="%an %ae" | sort -u
     # Look for unfamiliar commit authors
     ```

### Step 4: Remediation (Next 1-2 hours)

1. **Rotate all credentials**:
   ```bash
   # GitHub: Create new PAT (Settings → Developer settings)
   # Docker Hub: Generate new token (Account → Security)
   # Update repository secrets with new tokens
   ```

2. **Update workflow with new credentials**:
   - No code changes needed (uses secrets)
   - Just update repository secrets

3. **Force re-build with new credentials**:
   ```bash
   # Make minor change to trigger rebuild
   echo "# Rebuilt after credential rotation" >> README.md
   git add README.md
   git commit -m "chore: force rebuild after credential rotation"
   git push
   # Verify new builds use correct credentials (check logs)
   ```

### Step 5: Post-Incident Review (Next 24 hours)

1. **Verify no unauthorized images remain**:
   ```bash
   # List all images in registry
   # GHCR API: GET /user/packages/container/{package-name}/versions
   # Docker Hub: docker hub registry or API
   # Look for unexpected tags or images
   ```

2. **Enable security scanning** (if available):
   - GHCR: Enable "Enable container scanning"
   - Check for suspicious image layers

3. **Document incident**:
   - When discovered
   - How credentials were exposed
   - Impact (what was compromised)
   - Remediation taken
   - Prevention measures

4. **Update security practices** (if lesson learned):
   - Add to incident review notes
   - Update this documentation if applicable

---

## Token Scope Reference

### GITHUB_TOKEN (GitHub Actions)

Automatically provided in workflows with `permissions: packages: write`

**Scopes** (by `permissions`):
```yaml
permissions:
  contents: read        # Read repo contents
  packages: write       # Push to GHCR
  pull-requests: read   # Read PR info
```

**Never needs manual rotation** (changes per workflow run)

### Personal Access Tokens (GitHub)

**Scope selection** (create at github.com/settings/tokens):
- ✅ `write:packages` - Required for pushing to GHCR
- ✅ `read:packages` - Required for pulling private registries
- ❌ `delete:packages` - Don't grant unless needed (cleanup)
- ❌ `admin` - Never grant unless absolutely necessary

**Rotation**: Every 3-6 months recommended, or immediately if compromised

### Docker Hub Tokens

**Type**: Personal Access Token (classic), not password

**Permissions**: Not granular (all or nothing)

**Rotation**: Every 3-6 months recommended

### Quay.io Tokens

**Type**: Application tokens

**Permissions**: Not granular at token level (set at organization level)

**Rotation**: Every 3-6 months recommended

---

## Compliance and Audit

### Principle: Least Privilege

Each credential should have **minimum permissions needed**:
- GHCR: `write:packages` (not `admin`)
- Docker Hub: Push-only token (no delete, no admin)
- Quay.io: Organization-specific permissions

### Audit Trail

All authenticated actions are logged:
- GitHub Actions: Workflow logs (visible to repo members)
- GHCR: Package activity logs
- Docker Hub: Account security activity
- Quay.io: Organization audit logs

**Best practice**: Review logs monthly for unusual activity

### Compliance Checklist

- [ ] No hardcoded credentials in repository
- [ ] All credentials stored in repository secrets
- [ ] GITHUB_TOKEN used for GHCR (automatic)
- [ ] PATs used for other registries (rotated monthly)
- [ ] Credentials scoped to minimum permissions
- [ ] Workflow logs don't expose secrets
- [ ] All activity auditable and logged
- [ ] Incident response plan documented and tested

---

## Resources

- [GitHub Secrets Documentation](https://docs.github.com/en/actions/security-guides/using-secrets-in-github-actions)
- [GitHub Container Registry (GHCR)](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Docker Hub Personal Access Tokens](https://docs.docker.com/docker-hub/access-tokens/)
- [Quay.io Application Tokens](https://docs.quay.io/api/swagger/?url=https://docs.quay.io/api/swagger/swagger-v2.json)

---

## Questions?

- Review the project documentation in `docs/` for workflow details
- Open an issue with security concerns (use private disclosure if applicable)
