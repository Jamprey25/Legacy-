import type { TasksFile, Task, Status, Owner } from "./types";

const GITHUB_RAW =
  "https://raw.githubusercontent.com/Jamprey25/Legacy-/main/tasks.json";

async function getTasks(): Promise<TasksFile> {
  const res = await fetch(GITHUB_RAW, { next: { revalidate: 30 } });
  if (!res.ok) throw new Error(`Failed to fetch tasks: ${res.status}`);
  return res.json();
}

const STATUS_LABEL: Record<Status, string> = {
  todo: "Todo",
  "in-progress": "In Progress",
  done: "Done",
};

const OWNER_LABEL: Record<Owner, string> = {
  backend: "Backend",
  ios: "iOS",
  either: "Either",
};

function statusColor(s: Status) {
  if (s === "done") return "#16a34a";
  if (s === "in-progress") return "#d97706";
  return "#444";
}

function ownerColor(o: Owner) {
  if (o === "backend") return "#6366f1";
  if (o === "ios") return "#0ea5e9";
  return "#8b5cf6";
}

function Badge({ label, color }: { label: string; color: string }) {
  return (
    <span
      style={{
        background: color + "22",
        color,
        border: `1px solid ${color}44`,
        borderRadius: 4,
        padding: "1px 8px",
        fontSize: 11,
        fontWeight: 600,
        letterSpacing: 0.3,
        whiteSpace: "nowrap",
      }}
    >
      {label}
    </span>
  );
}

function TaskCard({ task, allTasks }: { task: Task; allTasks: Task[] }) {
  const blockers = task.blockedBy
    .map((id) => allTasks.find((t) => t.id === id))
    .filter(Boolean) as Task[];
  const isBlocked = blockers.some((b) => b.status !== "done");

  return (
    <div
      style={{
        background: "#141414",
        border: "1px solid #242424",
        borderRadius: 8,
        padding: "14px 16px",
        display: "flex",
        flexDirection: "column",
        gap: 8,
        opacity: task.status === "done" ? 0.5 : 1,
      }}
    >
      <div style={{ display: "flex", alignItems: "flex-start", gap: 10, justifyContent: "space-between" }}>
        <span style={{ fontWeight: 500, lineHeight: 1.4, flex: 1 }}>{task.title}</span>
        <div style={{ display: "flex", gap: 6, flexShrink: 0 }}>
          <Badge label={STATUS_LABEL[task.status]} color={statusColor(task.status)} />
          <Badge label={OWNER_LABEL[task.owner]} color={ownerColor(task.owner)} />
        </div>
      </div>

      {task.notes && (
        <p style={{ color: "#888", fontSize: 12, lineHeight: 1.5 }}>{task.notes}</p>
      )}

      {isBlocked && (
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap", alignItems: "center" }}>
          <span style={{ color: "#666", fontSize: 11 }}>Blocked by:</span>
          {blockers
            .filter((b) => b.status !== "done")
            .map((b) => (
              <span
                key={b.id}
                style={{
                  background: "#ff444411",
                  color: "#ff6b6b",
                  border: "1px solid #ff444433",
                  borderRadius: 4,
                  padding: "1px 7px",
                  fontSize: 11,
                }}
              >
                {b.id}
              </span>
            ))}
        </div>
      )}
    </div>
  );
}

function MilestoneGroup({ milestone, tasks, allTasks }: { milestone: string; tasks: Task[]; allTasks: Task[] }) {
  const done = tasks.filter((t) => t.status === "done").length;
  const pct = Math.round((done / tasks.length) * 100);

  return (
    <div style={{ marginBottom: 40 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 16 }}>
        <h2 style={{ fontSize: 16, fontWeight: 700, color: "#e8e8e8" }}>{milestone}</h2>
        <span style={{ color: "#666", fontSize: 12 }}>
          {done}/{tasks.length} done
        </span>
        <div style={{ flex: 1, height: 3, background: "#242424", borderRadius: 2, maxWidth: 120 }}>
          <div
            style={{
              height: "100%",
              width: `${pct}%`,
              background: pct === 100 ? "#16a34a" : "#d97706",
              borderRadius: 2,
              transition: "width 0.3s",
            }}
          />
        </div>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
        {tasks.map((t) => (
          <TaskCard key={t.id} task={t} allTasks={allTasks} />
        ))}
      </div>
    </div>
  );
}

export default async function Dashboard() {
  let data: TasksFile;
  try {
    data = await getTasks();
  } catch {
    return (
      <main style={{ padding: 40, color: "#ff6b6b" }}>
        Failed to load tasks.json from GitHub. Make sure the repo is public and tasks.json is on the main branch.
      </main>
    );
  }

  const { tasks, meta } = data;
  const total = tasks.length;
  const done = tasks.filter((t) => t.status === "done").length;
  const inProgress = tasks.filter((t) => t.status === "in-progress").length;

  // Group by milestone, preserving order
  const milestoneOrder = [...new Set(tasks.map((t) => t.milestone))];
  const byMilestone = milestoneOrder.map((m) => ({
    milestone: m,
    tasks: tasks.filter((t) => t.milestone === m),
  }));

  return (
    <main style={{ maxWidth: 860, margin: "0 auto", padding: "40px 24px" }}>
      {/* Header */}
      <div style={{ marginBottom: 40 }}>
        <h1 style={{ fontSize: 28, fontWeight: 800, letterSpacing: -0.5, marginBottom: 4 }}>
          Legacy
        </h1>
        <p style={{ color: "#666", fontSize: 13 }}>
          Last updated: {meta.lastUpdated} · auto-refreshes every 30s
        </p>

        {/* Summary row */}
        <div style={{ display: "flex", gap: 24, marginTop: 24 }}>
          {[
            { label: "Total", value: total, color: "#e8e8e8" },
            { label: "Done", value: done, color: "#16a34a" },
            { label: "In Progress", value: inProgress, color: "#d97706" },
            { label: "Todo", value: total - done - inProgress, color: "#666" },
          ].map(({ label, value, color }) => (
            <div key={label}>
              <div style={{ fontSize: 28, fontWeight: 700, color }}>{value}</div>
              <div style={{ fontSize: 12, color: "#666", marginTop: 2 }}>{label}</div>
            </div>
          ))}
        </div>

        {/* Overall progress bar */}
        <div style={{ height: 4, background: "#242424", borderRadius: 2, marginTop: 20 }}>
          <div
            style={{
              height: "100%",
              width: `${Math.round((done / total) * 100)}%`,
              background: "#16a34a",
              borderRadius: 2,
            }}
          />
        </div>
      </div>

      {/* Legend */}
      <div style={{ display: "flex", gap: 16, marginBottom: 32, flexWrap: "wrap" }}>
        {[
          { label: "Backend (Claude)", color: "#6366f1" },
          { label: "iOS (Cursor)", color: "#0ea5e9" },
          { label: "Either", color: "#8b5cf6" },
        ].map(({ label, color }) => (
          <div key={label} style={{ display: "flex", alignItems: "center", gap: 6 }}>
            <div style={{ width: 8, height: 8, borderRadius: "50%", background: color }} />
            <span style={{ fontSize: 12, color: "#888" }}>{label}</span>
          </div>
        ))}
      </div>

      {/* Milestones */}
      {byMilestone.map(({ milestone, tasks: milestoneTasks }) => (
        <MilestoneGroup
          key={milestone}
          milestone={milestone}
          tasks={milestoneTasks}
          allTasks={tasks}
        />
      ))}
    </main>
  );
}
