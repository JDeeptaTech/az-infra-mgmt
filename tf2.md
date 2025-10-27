```yml
- name: Extract only user-provided extra vars in AAP
  set_fact:
    job_payload: >-
      {{
        (ansible_job_extra_vars
          | default({})
          | dict2items
          | rejectattr('key', 'match', '^(ansible_|awx_|tower_|omit|_.*)$')
          | list
          | items2dict)
        if (ansible_job_extra_vars is defined)
        else
        (vars
          | dict2items
          | rejectattr('key', 'match', '^(ansible_|awx_|tower_|omit|_.*)$')
          | rejectattr('key', 'in', ['inventory_dir', 'inventory_file', 'playbook_dir', 'role_path'])
          | list
          | items2dict)
      }}



import streamlit as st
import psycopg2
import pandas as pd
import plotly.express as px
from datetime import datetime, time
import uuid

# -----------------------------
# ⚙️ Database Configuration
# -----------------------------
DB_CONFIG = {
    "host": "localhost",
    "port": "5432",
    "database": "mydb",
    "user": "postgres",
    "password": "password"
}

def get_connection():
    return psycopg2.connect(**DB_CONFIG)

# -----------------------------
# 🧩 Query Functions
# -----------------------------
def load_lifecycle_summary(start_dt, end_dt):
    query = """
        SELECT lifecycle_status, COUNT(*) AS total
        FROM vm
        WHERE created_at BETWEEN %s AND %s
        GROUP BY lifecycle_status
        ORDER BY total DESC
    """
    try:
        with get_connection() as conn:
            return pd.read_sql_query(query, conn, params=(start_dt, end_dt))
    except Exception as e:
        st.error(f"Database query failed: {e}")
        return pd.DataFrame()

def load_vm_table(search, lifecycle, start_dt, end_dt):
    query = """
        SELECT invocation_id, correlation_id, vm_name, ip_address,
               cpu, memory, lifecycle_status, created_at
        FROM vm
        WHERE created_at BETWEEN %s AND %s
    """
    params = [start_dt, end_dt]

    if lifecycle != "All":
        query += " AND lifecycle_status = %s"
        params.append(lifecycle)

    if search:
        try:
            uuid.UUID(search)
            query += " AND (invocation_id = %s OR correlation_id = %s)"
            params.extend([search, search])
        except Exception:
            query += " AND (vm_name ILIKE %s OR ip_address ILIKE %s)"
            params.extend([f"%{search}%", f"%{search}%"])

    query += " ORDER BY created_at DESC LIMIT 100"
    try:
        with get_connection() as conn:
            return pd.read_sql_query(query, conn, params=tuple(params))
    except Exception as e:
        st.error(f"Data query failed: {e}")
        return pd.DataFrame()

# -----------------------------
# 🎨 Streamlit Setup (White + Red Theme)
# -----------------------------
st.set_page_config(page_title="VM Portal", layout="wide")

st.markdown("""
<style>
body, [data-testid="stAppViewContainer"], [data-testid="stHeader"] {
    background-color: #ffffff !important;
    color: #000000 !important;
}
h1, h2, h3, h4 {
    color: #b30000 !important;
}
.stButton>button {
    background-color: #b30000 !important;
    color: white !important;
    border-radius: 6px;
}
.stButton>button:hover {
    background-color: #e60000 !important;
}
[data-testid="stSidebar"] {
    background-color: #fafafa !important;
}
</style>
""", unsafe_allow_html=True)

# -----------------------------
# 🧭 Sidebar Navigation
# -----------------------------
st.sidebar.title("📋 Menu")
page = st.sidebar.radio("Navigate to", ["📊 Dashboard", "📦 VM Table"])

# -----------------------------
# 🧮 Common Top Filters
# -----------------------------
st.markdown("### 🔍 Filters")

col1, col2, col3, col4, col5 = st.columns([2,2,2,2,2])
with col1:
    start_date = st.date_input("Start date", datetime(2024, 1, 1))
with col2:
    start_time = st.time_input("Start time", time(0, 0))
with col3:
    end_date = st.date_input("End date", datetime.now().date())
with col4:
    end_time = st.time_input("End time", time(23, 59))
with col5:
    if st.button("🔄 Refresh"):
        st.experimental_rerun()

start_dt = datetime.combine(start_date, start_time)
end_dt = datetime.combine(end_date, end_time)

st.markdown("---")

# -----------------------------
# 📊 Page 1: Dashboard
# -----------------------------
if page == "📊 Dashboard":
    st.title("📊 VM Lifecycle Summary")

    df = load_lifecycle_summary(start_dt, end_dt)

    if df.empty:
        st.warning("No data found for the selected period.")
    else:
        col1, col2 = st.columns(2)

        with col1:
            st.subheader("🟢 Lifecycle Pie Chart")
            fig_pie = px.pie(
                df, names="lifecycle_status", values="total",
                color_discrete_sequence=px.colors.sequential.Reds, hole=0.3
            )
            fig_pie.update_traces(textposition='inside', textinfo='percent+label')
            st.plotly_chart(fig_pie, use_container_width=True)

        with col2:
            st.subheader("📊 Lifecycle Counts (Bar)")
            fig_bar = px.bar(
                df, x="lifecycle_status", y="total", color="lifecycle_status",
                color_discrete_sequence=px.colors.sequential.Reds_r, text="total"
            )
            fig_bar.update_layout(plot_bgcolor="white", paper_bgcolor="white")
            st.plotly_chart(fig_bar, use_container_width=True)

        st.markdown("### 📋 Summary Table")
        st.dataframe(df.rename(columns={"lifecycle_status": "Lifecycle Status", "total": "Total VMs"}),
                     hide_index=True, use_container_width=True)

# -----------------------------
# 📦 Page 2: VM Table
# -----------------------------
elif page == "📦 VM Table":
    st.title("📦 VM Details")

    # Add search & lifecycle filters on top
    col1, col2, col3 = st.columns([2, 2, 1])
    with col1:
        search = st.text_input("🔍 Search by name, IP, or UUID")
    with col2:
        lifecycle = st.selectbox("Lifecycle status", ["All", "Provisioned", "Running", "Terminated"])
    with col3:
        refresh = st.button("Reload Table")

    df = load_vm_table(search, lifecycle, start_dt, end_dt)

    if df.empty:
        st.warning("No matching records.")
    else:
        st.dataframe(df, hide_index=True, use_container_width=True)
        csv = df.to_csv(index=False)
        st.download_button("📥 Download as CSV", data=csv, file_name="vm_list.csv", mime="text/csv")

```

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
