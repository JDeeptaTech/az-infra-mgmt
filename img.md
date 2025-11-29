```txtgraph TD
    Start([Start]) --> Inputs[Get Inputs:<br/>Req CPU, Req Memory, Capacity Params]
    Inputs --> DecisionCap{Capacity Mgmt<br/>Enabled?}

    %% Path 1: Capacity Management is ON (Smart Placement)
    DecisionCap -- Yes --> CalcMem[Convert Req Memory<br/>GB to KB]
    CalcMem --> LoopCPU1[Loop CPU Levels:<br/>8, 16, 18, 20]
    LoopCPU1 --> CheckCPU1{Req CPU <= Level?}
    CheckCPU1 -- No --> LoopCPU1
    CheckCPU1 -- Yes --> SetTag1[Set Tag: <br/>Max-VM-Size:1-Level]
    SetTag1 --> Filter1[Get Clusters by Tag]
    Filter1 --> Found1{Clusters Found?}
    Found1 -- No --> Error1[Throw Error:<br/>No Suitable Cluster]
    
    Found1 -- Yes --> LoopClusters[Loop Through Filtered Clusters]
    LoopClusters --> GetMetrics[Get vROps Metrics:<br/>- Usable Memory<br/>- Current Used Memory]
    GetMetrics --> CalcFit[Calc: Current Used + Req Memory]
    CalcFit --> CheckFit{Fits in Usable?}
    
    CheckFit -- No --> LoopClusters
    CheckFit -- Yes --> Compare{Is this Cluster<br/>Better than current best?}
    
    Compare -- No --> LoopClusters
    Compare -- Yes --> SelectBest[Mark as Selected Host]
    SelectBest --> LoopClusters
    
    LoopClusters -- End of Loop --> FinalCheck{Was a Host Selected?}
    FinalCheck -- Yes --> ReturnBest([Return Selected Cluster ID])
    FinalCheck -- No --> Error2[Throw Error:<br/>Not enough memory in any cluster]

    %% Path 2: Capacity Management is OFF (Random Placement)
    DecisionCap -- No --> LoopCPU2[Loop CPU Levels:<br/>8, 16, 18, 20]
    LoopCPU2 --> CheckCPU2{Req CPU <= Level?}
    CheckCPU2 -- No --> LoopCPU2
    CheckCPU2 -- Yes --> SetTag2[Set Tag: <br/>Max-VM-Size:1-Level]
    SetTag2 --> Filter2[Get Clusters by Tag]
    Filter2 --> Found2{Clusters Found?}
    Found2 -- No --> Error3[Throw Error:<br/>No Suitable Cluster]
    Found2 -- Yes --> RandomPick[Pick Random Index]
    RandomPick --> ReturnRandom([Return Random Cluster ID])

    %% Styling
    style Start fill:#f9f,stroke:#333,stroke-width:2px
    style ReturnBest fill:#9f9,stroke:#333,stroke-width:2px
    style ReturnRandom fill:#9f9,stroke:#333,stroke-width:2px
    style DecisionCap fill:#ff9,stroke:#333,stroke-width:2px
    style Error1 fill:#f99,stroke:#333,stroke-width:2px
    style Error2 fill:#f99,stroke:#333,stroke-width:2px
    style Error3 fill:#f99,stroke:#333,stroke-width:2px
```
