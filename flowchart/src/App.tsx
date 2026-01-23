import { useCallback, useState, useRef } from 'react';
import type { Node, Edge, NodeChange, EdgeChange, Connection } from '@xyflow/react';
import {
  ReactFlow,
  useNodesState,
  useEdgesState,
  Controls,
  Background,
  BackgroundVariant,
  MarkerType,
  applyNodeChanges,
  applyEdgeChanges,
  addEdge,
  Handle,
  Position,
  reconnectEdge,
} from '@xyflow/react';
import '@xyflow/react/dist/style.css';
import './App.css';

const nodeWidth = 240;
const nodeHeight = 70;

// Setup phase - horizontal at top
// Loop phase - circular arrangement below
// Exit - at bottom center

type Phase = 'setup' | 'loop' | 'decision' | 'done' | 'objective-setup' | 'objective-loop' | 'objective-decision' | 'objective-termination';
type FlowMode = 'prd' | 'objective';

const phaseColors: Record<Phase, { bg: string; border: string }> = {
  // PRD mode colors (blue-ish theme)
  setup: { bg: '#f0f7ff', border: '#4a90d9' },
  loop: { bg: '#f5f5f5', border: '#666666' },
  decision: { bg: '#fff8e6', border: '#c9a227' },
  done: { bg: '#f0fff4', border: '#38a169' },
  // Objective mode colors (purple/coral theme)
  'objective-setup': { bg: '#f5f0ff', border: '#8b5cf6' },
  'objective-loop': { bg: '#fdf4f0', border: '#c97a50' },
  'objective-decision': { bg: '#fef9e6', border: '#d4a017' },
  'objective-termination': { bg: '#f0fff4', border: '#38a169' },
};

// PRD Mode Steps
const prdSteps: { id: string; label: string; description: string; phase: Phase }[] = [
  // Setup phase (vertical)
  { id: '1', label: 'You write a PRD', description: 'Define what you want to build', phase: 'setup' },
  { id: '2', label: 'Convert to prd.json', description: 'Break into small user stories', phase: 'setup' },
  { id: '3', label: 'Run angainor.sh', description: 'Starts the autonomous loop', phase: 'setup' },
  // Loop phase
  { id: '4', label: 'Amp picks a story', description: 'Finds next passes: false', phase: 'loop' },
  { id: '5', label: 'Implements it', description: 'Writes code, runs tests', phase: 'loop' },
  { id: '6', label: 'Commits changes', description: 'If tests pass', phase: 'loop' },
  { id: '7', label: 'Updates prd.json', description: 'Sets passes: true', phase: 'loop' },
  { id: '8', label: 'Logs to progress.txt', description: 'Saves learnings', phase: 'loop' },
  { id: '9', label: 'More stories?', description: '', phase: 'decision' },
  // Exit
  { id: '10', label: 'Done!', description: 'All stories complete', phase: 'done' },
];

// Objective Mode Steps
const objectiveSteps: { id: string; label: string; description: string; phase: Phase }[] = [
  // Setup phase
  { id: 'obj-1', label: 'Define objective', description: 'Run /objective skill', phase: 'objective-setup' },
  { id: 'obj-2', label: 'Create objective.json', description: 'Goal, metrics, constraints', phase: 'objective-setup' },
  { id: 'obj-3', label: 'Run angainor.sh --objective', description: 'Starts experiment loop', phase: 'objective-setup' },
  // Loop phase
  { id: 'obj-4', label: 'Read objective.json', description: 'Load goal & metrics', phase: 'objective-loop' },
  { id: 'obj-5', label: 'Form hypothesis', description: 'What might improve metric?', phase: 'objective-loop' },
  { id: 'obj-6', label: 'Implement change', description: 'Try the experiment', phase: 'objective-loop' },
  { id: 'obj-7', label: 'Run benchmark', description: 'Measure metrics', phase: 'objective-loop' },
  { id: 'obj-8', label: 'Evaluate results', description: 'Did it improve?', phase: 'objective-decision' },
  { id: 'obj-9', label: 'Update metrics', description: 'Log to objective.json', phase: 'objective-loop' },
  // Decision
  { id: 'obj-10', label: 'Goal achieved?', description: '', phase: 'objective-decision' },
  // Termination branches
  { id: 'obj-success', label: 'SUCCESS', description: 'Objective achieved!', phase: 'objective-termination' },
  { id: 'obj-impossible', label: 'IMPOSSIBLE', description: 'Cannot be achieved', phase: 'objective-termination' },
  { id: 'obj-plateau', label: 'PLATEAU', description: 'Diminishing returns', phase: 'objective-termination' },
  { id: 'obj-max', label: 'MAX_ITERATIONS', description: 'Budget exhausted', phase: 'objective-termination' },
];

// PRD Mode notes
const prdNotes = [
  {
    id: 'note-1',
    appearsWithStep: 2,
    position: { x: 340, y: 100 },
    color: { bg: '#f5f0ff', border: '#8b5cf6' },
    content: `{
  "id": "US-001",
  "title": "Add priority field to database",
  "acceptanceCriteria": [
    "Add priority column to tasks table",
    "Generate and run migration",
    "Typecheck passes"
  ],
  "passes": false
}`,
  },
  {
    id: 'note-2',
    appearsWithStep: 8,
    position: { x: 480, y: 620 },
    color: { bg: '#fdf4f0', border: '#c97a50' },
    content: `Also updates AGENTS.md with
patterns discovered, so future
iterations learn from this one.`,
  },
];

// Objective Mode notes
const objectiveNotes = [
  {
    id: 'obj-note-1',
    appearsWithStep: 2,
    position: { x: 340, y: 100 },
    color: { bg: '#f5f0ff', border: '#8b5cf6' },
    content: `{
  "objective": {
    "description": "Improve accuracy to 90%"
  },
  "verification": {
    "command": "python benchmark.py",
    "successCriteria": "accuracy >= 0.90"
  }
}`,
  },
  {
    id: 'obj-note-2',
    appearsWithStep: 5,
    position: { x: 520, y: 340 },
    color: { bg: '#fdf4f0', border: '#c97a50' },
    content: `Hypothesis: "Adding dropout
layer might reduce overfitting
and improve test accuracy"`,
  },
  {
    id: 'obj-note-3',
    appearsWithStep: 10,
    position: { x: 60, y: 750 },
    color: { bg: '#e8f5e9', border: '#4caf50' },
    content: `Exit codes:
• SUCCESS = 0
• IMPOSSIBLE = 2
• PLATEAU = 3
• MAX_ITERATIONS = 4`,
  },
];

function CustomNode({ data }: { data: { title: string; description: string; phase: Phase } }) {
  const colors = phaseColors[data.phase];
  return (
    <div 
      className="custom-node"
      style={{ 
        backgroundColor: colors.bg, 
        borderColor: colors.border 
      }}
    >
      <Handle type="target" position={Position.Top} id="top" />
      <Handle type="target" position={Position.Left} id="left" />
      <Handle type="source" position={Position.Right} id="right" />
      <Handle type="source" position={Position.Bottom} id="bottom" />
      <Handle type="target" position={Position.Right} id="right-target" style={{ right: 0 }} />
      <Handle type="target" position={Position.Bottom} id="bottom-target" style={{ bottom: 0 }} />
      <Handle type="source" position={Position.Top} id="top-source" />
      <Handle type="source" position={Position.Left} id="left-source" />
      <div className="node-content">
        <div className="node-title">{data.title}</div>
        {data.description && <div className="node-description">{data.description}</div>}
      </div>
    </div>
  );
}

function NoteNode({ data }: { data: { content: string; color: { bg: string; border: string } } }) {
  return (
    <div 
      className="note-node"
      style={{
        backgroundColor: data.color.bg,
        borderColor: data.color.border,
      }}
    >
      <pre>{data.content}</pre>
    </div>
  );
}

const nodeTypes = { custom: CustomNode, note: NoteNode };

// PRD Mode positions
const prdPositions: { [key: string]: { x: number; y: number } } = {
  // Vertical setup flow on the left
  '1': { x: 20, y: 20 },
  '2': { x: 80, y: 130 },
  '3': { x: 60, y: 250 },
  // Loop
  '4': { x: 40, y: 420 },
  '5': { x: 450, y: 300 },
  '6': { x: 750, y: 450 },
  '7': { x: 470, y: 520 },
  '8': { x: 200, y: 620 },
  '9': { x: 40, y: 720 },
  // Exit
  '10': { x: 350, y: 880 },
  // Notes
  ...Object.fromEntries(prdNotes.map(n => [n.id, n.position])),
};

// Objective Mode positions
const objectivePositions: { [key: string]: { x: number; y: number } } = {
  // Setup phase (vertical on left)
  'obj-1': { x: 20, y: 20 },
  'obj-2': { x: 80, y: 130 },
  'obj-3': { x: 60, y: 250 },
  // Loop phase
  'obj-4': { x: 40, y: 420 },
  'obj-5': { x: 300, y: 320 },
  'obj-6': { x: 550, y: 400 },
  'obj-7': { x: 750, y: 500 },
  'obj-8': { x: 550, y: 600 },
  'obj-9': { x: 300, y: 530 },
  // Decision
  'obj-10': { x: 40, y: 680 },
  // Termination branches (fan out at bottom)
  'obj-success': { x: 20, y: 850 },
  'obj-impossible': { x: 250, y: 850 },
  'obj-plateau': { x: 480, y: 850 },
  'obj-max': { x: 710, y: 850 },
  // Notes
  ...Object.fromEntries(objectiveNotes.map(n => [n.id, n.position])),
};

// PRD Mode edge connections
const prdEdgeConnections: { source: string; target: string; sourceHandle?: string; targetHandle?: string; label?: string }[] = [
  // Setup phase (vertical) - bottom to top connections
  { source: '1', target: '2', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: '2', target: '3', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: '3', target: '4', sourceHandle: 'bottom', targetHandle: 'top' },
  // Loop phase
  { source: '4', target: '5', sourceHandle: 'right', targetHandle: 'left' },
  { source: '5', target: '6', sourceHandle: 'right', targetHandle: 'top' },
  { source: '6', target: '7', sourceHandle: 'left-source', targetHandle: 'right-target' },
  { source: '7', target: '8', sourceHandle: 'left-source', targetHandle: 'right-target' },
  { source: '8', target: '9', sourceHandle: 'left-source', targetHandle: 'right-target' },
  { source: '9', target: '4', sourceHandle: 'top-source', targetHandle: 'bottom-target', label: 'Yes' },
  // Exit
  { source: '9', target: '10', sourceHandle: 'bottom', targetHandle: 'top', label: 'No' },
];

// Objective Mode edge connections
const objectiveEdgeConnections: { source: string; target: string; sourceHandle?: string; targetHandle?: string; label?: string }[] = [
  // Setup phase (vertical)
  { source: 'obj-1', target: 'obj-2', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: 'obj-2', target: 'obj-3', sourceHandle: 'bottom', targetHandle: 'top' },
  { source: 'obj-3', target: 'obj-4', sourceHandle: 'bottom', targetHandle: 'top' },
  // Loop phase
  { source: 'obj-4', target: 'obj-5', sourceHandle: 'right', targetHandle: 'left' },
  { source: 'obj-5', target: 'obj-6', sourceHandle: 'right', targetHandle: 'left' },
  { source: 'obj-6', target: 'obj-7', sourceHandle: 'right', targetHandle: 'top' },
  { source: 'obj-7', target: 'obj-8', sourceHandle: 'bottom', targetHandle: 'right-target' },
  { source: 'obj-8', target: 'obj-9', sourceHandle: 'left-source', targetHandle: 'right-target' },
  { source: 'obj-9', target: 'obj-10', sourceHandle: 'left-source', targetHandle: 'right-target' },
  // Loop back
  { source: 'obj-10', target: 'obj-4', sourceHandle: 'top-source', targetHandle: 'bottom-target', label: 'No' },
  // Termination branches from decision node
  { source: 'obj-10', target: 'obj-success', sourceHandle: 'bottom', targetHandle: 'top', label: 'Yes' },
  { source: 'obj-8', target: 'obj-impossible', sourceHandle: 'bottom', targetHandle: 'top', label: 'Evidence' },
  { source: 'obj-10', target: 'obj-plateau', sourceHandle: 'right', targetHandle: 'top', label: 'Stagnant' },
  { source: 'obj-10', target: 'obj-max', sourceHandle: 'right', targetHandle: 'top', label: 'Budget' },
];

type StepType = { id: string; label: string; description: string; phase: Phase };
type NoteType = { id: string; appearsWithStep: number; position: { x: number; y: number }; color: { bg: string; border: string }; content: string };
type EdgeConnType = { source: string; target: string; sourceHandle?: string; targetHandle?: string; label?: string };

function createNode(
  step: StepType,
  visible: boolean,
  positions: { [key: string]: { x: number; y: number } },
  position?: { x: number; y: number }
): Node {
  return {
    id: step.id,
    type: 'custom',
    position: position || positions[step.id],
    data: {
      title: step.label,
      description: step.description,
      phase: step.phase,
    },
    style: {
      width: nodeWidth,
      height: nodeHeight,
      opacity: visible ? 1 : 0,
      transition: 'opacity 0.5s ease-in-out',
      pointerEvents: visible ? 'auto' : 'none',
    },
  };
}

function createEdge(conn: EdgeConnType, visible: boolean): Edge {
  return {
    id: `e${conn.source}-${conn.target}`,
    source: conn.source,
    target: conn.target,
    sourceHandle: conn.sourceHandle,
    targetHandle: conn.targetHandle,
    label: visible ? conn.label : undefined,
    animated: visible,
    style: {
      stroke: '#222',
      strokeWidth: 2,
      opacity: visible ? 1 : 0,
      transition: 'opacity 0.5s ease-in-out',
    },
    labelStyle: {
      fill: '#222',
      fontWeight: 600,
      fontSize: 14,
    },
    labelShowBg: true,
    labelBgPadding: [8, 4] as [number, number],
    labelBgStyle: {
      fill: '#fff',
      stroke: '#222',
      strokeWidth: 1,
    },
    markerEnd: {
      type: MarkerType.ArrowClosed,
      color: '#222',
    },
  };
}

function createNoteNode(
  note: NoteType,
  visible: boolean,
  positions: { [key: string]: { x: number; y: number } },
  position?: { x: number; y: number }
): Node {
  return {
    id: note.id,
    type: 'note',
    position: position || positions[note.id],
    data: { content: note.content, color: note.color },
    style: {
      opacity: visible ? 1 : 0,
      transition: 'opacity 0.5s ease-in-out',
      pointerEvents: visible ? 'auto' : 'none',
    },
    draggable: true,
    selectable: false,
    connectable: false,
  };
}

// Helper to get mode-specific data
function getModeData(mode: FlowMode) {
  if (mode === 'prd') {
    return {
      steps: prdSteps,
      notes: prdNotes,
      positions: prdPositions,
      edges: prdEdgeConnections,
      title: 'How Angainor Works with Amp',
      subtitle: 'Autonomous AI agent loop for completing PRDs',
    };
  } else {
    return {
      steps: objectiveSteps,
      notes: objectiveNotes,
      positions: objectivePositions,
      edges: objectiveEdgeConnections,
      title: 'Objective Mode: Goal-Driven Iteration',
      subtitle: 'Experiment toward measurable goals with unknown approaches',
    };
  }
}

// Compute initial nodes without ref (for initial render)
function computeInitialNodes(currentModeData: ReturnType<typeof getModeData>) {
  const stepNodes = currentModeData.steps.map((step, index) =>
    createNode(step, index < 1, currentModeData.positions, currentModeData.positions[step.id])
  );
  const noteNodes = currentModeData.notes.map(note => {
    const noteVisible = 1 >= note.appearsWithStep;
    return createNoteNode(note, noteVisible, currentModeData.positions, currentModeData.positions[note.id]);
  });
  return [...stepNodes, ...noteNodes];
}

function App() {
  const [mode, setMode] = useState<FlowMode>('prd');
  const [visibleCount, setVisibleCount] = useState(1);

  const modeData = getModeData(mode);
  const nodePositions = useRef<{ [key: string]: { x: number; y: number } }>({ ...prdPositions });

  const getNodes = useCallback((count: number, currentModeData: ReturnType<typeof getModeData>) => {
    const stepNodes = currentModeData.steps.map((step, index) =>
      createNode(step, index < count, nodePositions.current, nodePositions.current[step.id])
    );
    const noteNodes = currentModeData.notes.map(note => {
      const noteVisible = count >= note.appearsWithStep;
      return createNoteNode(note, noteVisible, nodePositions.current, nodePositions.current[note.id]);
    });
    return [...stepNodes, ...noteNodes];
  }, []);

  const getEdgeVisibility = useCallback((conn: EdgeConnType, visibleStepCount: number, steps: StepType[]) => {
    const sourceIndex = steps.findIndex(s => s.id === conn.source);
    const targetIndex = steps.findIndex(s => s.id === conn.target);
    return sourceIndex < visibleStepCount && targetIndex < visibleStepCount;
  }, []);

  // Initialize with PRD mode data (computed outside of ref access)
  const [nodes, setNodes] = useNodesState(computeInitialNodes(getModeData('prd')));
  const [edges, setEdges] = useEdgesState(prdEdgeConnections.map((conn) => createEdge(conn, false)));

  const onNodesChange = useCallback(
    (changes: NodeChange[]) => {
      changes.forEach((change) => {
        if (change.type === 'position' && change.position) {
          nodePositions.current[change.id] = change.position;
        }
      });
      setNodes((nds) => applyNodeChanges(changes, nds));
    },
    [setNodes]
  );

  const onEdgesChange = useCallback(
    (changes: EdgeChange[]) => {
      setEdges((eds) => applyEdgeChanges(changes, eds));
    },
    [setEdges]
  );

  const onConnect = useCallback(
    (connection: Connection) => {
      setEdges((eds) => addEdge({ ...connection, animated: true, style: { stroke: '#222', strokeWidth: 2 }, markerEnd: { type: MarkerType.ArrowClosed, color: '#222' } }, eds));
    },
    [setEdges]
  );

  const onReconnect = useCallback(
    (oldEdge: Edge, newConnection: Connection) => {
      setEdges((eds) => reconnectEdge(oldEdge, newConnection, eds));
    },
    [setEdges]
  );

  const handleNext = useCallback(() => {
    if (visibleCount < modeData.steps.length) {
      const newCount = visibleCount + 1;
      setVisibleCount(newCount);

      setNodes(getNodes(newCount, modeData));
      setEdges(
        modeData.edges.map((conn) =>
          createEdge(conn, getEdgeVisibility(conn, newCount, modeData.steps))
        )
      );
    }
  }, [visibleCount, modeData, setNodes, setEdges, getNodes, getEdgeVisibility]);

  const handlePrev = useCallback(() => {
    if (visibleCount > 1) {
      const newCount = visibleCount - 1;
      setVisibleCount(newCount);

      setNodes(getNodes(newCount, modeData));
      setEdges(
        modeData.edges.map((conn) =>
          createEdge(conn, getEdgeVisibility(conn, newCount, modeData.steps))
        )
      );
    }
  }, [visibleCount, modeData, setNodes, setEdges, getNodes, getEdgeVisibility]);

  const handleReset = useCallback(() => {
    setVisibleCount(1);
    nodePositions.current = { ...modeData.positions };
    setNodes(getNodes(1, modeData));
    setEdges(modeData.edges.map((conn) => createEdge(conn, false)));
  }, [modeData, setNodes, setEdges, getNodes]);

  const handleModeSwitch = useCallback((newMode: FlowMode) => {
    const newModeData = getModeData(newMode);
    setMode(newMode);
    setVisibleCount(1);
    nodePositions.current = { ...newModeData.positions };
    setNodes(getNodes(1, newModeData));
    setEdges(newModeData.edges.map((conn) => createEdge(conn, false)));
  }, [setNodes, setEdges, getNodes]);

  return (
    <div className="app-container">
      <div className="header">
        <div className="mode-toggle">
          <button
            className={`mode-btn ${mode === 'prd' ? 'active' : ''}`}
            onClick={() => handleModeSwitch('prd')}
          >
            PRD Mode
          </button>
          <button
            className={`mode-btn objective ${mode === 'objective' ? 'active' : ''}`}
            onClick={() => handleModeSwitch('objective')}
          >
            Objective Mode
          </button>
        </div>
        <h1>{modeData.title}</h1>
        <p>{modeData.subtitle}</p>
      </div>
      <div className="flow-container">
        <ReactFlow
          nodes={nodes}
          edges={edges}
          nodeTypes={nodeTypes}
          onNodesChange={onNodesChange}
          onEdgesChange={onEdgesChange}
          onConnect={onConnect}
          onReconnect={onReconnect}
          fitView
          fitViewOptions={{ padding: 0.2 }}
          nodesDraggable={true}
          nodesConnectable={true}
          edgesReconnectable={true}
          elementsSelectable={true}
          deleteKeyCode={['Backspace', 'Delete']}
          panOnDrag={true}
          panOnScroll={true}
          zoomOnScroll={true}
          zoomOnPinch={true}
          zoomOnDoubleClick={true}
          selectNodesOnDrag={false}
        >
          <Background variant={BackgroundVariant.Dots} gap={20} size={1} color="#ddd" />
          <Controls showInteractive={false} />
        </ReactFlow>
      </div>
      <div className="controls">
        <button onClick={handlePrev} disabled={visibleCount <= 1}>
          Previous
        </button>
        <span className="step-counter">
          Step {visibleCount} of {modeData.steps.length}
        </span>
        <button onClick={handleNext} disabled={visibleCount >= modeData.steps.length}>
          Next
        </button>
        <button onClick={handleReset} className="reset-btn">
          Reset
        </button>
      </div>
      <div className="instructions">
        Click Next to reveal each step • Switch between modes above
      </div>
    </div>
  );
}

export default App;
