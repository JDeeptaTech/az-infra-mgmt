``` txt
sequenceDiagram
    participant U as User
    participant API as FastAPI App
    participant Sched as APScheduler
    participant DB as PostgreSQL (JobStore)

    Note over API, Sched: Shared Memory (In-App)

    %% Startup Phase
    rect rgb(240, 248, 255)
    Note right of API: Startup Event
    API->>Sched: Initialize Scheduler
    API->>DB: Connect to JobStore
    API->>API: Check "Default Jobs" List
    loop For each Default Job
        API->>Sched: Job Exists?
        alt Job Missing
            Sched->>DB: INSERT Default Schedule
        end
    end
    end

    %% User Interaction Phase
    U->>API: GET /jobs
    API->>DB: Fetch active jobs
    DB-->>API: Return Job List
    API-->>U: JSON [ {id: "email_sender", next_run: "10:00"} ]

    U->>API: POST /jobs/update (Change Schedule)
    API->>Sched: reschedule_job(job_id, new_trigger)
    Sched->>DB: UPDATE apscheduler_jobs SET next_run_time = ...
    API-->>U: 200 OK

    U->>API: POST /jobs/run-now (On Demand)
    API->>Sched: add_job(func, trigger='date', run_date=NOW)
    Note right of Sched: Fires immediately<br/>(Separate from recurring schedule)
    Sched->>U: 202 Accepted

```
