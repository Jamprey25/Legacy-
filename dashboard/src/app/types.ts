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

export interface Decision {
  id: string;
  kind: DecisionKind;          // "decision" needs a call; "blocker" is something stuck
  title: string;
  status: DecisionStatus;
  raisedBy: Owner;             // who flagged it
  needs: Owner | "joseph";     // who needs to act
  detail: string;
  recommendation?: string;     // proposed answer, if any
  blocks: string[];            // task ids this is holding up
  resolution?: string;         // filled in when decided
}

export interface TasksFile {
  meta: { project: string; lastUpdated: string };
  decisions?: Decision[];
  tasks: Task[];
}
