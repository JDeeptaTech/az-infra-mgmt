``` powershell
# Define the path to your CSV files
$SourceFolderPath = "C:\Your\Path\To\CSVFiles" # <--- IMPORTANT: Change this to the folder containing your CSV files

# Define the path and name for the consolidated output file
$OutputFilePath = "C:\Your\Path\To\Output\ConsolidatedData.csv" # <--- IMPORTANT: Change this to your desired output file path and name

# Define the name for the new column that will store the filename
$NewColumnName = "SourceFileName"

# Create an empty array to store all consolidated data
$AllData = @()

# Get all CSV files in the source folder
$csvFiles = Get-ChildItem -Path $SourceFolderPath -Filter "*.csv"

if ($csvFiles.Count -eq 0) {
    Write-Warning "No CSV files found in '$SourceFolderPath'. Please check the path."
} else {
    Write-Host "Found $($csvFiles.Count) CSV files in '$SourceFolderPath'."

    foreach ($file in $csvFiles) {
        Write-Host "Processing file: $($file.Name)"

        # Import the CSV content
        $data = Import-Csv -Path $file.FullName

        # Get the file name without the extension
        $fileName = $file.BaseName

        # Add the new column with the file name to each row
        foreach ($row in $data) {
            $row | Add-Member -MemberType NoteProperty -Name $NewColumnName -Value $fileName -Force
        }

        # Add the modified data to the consolidated array
        $AllData += $data
    }

    # Export all consolidated data to a new CSV file
    Write-Host "Exporting consolidated data to '$OutputFilePath'."
    $AllData | Export-Csv -Path $OutputFilePath -NoTypeInformation

    Write-Host "Script completed successfully! Consolidated data saved to '$OutputFilePath'."
}
```

``` bash
#!/bin/bash

# --- Variables ---
# Define your workspace name
WORKSPACE_NAME="your_databricks_private_workspace" # <<< IMPORTANT: Change this to your desired workspace name

# --- Script Logic ---

echo "--- Initializing Terraform ---"
# Initialize Terraform with backend configuration.
# Ensure your backend config for `terraform init` is correct for your environment.
# Example: Using an Azure Storage Account backend
terraform init \
  -backend-config="resource_group_name=${TF_STATE_RESOURCE_GROUP_NAME}" \
  -backend-config="storage_account_name=${TF_STATE_STORAGE_ACCOUNT_NAME}" \
  -backend-config="container_name=${TF_STATE_CONTAINER_NAME}" \
  -backend-config="key=${TF_STATE_KEY}" || { echo "Terraform init failed."; exit 1; }

echo "--- Checking and Setting Terraform Workspace ---"

# Check if the workspace exists
terraform workspace select "$WORKSPACE_NAME" || {
  echo "Workspace '$WORKSPACE_NAME' does not exist. Creating it..."
  terraform workspace new "$WORKSPACE_NAME" || { echo "Failed to create workspace '$WORKSPACE_NAME'."; exit 1; }
  echo "Workspace '$WORKSPACE_NAME' created and selected."
}

# Verify the currently selected workspace (optional, but good for debugging)
CURRENT_WORKSPACE=$(terraform workspace show)
echo "Current Terraform Workspace: $CURRENT_WORKSPACE"

# Ensure the correct workspace is selected if it was just created or already existed
if [ "$CURRENT_WORKSPACE" != "$WORKSPACE_NAME" ]; then
  echo "Attempting to select workspace '$WORKSPACE_NAME'..."
  terraform workspace select "$WORKSPACE_NAME" || { echo "Failed to select workspace '$WORKSPACE_NAME'."; exit 1; }
  echo "Workspace '$WORKSPACE_NAME' is now selected."
fi

export TF_WORKSPACE="$WORKSPACE_NAME" # Exporting for any downstream processes if needed

echo "--- Running Terraform Plan ---"

# Run terraform plan
# -input=false: Do not prompt for input
# -out=tfplan.out: Save the plan to a file
# -detailed-exitcode: This is CRUCIAL for failing the script!
#                     Returns 0 if no changes, 1 if error, 2 if changes.
# -parallelism=50: Adjust as needed
terraform plan -input=false -out=tfplan.out -detailed-exitcode -parallelism=50

# Check the exit code of the terraform plan command
PLAN_EXIT_CODE=$?

if [ $PLAN_EXIT_CODE -eq 0 ]; then
  echo "Terraform plan succeeded: No changes detected."
  # You might want to remove the tfplan.out file if no changes are needed
  rm -f tfplan.out
elif [ $PLAN_EXIT_CODE -eq 2 ]; then
  echo "Terraform plan succeeded: Changes detected. Proceeding to apply stage."
  # Optionally, display the plan if changes are detected
  terraform show tfplan.out
  # You can now publish the tfplan.out as an artifact in your pipeline
else
  echo "Terraform plan failed with exit code $PLAN_EXIT_CODE. Exiting."
  exit 1 # Fail the script
fi

echo "--- Generating Terraform Plan JSON Output ---"
# This command is useful for programmatic parsing of the plan
terraform show -json tfplan.out > tfplan.json || { echo "Failed to generate tfplan.json."; exit 1; }

echo "Script finished."
```
