```py
from graphviz import Digraph

def create_logic_diagram():
    dot = Digraph(comment='Cluster Selection Logic', format='png')
    dot.attr(rankdir='TB', size='10')

    # Styles
    dot.attr('node', shape='rect', style='filled', fillcolor='lightblue')
    
    # Nodes
    dot.node('Start', 'Start', shape='oval', fillcolor='lightgrey')
    dot.node('Inputs', 'Get Inputs:\n(CPU, Mem, CapParams)')
    dot.node('DecisionCap', 'Capacity Mgmt\nEnabled?', shape='diamond', fillcolor='yellow')
    
    # Path 1: Smart
    dot.node('CalcMem', 'Convert Req Mem\nGB to KB')
    dot.node('LoopCPU1', 'Loop CPU Levels:\n[8, 16, 18, 20]')
    dot.node('CheckCPU1', 'Req CPU <= Level?', shape='diamond', fillcolor='orange')
    dot.node('SetTag1', 'Set Tag:\nMax-VM-Size:1-{Level}')
    dot.node('Filter1', 'Filter Clusters\nby Tag')
    dot.node('Found1', 'Clusters Found?', shape='diamond', fillcolor='orange')
    dot.node('LoopClusters', 'Loop: Candidate\nClusters')
    dot.node('GetMetrics', 'Fetch Metrics:\n(Usable vs Used)')
    dot.node('CheckFit', 'Fits in\nUsable?', shape='diamond', fillcolor='orange')
    dot.node('SelectBest', 'Mark as\nBest Candidate', fillcolor='lightgreen')
    dot.node('ReturnBest', 'Return\nSelected Cluster', shape='oval', fillcolor='lightgreen')
    
    # Path 2: Random
    dot.node('LoopCPU2', 'Loop CPU Levels:\n[8, 16, 18, 20]')
    dot.node('CheckCPU2', 'Req CPU <= Level?', shape='diamond', fillcolor='orange')
    dot.node('SetTag2', 'Set Tag:\nMax-VM-Size:1-{Level}')
    dot.node('Filter2', 'Filter Clusters\nby Tag')
    dot.node('Found2', 'Clusters Found?', shape='diamond', fillcolor='orange')
    dot.node('RandomPick', 'Pick Random\nCluster')
    dot.node('ReturnRandom', 'Return\nRandom Cluster', shape='oval', fillcolor='lightgreen')
    
    # Errors
    dot.node('Error', 'Throw Error', shape='oval', fillcolor='red')

    # Edges - Main Flow
    dot.edge('Start', 'Inputs')
    dot.edge('Inputs', 'DecisionCap')
    
    # Edges - Smart Path (Yes)
    dot.edge('DecisionCap', 'CalcMem', label='Yes')
    dot.edge('CalcMem', 'LoopCPU1')
    dot.edge('LoopCPU1', 'CheckCPU1')
    dot.edge('CheckCPU1', 'LoopCPU1', label='No (Next Lvl)')
    dot.edge('CheckCPU1', 'SetTag1', label='Yes')
    dot.edge('SetTag1', 'Filter1')
    dot.edge('Filter1', 'Found1')
    dot.edge('Found1', 'LoopClusters', label='Yes')
    dot.edge('Found1', 'Error', label='No')
    
    dot.edge('LoopClusters', 'GetMetrics')
    dot.edge('GetMetrics', 'CheckFit')
    dot.edge('CheckFit', 'SelectBest', label='Yes')
    dot.edge('CheckFit', 'LoopClusters', label='No')
    dot.edge('SelectBest', 'LoopClusters', label='Next')
    dot.edge('LoopClusters', 'ReturnBest', label='Done')

    # Edges - Random Path (No)
    dot.edge('DecisionCap', 'LoopCPU2', label='No')
    dot.edge('LoopCPU2', 'CheckCPU2')
    dot.edge('CheckCPU2', 'LoopCPU2', label='No')
    dot.edge('CheckCPU2', 'SetTag2', label='Yes')
    dot.edge('SetTag2', 'Filter2')
    dot.edge('Filter2', 'Found2')
    dot.edge('Found2', 'RandomPick', label='Yes')
    dot.edge('Found2', 'Error', label='No')
    dot.edge('RandomPick', 'ReturnRandom')

    # Render
    dot.render('cluster_logic_flow', view=True)
    print("Diagram generated: cluster_logic_flow.png")

if __name__ == '__main__':
    create_logic_diagram()
```
