---

## 🚀 Features

- FastAPI backend
- Generated API client from OpenAPI spec
- Dockerized application
- GitHub Actions pipeline for Docker builds

---

## 🛠️ Setup Instructions

### 1. Project Initialization

 Task Checklist
 Initialize FastAPI project

 Download/Open OpenAPI spec

 Generate client using openapi-python-client

 Implement FastAPI endpoints

 Freeze dependencies into requirements.txt

 Create Dockerfile and .dockerignore

 Build and run Docker image locally

 Set up GitHub Actions workflow

 Push to DockerHub on each main branch update

Optional Enhancements
Add health check endpoints

Add logging and settings management

Add unit tests and CI test stage

Deploy with Kubernetes or Docker Compose

'''
# Connect to vCenter
Connect-VIServer -Server 'your-vcenter-server'

# Get all ESXi hosts
$hosts = Get-VMHost

# Initialize array to store results
$report = @()

foreach ($vmhost in $hosts) {
    $hostName = $vmhost.Name
    $hbas = Get-VMHostHba -VMHost $vmhost -Type FibreChannel

    foreach ($hba in $hbas) {
        $paths = Get-ScsiLun -VMHost $vmhost | Get-ScsiLunPath | Where-Object { $_.Device -eq $hba.Device }

        foreach ($path in $paths) {
            $row = [PSCustomObject]@{
                ScsiCanonicalName = $path.ScsiLunCanonicalName
                HostName          = $hostName
                HBA               = $path.Name
                ServerHBA         = $hba.NodeWorldWideName
                FA                = $path.AdapterWorldWideName
                Status            = if ($path.State -eq "active") { "✔" } else { "✖" }
            }
            $report += $row
        }
    }
}

# Export to CSV
$report | Export-Csv -Path ".\HBA_Precheck_Report.csv" -NoTypeInformation

# Optionally display in grid view
$report | Out-GridView -Title "HBA Precheck Report"
'''