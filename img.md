``` txt
sequenceDiagram
    participant User as Client (User)
    participant API as FastAPI App
    participant Sched as APScheduler (Background Thread)
    participant DB as PostgreSQL

    Note over API, DB: Async Connection (asyncpg)
    Note over Sched, DB: Sync Connection (psycopg2)

    User->>API: POST /schedule-job (payload)
    API->>Sched: add_job(func, trigger, args)
    
    rect rgb(240, 248, 255)
    Note right of Sched: Job Serialization
    Sched->>DB: INSERT into apscheduler_jobs (pickle blob)
    DB-->>Sched: Confirm Save
    end
    
    API-->>User: 200 OK {"job_id": "123"}

    Note over Sched: ... Time Passes ...

    loop Background Polling
        Sched->>DB: SELECT * FROM apscheduler_jobs WHERE next_run_time <= NOW()
        DB-->>Sched: Return Job Payload
        Sched->>Sched: Deserialize & Execute Job
        
        opt Execution Logic
            Sched->>DB: Update/Write Results (if needed)
        end

        Sched->>DB: DELETE or UPDATE next_run_time
    end

```
