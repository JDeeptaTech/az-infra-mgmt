Refined Jenkins Pipeline for PR Validation and Tagged Releases
This Jenkinsfile is designed for a Jenkins Multibranch Pipeline project, which automatically detects branches and Pull Requests.

5.1. Jenkinsfile (Jenkinsfile)
Groovy

// Jenkinsfile for Trunk-Based Terraform Development with GitHub Flow Releases

pipeline {
    // Agent definition: Use a Docker image with Terraform pre-installed.
    agent {
        docker {
            image 'hashicorp/terraform:1.7.5' // Always use a specific, stable version!
            args '-u root' // Run as root inside the container for potential permissions issues
        }
    }

    // Environment variables for Terraform and cloud provider access.
    environment {
        // Example for AWS. Adjust for Azure/GCP.
        AWS_ACCOUNT_CREDS = credentials('aws-terraform-global') // Replace with your Jenkins AWS Credentials ID
        TF_VAR_environment_name = "" // Will be set dynamically by stages
        // GITHUB_TOKEN for GitHub Release Plugin (if needed, map from credentials)
        // GITHUB_RELEASE_PAT = credentials('github-pat-for-releases') // Example if using env var instead of direct credentialId
    }

    // No parameters for automated PR/Merge flows, as they are triggered by Git events.
    // Manual parameters for ad-hoc 'plan'/'destroy' could be added if needed,
    // but for true CI/CD, keeping it event-driven is cleaner.

    stages {
        // Stage 1: Checkout Code
        stage('Checkout') {
            steps {
                script {
                    checkout scm
                    echo "Checking out code from branch: ${env.BRANCH_NAME}"
                    // For tag builds, Jenkins automatically checks out the commit associated with the tag
                }
            }
        }

        // --- Pull Request Validation Flow ---
        stage('PR Validation') {
            when {
                // This entire stage block runs only when a Pull Request is detected.
                // env.CHANGE_ID is typically set by Jenkins Multibranch Pipeline for PRs.
                expression { env.CHANGE_ID != null }
            }
            stages {
                stage('Determine PR Environment') {
                    steps {
                        script {
                            // For PRs, we typically plan against a non-destructive environment
                            // or a dedicated 'pr-validation' environment.
                            // For this example, let's assume 'dev' is safe for PR plans.
                            env.DEPLOY_ENVIRONMENT = 'dev'
                            env.TF_VAR_environment_name = env.DEPLOY_ENVIRONMENT
                            echo "Detected Pull Request. Planning against: ${env.DEPLOY_ENVIRONMENT} environment."
                        }
                    }
                }
                stage('Terraform Init (PR)') {
                    steps {
                        sh "cd environments/${env.DEPLOY_ENVIRONMENT} && terraform init"
                    }
                }
                stage('Validate & Format (PR)') {
                    steps {
                        sh "cd environments/${env.DEPLOY_ENVIRONMENT} && terraform fmt -check -diff" // Fails if not formatted
                        sh "cd environments/${env.DEPLOY_ENVIRONMENT} && terraform validate" // Fails on syntax/config errors
                        // Optional: Add static analysis tools for PRs
                        // sh "tflint environments/${env.DEPLOY_ENVIRONMENT}"
                        // sh "checkov -d environments/${env.DEPLOY_ENVIRONMENT}"
                    }
                }
                stage('Terraform Plan (PR)') {
                    steps {
                        sh "cd environments/${env.DEPLOY_ENVIRONMENT} && terraform plan -out=tfplan -var=\"environment_name=${env.DEPLOY_ENVIRONMENT}\""
                        sh "cd environments/${env.DEPLOY_ENVIRONMENT} && terraform show -no-color tfplan > tfplan.txt"
                        archiveArtifacts artifacts: "environments/${env.DEPLOY_ENVIRONMENT}/tfplan.txt"
                    }
                }
                // No 'apply' or 'destroy' for PRs - they are for validation only.
            }
        }

        // --- Main Branch / Release Flow ---
        stage('Main Branch / Release Actions') {
            when {
                // This entire stage block runs only when we are on the 'main' branch
                // and it's NOT a Pull Request (i.e., it's a direct merge or a tag push).
                allOf {
                    branch 'main' // Only runs for the main branch
                    expression { env.CHANGE_ID == null } // Exclude PRs
                }
            }
            stages {
                stage('Determine Main Branch Environment') {
                    steps {
                        script {
                            if (env.TAG_NAME != null) {
                                // This is a Git Tag push on main, signifying a Production release.
                                env.DEPLOY_ENVIRONMENT = 'prod'
                                echo "Detected Git Tag '${env.TAG_NAME}' on main branch. Initiating PRODUCTION deployment."
                            } else {
                                // This is a merge to main (not a tag), for Continuous Deployment to Staging.
                                env.DEPLOY_ENVIRONMENT = 'staging'
                                echo "Detected merge to main branch. Initiating STAGING deployment."
                            }
                            env.TF_VAR_environment_name = env.DEPLOY_ENVIRONMENT
                            echo "Terraform environment variable set to: ${env.TF_VAR_environment_name}"
                        }
                    }
                }
                stage('Terraform Init (Main)') {
                    steps {
                        sh "cd environments/${env.DEPLOY_ENVIRONMENT} && terraform init"
                    }
                }
                stage('Validate & Format (Main)') {
                    // Re-validate on main, just in case (though PR checks should catch most issues)
                    steps {
                        sh "cd environments/${env.DEPLOY_ENVIRONMENT} && terraform fmt -check -diff"
                        sh "cd environments/${env.DEPLOY_ENVIRONMENT} && terraform validate"
                    }
                }
                stage('Terraform Plan (Main)') {
                    steps {
                        sh "cd environments/${env.DEPLOY_ENVIRONMENT} && terraform plan -out=tfplan -var=\"environment_name=${env.DEPLOY_ENVIRONMENT}\""
                        sh "cd environments/${env.DEPLOY_ENVIRONMENT} && terraform show -no-color tfplan > tfplan.txt"
                        archiveArtifacts artifacts: "environments/${env.DEPLOY_ENVIRONMENT}/tfplan.txt"
                    }
                }
                stage('Manual Approval for Production Apply') {
                    when {
                        // Only for production deployments triggered by a tag
                        expression { env.DEPLOY_ENVIRONMENT == 'prod' }
                    }
                    steps {
                        script {
                            timeout(time: 30, unit: 'MINUTES') {
                                input message: "Review the Terraform plan for PRODUCTION environment (Tag: ${env.TAG_NAME}):\n${readFile('environments/' + env.DEPLOY_ENVIRONMENT + '/tfplan.txt')}\n\nProceed with PRODUCTION apply?",
                                      id: 'proceed-prod-apply', submitter: 'release-managers,ops-lead'
                            }
                        }
                    }
                }
                stage('Terraform Apply') {
                    steps {
                        script {
                            // Apply if not a PR and action is 'apply' (which is determined by branch/tag)
                            echo "Applying Terraform plan for ${env.DEPLOY_ENVIRONMENT}..."
                            sh "cd environments/${env.DEPLOY_ENVIRONMENT} && terraform apply -auto-approve tfplan -var=\"environment_name=${env.DEPLOY_ENVIRONMENT}\""
                        }
                    }
                }
                stage('Create GitHub Release') {
                    when {
                        // Only create a GitHub Release when a tag is pushed to 'main' and deployed to prod
                        expression { env.TAG_NAME != null && env.DEPLOY_ENVIRONMENT == 'prod' }
                    }
                    steps {
                        script {
                            // Ensure GitHub Release Plugin is installed in Jenkins
                            // Ensure a Jenkins 'Secret text' credential with a GitHub PAT ('repo' scope) exists.
                            // Credential ID: 'github-pat-for-releases'
                            def releaseBody = "Terraform infrastructure changes for release ${env.TAG_NAME} to ${env.DEPLOY_ENVIRONMENT} environment.\n\n" +
                                              "See tfplan.txt artifact from Jenkins build #${env.BUILD_NUMBER} for details."
                            // You might want to generate a changelog here dynamically based on commits since last tag.

                            // Use the Jenkins GitHub Release Plugin step
                            createGitHubRelease(
                                credentialId: 'github-pat-for-releases', // Replace with your GitHub PAT credential ID
                                repository: "${env.GIT_ORGANIZATION}/${env.GIT_REPO}", // Automatically set by Jenkins for GitHub projects
                                tag: env.TAG_NAME,
                                name: "Release ${env.TAG_NAME}",
                                body: releaseBody,
                                prerelease: false,
                                draft: false
                            )
                            echo "GitHub Release '${env.TAG_NAME}' created."
                        }
                    }
                }
            }
        }
    }

    // Post-pipeline actions, e.g., for success/failure notifications and cleanup
    post {
        always {
            script {
                echo "Pipeline finished for ${env.BRANCH_NAME}."
                // Clean up .terraform directories and plan files for the specific environment processed
                if (env.DEPLOY_ENVIRONMENT) { // Ensure DEPLOY_ENVIRONMENT was set
                    sh "rm -rf environments/${env.DEPLOY_ENVIRONMENT}/.terraform"
                    sh "rm -f environments/${env.DEPLOY_ENVIRONMENT}/tfplan"
                    sh "rm -f environments/${env.DEPLOY_ENVIRONMENT}/tfplan.txt"
                }
            }
        }
        success {
            echo "Pipeline succeeded!"
            // Add success notification (e.g., Slack, Email)
        }
        failure {
            echo "Pipeline failed!"
            // Add failure notification (e.g., Slack, Email)
        }
    }
}
5.2. Key Improvements and Rationale:
Clear when Conditions for Stages:

PR Validation Stage: The entire stage block (and its nested stages) is wrapped in a when { expression { env.CHANGE_ID != null } }. This ensures all validation steps (init, fmt, validate, plan) only run for Pull Requests.
Main Branch / Release Actions Stage: This stage block explicitly runs when { allOf { branch 'main'; expression { env.CHANGE_ID == null } } }. This means it only triggers for direct merges to main or tag pushes to main, effectively separating the deployment logic from PR validation.
Dynamic DEPLOY_ENVIRONMENT and TF_VAR_environment_name:

A dedicated Determine PR Environment stage for PRs sets DEPLOY_ENVIRONMENT to dev (or a PR-specific sandbox).
A Determine Main Branch Environment stage for main branch builds intelligently sets DEPLOY_ENVIRONMENT to staging for merges and prod for tag pushes. This centralizes the logic for environment mapping.
No Parameters for Automated Flow:

Removed parameters for ACTION and TARGET_ENVIRONMENT from the primary pipeline block. This encourages an event-driven CI/CD model where the pipeline's behavior is determined by the Git event (PR, merge, tag). If you still need manual override for ad-hoc plan/destroy, you could add them back, but they should be used with extreme caution and strong approval gates.
Consolidated Terraform Actions:

Terraform Init, Validate & Format, Terraform Plan stages are duplicated under both PR Validation and Main Branch / Release Actions to ensure the correct environment context (env.DEPLOY_ENVIRONMENT) is used for each flow. This makes the pipeline more explicit and robust.
Targeted Manual Approval for Production Apply:

This stage is now strictly under the Main Branch / Release Actions block and uses when { expression { env.DEPLOY_ENVIRONMENT == 'prod' } } to ensure it only activates for production deployments triggered by a tag.
Create GitHub Release Stage:

This stage is also under Main Branch / Release Actions and explicitly when a TAG_NAME is present and the DEPLOY_ENVIRONMENT is prod. This ties your GitHub releases directly to successful production deployments.
Remember to replace 'github-pat-for-releases' with the actual ID of your Jenkins credential storing your GitHub Personal Access Token (PAT) with repo scope.
Robust Cleanup:

The post block now cleans up based on env.DEPLOY_ENVIRONMENT, ensuring temporary Terraform files are removed specific to the environment that was processed.
5.3. Setting up in Jenkins:
Install Plugins: Ensure Git, Pipeline, Credentials, GitHub Release Plugin are installed.
Configure Terraform Tool (Optional but recommended): Manage Jenkins -> Global Tool Configuration -> Terraform Installations.
Add GitHub PAT Credential: Manage Jenkins -> Manage Credentials -> Jenkins -> Global credentials (unrestricted) -> Add Credentials.
Kind: Secret text
ID: github-pat-for-releases (must match the credentialId in the Jenkinsfile)
Secret: Your GitHub Personal Access Token (PAT) with repo scope.
Add Cloud Provider Credentials: As discussed before (e.g., aws-terraform-global as AWS Credentials kind).
Create Jenkins Job:
Go to New Item.
Select Multibranch Pipeline.
Give it a name (e.g., terraform-repo-pipeline).
Configure Branch Sources:
Add Source: Git
Project Repository: Your GitHub repository URL (e.g., https://github.com/your-org/your-repo.git)
Credentials: If your repo is private, add a Jenkins credential here (e.g., SSH key or Username/Password).
Behaviors: Ensure "Discover Pull Requests" is enabled.
Build Configuration:
Mode: By Jenkinsfile
Script Path: Jenkinsfile (assuming it's at the root of your repo).
Save the job. Jenkins will then scan your repository, detect branches, and create pipeline jobs for main and any open PRs.
This setup provides a highly automated, robust, and clear workflow for Terraform development following GitHub Flow principles with Jenkins.
