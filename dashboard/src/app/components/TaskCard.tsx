"use client";
import type { Task } from "../types";

const STATUS_LABEL: Record<string, string> = {
  todo: "Todo",
  "in-progress": "In Progress",
  done: "Done",
};

const OWNER_LABEL: Record<string, string> = {
  backend: "Backend",
  ios: "iOS",
  either: "Either",
};

function statusColor(s: string) {
  if (s === "done") return "#16a34a";
  if (s === "in-progress") return "#d97706";
  return "#444";
}

function ownerColor(o: string) {
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

export default function TaskCard({ task, allTasks }: { task: Task; allTasks: Task[] }) {
  const blockers = (task.blockedBy ?? [])
    .map((id) => allTasks.find((t) => t.id === id))
    .filter(Boolean) as Task[];
  const isBlocked = blockers.some((b) => b.status !== "done");
  const isInProgress = task.status === "in-progress";

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
        <div style={{ display: "flex", gap: 6, flexShrink: 0, alignItems: "center" }}>
          {isInProgress && (
            <span
              className="pulse-dot"
              style={{
                width: 8,
                height: 8,
                borderRadius: "50%",
                background: "#d97706",
                display: "inline-block",
                flexShrink: 0,
              }}
            />
          )}
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
                title={b.title}
                style={{
                  background: "#ff444411",
                  color: "#ff6b6b",
                  border: "1px solid #ff444433",
                  borderRadius: 4,
                  padding: "1px 7px",
                  fontSize: 11,
                  cursor: "help",
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
