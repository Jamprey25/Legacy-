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

export interface TasksFile {
  meta: { project: string; lastUpdated: string };
  tasks: Task[];
}
