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

export type DecisionStatus = "open" | "decided" | "resolved";
export type DecisionKind = "decision" | "blocker" | "question" | "concern" | "idea";

/** One choosable path for an open decision — Joseph picks one in the dashboard. */
export interface DecisionOption {
  id: string;
  label: string;
  description?: string;
  recommended?: boolean;
}

/** A single reply in a question/concern/idea thread. */
export interface ThreadResponse {
  author: Owner | "joseph";
  text: string;
  date: string; // ISO date
}

export interface Decision {
  id: string;
  kind: DecisionKind;
  title: string;
  status: DecisionStatus;
  raisedBy: Owner | "joseph";
  needs: Owner | "joseph";     // who needs to act
  detail: string;
  /** Required when kind is "decision" — Joseph chooses one option in the dashboard. */
  options?: DecisionOption[];
  recommendation?: string;
  blocks: string[];
  chosenOptionId?: string;
  decidedAt?: string;
  resolution?: string;
  /** Thread of responses for question/concern/idea kinds. */
  responses?: ThreadResponse[];
}

export interface TasksFile {
  meta: { project: string; lastUpdated: string };
  decisions?: Decision[];
  /** Manual Xcode/device checks Joseph marks pass/fail in the dashboard. */
  manualTests?: ManualTest[];
  tasks: Task[];
}

export type ManualTestStatus = "pending" | "passed" | "failed";
export type ManualTestPlatform = "xcode" | "device" | "simulator";

export interface ManualTest {
  id: string;
  title: string;
  status: ManualTestStatus;
  /** Who added this check (ios = Cursor, backend = Claude). */
  addedBy: Owner | "joseph";
  platform: ManualTestPlatform;
  milestone?: string;
  /** Task ids this validates (e.g. ios-auth-ui). */
  relatedTasks?: string[];
  /** Step-by-step instructions for Joseph in Xcode/simulator. */
  steps: string[];
  notes?: string;
  verifiedAt?: string;
}
