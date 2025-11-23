# n8n Auto-Deploy to Fly.io

Automated deployment system that monitors Docker Hub for new stable n8n releases and automatically deploys them to Fly.io using GitHub Actions.

## Overview

This repository contains a GitHub Actions workflow that:

- Checks Docker Hub daily for new stable n8n versions
- Compares the latest version with your currently deployed version
- Automatically deploys updates when a new stable version is available
- Preserves your existing configuration and data during updates

## Setup

### Prerequisites

- A Fly.io account with an existing n8n application deployed
- A GitHub repository with this workflow
- Fly.io CLI access token

### Configuration Steps

#### 1. Configure Fly.io API Token

The workflow requires a Fly.io API token to authenticate and deploy updates.

**Generate a Fly.io API Token:**

```bash
# Install flyctl if you haven't already
# See: https://fly.io/docs/hands-on/install-flyctl/

# Authenticate with Fly.io
flyctl auth login

# Create a new API token
flyctl tokens create deploy
```

**Add the token to GitHub Secrets:**

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `FLY_API_TOKEN`
5. Value: Paste the token from the previous step
6. Click **Add secret**

#### 2. Verify fly.toml Configuration

Ensure your `fly.toml` file is properly configured with your app name:

```toml
app = 'your-app-name'
```

The workflow will automatically detect your app name from this file.

#### 3. Enable the Workflow

The workflow is configured to run automatically. No additional setup is needed once the `FLY_API_TOKEN` secret is configured.

## Workflow Triggers

### Automatic (Scheduled)

The workflow runs automatically **daily at 2:00 AM UTC** to check for new versions.

To modify the schedule, edit `.github/workflows/deploy-n8n.yml`:

```yaml
on:
  schedule:
    - cron: "0 2 * * *" # Change this to your preferred schedule
```

Cron syntax examples:

- `0 2 * * *` - Daily at 2:00 AM UTC
- `0 */6 * * *` - Every 6 hours
- `0 0 * * 0` - Weekly on Sunday at midnight

### Manual

You can manually trigger the workflow at any time:

1. Go to your GitHub repository
2. Navigate to **Actions** tab
3. Select **Deploy n8n to Fly.io** workflow
4. Click **Run workflow**
5. Click the green **Run workflow** button

## How It Works

1. **Version Detection**: Queries Docker Hub API for the latest stable n8n version

   - Filters out pre-release versions (beta, alpha, rc)
   - Uses semantic versioning to identify the latest stable release

2. **Version Comparison**: Checks your currently deployed version on Fly.io

   - Compares using semantic versioning rules
   - Determines if an update is needed

3. **Deployment**: If a new version is available

   - Deploys the new Docker image to Fly.io
   - Preserves your existing `fly.toml` configuration
   - Maintains your data volume (no data loss)
   - Verifies deployment health after completion

4. **Reporting**: Logs all actions and creates a workflow summary
   - Success: Reports the deployed version
   - No update: Confirms you're already up to date
   - Failure: Provides detailed error information

## Monitoring

### View Workflow Runs

1. Go to your GitHub repository
2. Navigate to **Actions** tab
3. Click on **Deploy n8n to Fly.io** workflow
4. View individual workflow runs and their logs

### Workflow Summary

Each workflow run provides a summary showing:

- Current deployed version
- Latest available version
- Action taken (deployed, skipped, or failed)

## Troubleshooting

### Workflow Fails with "FLY_API_TOKEN secret is not configured"

**Problem**: The Fly.io API token is missing or not properly configured.

**Solution**:

1. Verify the secret is named exactly `FLY_API_TOKEN` (case-sensitive)
2. Ensure the token has deployment permissions
3. Try regenerating the token: `flyctl tokens create deploy`
4. Re-add the token to GitHub Secrets

### Workflow Fails with "Authentication failed"

**Problem**: The API token is invalid or has expired.

**Solution**:

1. Generate a new token: `flyctl tokens create deploy`
2. Update the `FLY_API_TOKEN` secret in GitHub with the new token
3. Re-run the workflow

### Workflow Fails with "Could not determine latest stable version"

**Problem**: Unable to query Docker Hub or parse version information.

**Solution**:

1. Check if Docker Hub is accessible: https://hub.docker.com/r/n8nio/n8n/tags
2. Review the workflow logs for specific error messages
3. The workflow will automatically retry on the next scheduled run

### Deployment Succeeds but Health Check Fails

**Problem**: The deployment completed but the application is not responding correctly.

**Solution**:

1. Check your Fly.io dashboard: https://fly.io/dashboard
2. View application logs: `flyctl logs`
3. Check application status: `flyctl status`
4. Fly.io's automatic rollback should restore the previous version
5. Review your `fly.toml` configuration for any issues

### No Deployment Triggered When Expected

**Problem**: A new version is available but the workflow didn't deploy it.

**Solution**:

1. Check the workflow logs to see the version comparison
2. Verify the new version is a stable release (not beta/alpha/rc)
3. Manually trigger the workflow to force a check
4. Review the version detection logic in the logs

### Workflow Doesn't Run on Schedule

**Problem**: The scheduled workflow is not executing.

**Solution**:

1. Ensure the workflow file is in the default branch (usually `main` or `master`)
2. Check that the repository is not archived or disabled
3. Verify the cron syntax is correct
4. Note: GitHub Actions may delay scheduled workflows during high load periods

## Configuration Preservation

The workflow is designed to preserve your existing configuration:

- **fly.toml**: All settings remain unchanged
- **Data Volume**: Your n8n workflows and data are preserved
- **Environment Variables**: All environment variables are maintained
- **Only the Docker image version is updated**

## Security

- API tokens are stored securely in GitHub Secrets
- Tokens are automatically masked in workflow logs
- The workflow uses minimal required permissions
- Concurrency control prevents simultaneous deployments

## Manual Deployment

If you need to deploy a specific version manually:

```bash
# Deploy a specific version
flyctl deploy --image n8nio/n8n:1.23.4

# Or deploy the latest version
flyctl deploy --image n8nio/n8n:latest
```

## Support

- **n8n Documentation**: https://docs.n8n.io/
- **Fly.io Documentation**: https://fly.io/docs/
- **GitHub Actions Documentation**: https://docs.github.com/en/actions

## License

This workflow configuration is provided as-is for use with your n8n deployment.
