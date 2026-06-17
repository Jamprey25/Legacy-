export type Status = "todo" | "in-progress" | "done";
export type Owner = "backend" | "ios" | "either";

export interface Task {
  id: string;
  title: string;
  status: Status;
  owner: Owner;
  phase: number;
  milestone: string;
  blockedBy: string[];
  notes: string;
}

export type DecisionStatus = "open" | "decided";
export type DecisionKind = "decision" | "blocker";

/** One choosable path for an open decision — Joseph picks one in the dashboard. */
export interface DecisionOption {
  id: string;
  label: string;
  description?: string;
  recommended?: boolean;
}

export interface Decision {
  id: string;
  kind: DecisionKind;          // "decision" needs a call; "blocker" is something stuck
  title: string;
  status: DecisionStatus;
  raisedBy: Owner;             // who flagged it
  needs: Owner | "joseph";     // who needs to act
  detail: string;
  /** Required when status is "open" — Joseph chooses one option in the dashboard. */
  options?: DecisionOption[];
  recommendation?: string;     // prose fallback / extra context
  blocks: string[];            // task ids this is holding up
  chosenOptionId?: string;     // set when decided via dashboard
  decidedAt?: string;          // ISO date when closed
  resolution?: string;         // filled in when decided
}

export interface TasksFile {
  meta: { project: string; lastUpdated: string };
  decisions?: Decision[];
  tasks: Task[];
}
