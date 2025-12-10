``` txt
sequenceDiagram
    participant User
    participant F_API as FastAPI Web API
    participant PG_DB as PostgreSQL DB
    participant AAP as Ansible Automation Platform
    participant Unicorn_API as Unicorn Status API
    
    %% --- Stage 1: Get VM List with Validation (Steps 1-6) ---
    
    User->>F_API: 1. Request List of VMs/Groups
    F_API->>PG_DB: 2. Query VM Data (Admin Status)
    PG_DB-->>F_API: 3. Return Filtered VM List
    
    Note over F_API: **Validation on Fetch:** Enrich operational status
    loop For each VM in List
        F_API->>Unicorn_API: 4. Check Operational Status
        Unicorn_API-->>F_API: 5. Return Current Operational Status
    end
    
    F_API-->>User: 6. Display Available VMs (with verified status)
    
    %% --- Stage 2: Submit Operation Request with Double Pre-Check (Steps 7-16) ---
    
    User->>F_API: 7. Submit Operation Request (Selected VM_IDs)
    
    Note over F_API: **Validation on Submit (Double Check)**
    
    F_API->>Unicorn_API: 8. **Pre-Check 1:** Verify operational status
    Unicorn_API-->>F_API: 9. Return Current Statuses
    
    alt If Unicorn Pre-Check Fails
        F_API-->>User: 10a. Return Error: Invalid operational state
    else 
        F_API->>PG_DB: 10b. **Pre-Check 2:** Verify administrative status/existence
        PG_DB-->>F_API: 11. Return Administrative Status/Existence
        
        alt If DB Pre-Check Fails
            F_API-->>User: 12a. Return Error: Fails administrative check
        else If Both Pre-Checks Pass
            F_API->>PG_DB: 12b. Insert VMs into Onboarding Queue
            PG_DB-->>F_API: 13. Confirmation of Insert
            
            F_API->>AAP: 14. Trigger AAP Onboarding Job Template
            AAP-->>F_API: 15. Return Onboarding Job ID and Status
            F_API-->>User: 16. Operation Accepted. Return Job ID.
        end
    end
    
    %% --- Stage 3: AAP Execution (Onboarding, Operation, and Final Status Update) (Steps 17-22) ---
    
    Note over AAP: AAP reads onboarding_queue as Dynamic Inventory.
    
    loop Onboard and Validate VMs
        AAP->>Unicorn_API: 17. Final Operational Status Check
        Unicorn_API-->>AAP: 18. Return VM Status
        
        alt If VM Status is Acceptable
            Note over AAP: Perform resource operation/onboarding logic
            AAP->>Unicorn_API: 19. Update VM Status in Unicorn API
        else 
            AAP->>PG_DB: 20. Update Onboarding Queue Status to 'Skipped'
        end
        
    end
    
    AAP->>PG_DB: 21. Update final job status in database/audit log
    PG_DB-->>AAP: 22. Confirmation
```
