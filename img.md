``` txt
gitGraph
   %% Setup Branches
   commit id: "init"
   branch dev
   checkout dev
   commit id: "start-dev"
   branch staging
   branch prod

   %% Feature Workflow
   checkout dev
   branch feature/login
   checkout feature/login
   commit id: "feat-1"
   commit id: "feat-2"
   
   %% Merge to DEV
   checkout dev
   merge feature/login id: "PR-Merge"
   commit id: "build-dev" tag: "v1.1.0-dev" type: HIGHLIGHT
   
   %% Promote to STAGING (Simulated via Merge)
   checkout staging
   merge dev id: "Promote-to-Stage"
   commit id: "test-stage" tag: "v1.1.0-stage" type: HIGHLIGHT
   
   %% Promote to PROD
   checkout prod
   merge staging id: "Promote-to-Prod"
   commit id: "release" tag: "v1.1.0" type: HIGHLIGHT




flowchart TD
    %% Styling for small circles
    classDef branch fill:#f9f,stroke:#333,stroke-width:2px,shape:circle,width:80px;
    classDef action fill:#bbf,stroke:#333,stroke-width:1px,rx:5,ry:5;
    classDef decision fill:#ff9,stroke:#333,stroke-width:1px,shape:diamond;
    classDef tag fill:#ffa,stroke:#da2,stroke-width:2px,stroke-dasharray: 5 5;

    %% Level 1: Development
    Start((Feature<br>Branch)) -->|PR Merge| Dev((Dev<br>Branch))
    Dev --> CalcVer[Calculate Version<br>Ex: 1.1.0]:::action
    CalcVer --> TagDev[Create Tag<br>v1.1.0-dev]:::tag
    TagDev --> TestDev{Tests<br>Pass?}:::decision
    
    %% Level 2: Staging Promotion
    TestDev -- Yes --> CreatePR_Stg[Create PR to<br>Staging Env]:::action
    TestDev -- No --> FixDev[Fix in Feature]:::action
    CreatePR_Stg -->|Merge| Staging((Staging<br>Branch)):::branch
    
    Staging --> InheritVer[Inherit Version<br>v1.1.0]:::action
    InheritVer --> TagStg[Create Tag<br>v1.1.0-staging]:::tag
    TagStg --> TestStg{Tests<br>Pass?}:::decision
    
    %% Level 3: Production Promotion
    TestStg -- Yes --> CreatePR_Prod[Create PR to<br>Prod Env]:::action
    TestStg -- No --> FixStg[Hotfix]:::action
    CreatePR_Prod -->|Merge| Prod((Prod<br>Branch)):::branch
    
    Prod --> TagProd[Create Release<br>v1.1.0]:::tag
    TagProd --> Final{Smoke<br>Test}:::decision
    Final -- Pass --> Done((Latest<br>Release)):::branch

    class Start,Dev,Staging,Prod,Done branch;
```
