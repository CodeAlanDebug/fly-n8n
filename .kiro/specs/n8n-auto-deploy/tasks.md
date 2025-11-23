# Implementation Plan

- [x] 1. Create GitHub Actions workflow structure

  - Create `.github/workflows/deploy-n8n.yml` file
  - Configure workflow triggers (schedule and workflow_dispatch)
  - Set up concurrency control to prevent simultaneous deployments
  - Define required environment variables and secrets
  - _Requirements: 5.1, 5.3, 5.4_

- [x] 2. Implement version detection from Docker Hub

  - [x] 2.1 Create function to query Docker Hub API for n8n tags

    - Query `https://hub.docker.com/v2/repositories/n8nio/n8n/tags` endpoint
    - Handle API errors and network failures gracefully
    - Parse JSON response to extract tag names
    - _Requirements: 1.1, 1.4_

  - [x] 2.2 Write property test for API error handling

    - **Property 4: API Error Handling**
    - **Validates: Requirements 1.4**

  - [x] 2.3 Create function to filter stable versions

    - Filter out tags containing pre-release identifiers (-, beta, alpha, rc)
    - Filter out non-semantic version tags (latest, next)
    - Return only valid semantic version tags
    - _Requirements: 1.3_

  - [x] 2.4 Write property test for pre-release filtering

    - **Property 3: Pre-release Version Filtering**
    - **Validates: Requirements 1.3**

  - [x] 2.5 Create function to find latest semantic version

    - Sort versions using semantic versioning rules
    - Return the highest version number
    - _Requirements: 1.2, 2.4_

  - [x] 2.6 Write property test for semantic version comparison

    - **Property 2: Semantic Version Comparison Correctness**
    - **Validates: Requirements 1.2**

  - [x] 2.7 Write property test for latest version selection
    - **Property 8: Latest Version Selection**
    - **Validates: Requirements 2.4**

- [x] 3. Implement current version detection from Fly.io

  - [x] 3.1 Install and configure Fly.io CLI in workflow

    - Add step to install flyctl
    - Configure authentication using FLY_API_TOKEN secret
    - _Requirements: 3.1_

  - [x] 3.2 Write property test for API token usage

    - **Property 9: API Token Usage**
    - **Validates: Requirements 3.1**

  - [x] 3.3 Create function to query current deployed version

    - Execute `flyctl status --json` command
    - Parse JSON output to extract current image tag
    - Handle cases where app is not deployed
    - _Requirements: 2.2_

  - [x] 3.4 Write property test for authentication failure handling
    - **Property 10: Authentication Failure Handling**
    - **Validates: Requirements 3.2**

- [x] 4. Implement version comparison logic

  - [x] 4.1 Create function to compare current vs latest version

    - Use semantic version comparison
    - Return boolean indicating if update is needed
    - _Requirements: 1.2, 2.1, 2.2_

  - [x] 4.2 Write property test for deployment trigger logic

    - **Property 5: Deployment Trigger on New Version**
    - **Validates: Requirements 2.1**

  - [x] 4.3 Write property test for no-deployment scenario
    - **Property 6: No Deployment When Versions Match**
    - **Validates: Requirements 2.2**

- [x] 5. Implement deployment logic

  - [x] 5.1 Create deployment function using Fly.io CLI

    - Execute `flyctl deploy --image n8nio/n8n:${VERSION}` command
    - Use existing fly.toml configuration
    - Wait for deployment completion
    - _Requirements: 2.3, 6.1, 6.3_

  - [x] 5.2 Write property test for correct image tag usage

    - **Property 7: Deployment Uses Correct Image Tag**
    - **Validates: Requirements 2.3**

  - [x] 5.3 Write property test for configuration preservation

    - **Property 16: Configuration File Preservation**
    - **Validates: Requirements 6.1**

  - [x] 5.4 Write property test for image-only updates

    - **Property 18: Image-Only Updates**
    - **Validates: Requirements 6.3**

  - [x] 5.5 Implement post-deployment health verification

    - Wait for Fly.io health checks to pass
    - Verify service is accessible
    - _Requirements: 6.4_

  - [x] 5.6 Write property test for health verification

    - **Property 19: Post-Deployment Health Verification**
    - **Validates: Requirements 6.4**

  - [x] 5.7 Write property test for volume preservation
    - **Property 17: Volume Mount Preservation**
    - **Validates: Requirements 6.2**

- [x] 6. Implement logging and status reporting

  - [x] 6.1 Add logging for version check results

    - Log current version and latest available version
    - Log decision to deploy or skip
    - _Requirements: 4.3_

  - [x] 6.2 Add logging for deployment success

    - Log successful deployment with version number
    - _Requirements: 4.1_

  - [x] 6.3 Write property test for success logging

    - **Property 12: Success Logging Includes Version**
    - **Validates: Requirements 4.1**

  - [x] 6.4 Add logging for deployment failures

    - Log detailed error information
    - Include Fly.io CLI error output
    - _Requirements: 4.2_

  - [x] 6.5 Write property test for failure logging

    - **Property 13: Failure Logging Includes Error Details**
    - **Validates: Requirements 4.2**

  - [x] 6.6 Create workflow summary output

    - Summarize actions taken (checked, deployed, skipped)
    - Include version information
    - _Requirements: 4.3_

  - [x] 6.7 Write property test for workflow summary
    - **Property 14: Workflow Summary Completeness**
    - **Validates: Requirements 4.3**

- [x] 7. Implement security measures

  - [x] 7.1 Verify secret masking in logs

    - Ensure FLY_API_TOKEN is never exposed in logs
    - Test that GitHub Actions masks the secret automatically
    - _Requirements: 3.4_

  - [x] 7.2 Write property test for secret masking

    - **Property 11: Secret Masking in Logs**
    - **Validates: Requirements 3.4**

  - [x] 7.3 Add error handling for missing secrets
    - Check if FLY_API_TOKEN is set
    - Fail early with clear error message if missing
    - _Requirements: 3.2_

- [x] 8. Integrate all components into complete workflow

  - [x] 8.1 Wire together all workflow steps

    - Connect version detection, comparison, and deployment steps
    - Add conditional logic to skip deployment when not needed
    - Ensure proper error propagation between steps
    - _Requirements: 5.2_

  - [x] 8.2 Write property test for complete execution flow

    - **Property 15: Complete Execution Flow**
    - **Validates: Requirements 5.2**

  - [x] 8.3 Add workflow step names and descriptions
    - Use clear, descriptive names for each step
    - Add comments explaining complex logic
    - _Requirements: 4.4_

- [x] 9. Checkpoint - Ensure all tests pass

  - Ensure all tests pass, ask the user if questions arise.

- [x] 10. Create documentation

  - [x] 10.1 Document workflow setup in README

    - Explain how to configure FLY_API_TOKEN secret
    - Document workflow triggers and schedule
    - Provide troubleshooting guidance

  - [x] 10.2 Add inline comments to workflow file
    - Explain each major step
    - Document any non-obvious logic
    - Include links to relevant documentation
