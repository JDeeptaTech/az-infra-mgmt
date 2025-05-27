# Pull Request (PR) Validation Workflow

This document outlines the workflow for validating Pull Requests (PRs) to ensure code quality and adherence to standards before merging into the `main` branch. This process leverages a Jenkins PR Pipeline to automate checks, primarily focusing on Terraform configurations.

---

## 1. Developer Action

The workflow begins with actions initiated by the developer:

* **Developer Commits & Pushes Feature Branch:** The developer makes changes on a dedicated feature branch and pushes these changes to the remote repository.
* **Opens Pull Request to `main`:** After pushing the feature branch, the developer creates a Pull Request targeting the `main` branch. This action triggers the automated Jenkins PR Pipeline.

---

## 2. Jenkins PR Pipeline (AAP)

Upon creation of the Pull Request, a Jenkins PR Pipeline (labeled as "AAP" in the diagram) is automatically initiated. This pipeline consists of several sequential tasks designed to validate the proposed changes:

* **Task: Checkout Code:**
    * **Description:** The pipeline first checks out the code from the feature branch associated with the Pull Request into the Jenkins workspace. This ensures that all subsequent tasks operate on the latest changes.
* **Task: Terraform Init PR:**
    * **Description:** This task initializes the Terraform working directory. It downloads necessary provider plugins and modules, preparing the environment for subsequent Terraform operations. This is crucial for validating the Terraform configuration.
* **Task: Validate & Format PR:**
    * **Description:** This stage focuses on validating the syntax and format of the Terraform code within the PR. It comprises three parallel runs:
        * **Run: `terraform fmt -check`**
            * **Purpose:** This command checks if the Terraform configuration files are properly formatted according to the canonical Terraform style. It ensures consistency across the codebase. If files are not formatted correctly, this check will fail.
        * **Run: `terraform validate`**
            * **Purpose:** This command validates the configuration files in the current directory, checking for syntax errors, inconsistencies, and valid references. It ensures that the Terraform code is syntactically correct and internally consistent.
        * **Run: `terraform plan Plain PR`**
            * **Purpose:** This command creates an execution plan, showing what actions Terraform will take (e.g., creating, modifying, or destroying resources) if the configuration were to be applied. While it doesn't apply changes, it verifies that a valid plan can be generated, identifying potential issues before deployment.
* **Run: `terraform plan -out=tfplan`**
    * **Description:** Following the validation checks, a `terraform plan` is executed again, but this time its output is saved to a file named `tfplan`.
    * **Purpose:** This `tfplan` file serves as a detailed record of the proposed infrastructure changes.
* **Save: `tfplan.json` as Artifact:**
    * **Description:** The `tfplan` file, which is a binary file, is typically converted to `tfplan.json` for easier inspection and saved as a build artifact in Jenkins.
    * **Purpose:** Saving this artifact allows for manual review of the proposed changes, auditing, and can be used in subsequent deployment steps if the PR is approved.

---

## 3. Result

After all tasks within the Jenkins PR Pipeline complete, the workflow proceeds to evaluate the outcomes of the checks:

* **All Checks Pass? (Decision Point):**
    * **Description:** This is a conditional decision point. The workflow evaluates the success of all the preceding `terraform fmt -check`, `terraform validate`, and `terraform plan` runs.
    * **Criteria:** For the checks to pass, all three Terraform commands (formatting check, validation, and plan generation) must complete successfully without errors.

---

## 4. Outcomes

Based on the "All Checks Pass?" decision, one of two outcomes will occur:

* **If "Yes" (All Checks Pass):**
    * **PR Ready for Review & Merge:** The Pull Request is marked as successful. It is now considered ready for human review by other team members. Once reviewed and approved, it can be merged into the `main` branch.
* **If "No" (Checks Fail):**
    * **Report Failure to PR:** The workflow reports the failure back to the Pull Request in the version control system (e.g., GitHub, GitLab). This typically means setting the PR status to "failed" or "pending," and providing details in the build logs about which specific check failed.
    * **Action Required:** The developer is then responsible for reviewing the reported errors, fixing the issues in their feature branch, and pushing new commits. This will trigger the Jenkins PR Pipeline again for re-validation.
