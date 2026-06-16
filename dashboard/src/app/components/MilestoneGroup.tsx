"use client";
import type { Task } from "../types";
import TaskCard from "./TaskCard";

export default function MilestoneGroup({
  milestone,
  tasks,
  allTasks,
}: {
  milestone: string;
  tasks: Task[];
  allTasks: Task[];
}) {
  const done = tasks.filter((t) => t.status === "done").length;
  const inProg = tasks.filter((t) => t.status === "in-progress").length;
  const pct = tasks.length > 0 ? Math.round((done / tasks.length) * 100) : 0;
  const isComplete = pct === 100 && tasks.length > 0;
  const hasActive = inProg > 0 && !isComplete;

  return (
    <div
      style={{
        marginBottom: 40,
        background: isComplete ? "#16a34a08" : "transparent",
        borderRadius: isComplete ? 10 : 0,
        padding: isComplete ? "16px" : 0,
        border: isComplete ? "1px solid #16a34a22" : "1px solid transparent",
        transition: "background 0.4s, border-color 0.4s",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 16 }}>
        {isComplete && (
          <span style={{ color: "#16a34a", fontSize: 14, fontWeight: 800, flexShrink: 0 }}>✓</span>
        )}
        <h2
          style={{
            fontSize: 16,
            fontWeight: 700,
            color: isComplete ? "#16a34a" : "#e8e8e8",
            transition: "color 0.3s",
          }}
        >
          {milestone}
        </h2>
        <span style={{ color: "#666", fontSize: 12 }}>
          {done}/{tasks.length} done
        </span>
        {isComplete && (
          <span
            style={{
              background: "#16a34a22",
              color: "#16a34a",
              border: "1px solid #16a34a44",
              borderRadius: 4,
              padding: "1px 8px",
              fontSize: 11,
              fontWeight: 600,
            }}
          >
            Complete
          </span>
        )}
        <div
          style={{
            flex: 1,
            height: 3,
            background: "#242424",
            borderRadius: 2,
            maxWidth: 120,
            overflow: "hidden",
          }}
        >
          <div
            className={hasActive ? "shimmer-bar" : ""}
            style={{
              height: "100%",
              width: `${pct}%`,
              background: isComplete ? "#16a34a" : "#d97706",
              borderRadius: 2,
              transition: "width 0.3s",
            }}
          />
        </div>
      </div>
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          gap: 8,
          opacity: isComplete ? 0.55 : 1,
          transition: "opacity 0.4s",
        }}
      >
        {tasks.map((t) => (
          <TaskCard key={t.id} task={t} allTasks={allTasks} />
        ))}
      </div>
    </div>
  );
}
