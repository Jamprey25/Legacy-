"use client";
import { useCallback, useEffect, useState } from "react";
import type { Task } from "../types";
import TaskCard from "./TaskCard";

const STORAGE_KEY = "legacy-dashboard-milestone-collapsed";

type CollapsePrefs = { collapsed: Set<string>; userHasPrefs: boolean };

function readCollapsePrefs(): CollapsePrefs {
  if (typeof window === "undefined") {
    return { collapsed: new Set(), userHasPrefs: false };
  }
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw === null) return { collapsed: new Set(), userHasPrefs: false };
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return { collapsed: new Set(), userHasPrefs: false };
    return {
      collapsed: new Set(parsed.filter((x): x is string => typeof x === "string")),
      userHasPrefs: true,
    };
  } catch {
    return { collapsed: new Set(), userHasPrefs: false };
  }
}

function writeCollapsePrefs(collapsed: Set<string>) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify([...collapsed]));
}

function resolveCollapsed(milestone: string, isComplete: boolean): boolean {
  const { collapsed, userHasPrefs } = readCollapsePrefs();
  if (userHasPrefs) return collapsed.has(milestone);
  return isComplete;
}

/** Collapse every milestone id in the list (e.g. all 100%-done groups). */
export function collapseMilestones(milestones: string[]) {
  const { collapsed } = readCollapsePrefs();
  for (const m of milestones) collapsed.add(m);
  writeCollapsePrefs(collapsed);
}

/** Expand every milestone section. */
export function expandAllMilestones() {
  writeCollapsePrefs(new Set());
}

export default function MilestoneGroup({
  milestone,
  tasks,
  allTasks,
  collapseRevision = 0,
}: {
  milestone: string;
  tasks: Task[];
  allTasks: Task[];
  collapseRevision?: number;
}) {
  const done = tasks.filter((t) => t.status === "done").length;
  const inProg = tasks.filter((t) => t.status === "in-progress").length;
  const pct = tasks.length > 0 ? Math.round((done / tasks.length) * 100) : 0;
  const isComplete = pct === 100 && tasks.length > 0;
  const hasActive = inProg > 0 && !isComplete;

  const [collapsed, setCollapsed] = useState(false);

  useEffect(() => {
    setCollapsed(resolveCollapsed(milestone, isComplete));
  }, [milestone, isComplete, collapseRevision]);

  const toggleCollapsed = useCallback(() => {
    setCollapsed((prev) => {
      const next = !prev;
      const { collapsed: saved } = readCollapsePrefs();
      if (next) saved.add(milestone);
      else saved.delete(milestone);
      writeCollapsePrefs(saved);
      return next;
    });
  }, [milestone]);

  return (
    <section
      style={{
        marginBottom: 16,
        borderRadius: 10,
        border: `1px solid ${isComplete ? "#16a34a33" : "#2a2a2a"}`,
        background: isComplete ? "#101510" : "#141414",
        overflow: "hidden",
      }}
    >
      <button
        type="button"
        onClick={toggleCollapsed}
        aria-expanded={!collapsed}
        aria-controls={`milestone-panel-${milestone}`}
        style={{
          display: "flex",
          alignItems: "center",
          gap: 10,
          width: "100%",
          padding: "14px 16px",
          border: "none",
          background: collapsed ? "transparent" : "#1a1a1a",
          cursor: "pointer",
          textAlign: "left",
          font: "inherit",
          color: "inherit",
        }}
      >
        <span
          aria-hidden
          style={{
            color: "#aaa",
            fontSize: 13,
            fontWeight: 700,
            width: 16,
            flexShrink: 0,
            lineHeight: 1,
            transition: "transform 0.15s ease",
            transform: collapsed ? "rotate(-90deg)" : "rotate(0deg)",
            display: "inline-block",
          }}
        >
          ▼
        </span>
        {isComplete && (
          <span style={{ color: "#16a34a", fontSize: 14, fontWeight: 800, flexShrink: 0 }}>✓</span>
        )}
        <h2
          style={{
            fontSize: 16,
            fontWeight: 700,
            color: isComplete ? "#16a34a" : "#e8e8e8",
            margin: 0,
            flexShrink: 0,
          }}
        >
          {milestone}
        </h2>
        <span style={{ color: "#666", fontSize: 12, flexShrink: 0 }}>
          {done}/{tasks.length}
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
              flexShrink: 0,
            }}
          >
            Complete
          </span>
        )}
        <div
          style={{
            flex: 1,
            height: 4,
            background: "#242424",
            borderRadius: 2,
            overflow: "hidden",
            minWidth: 60,
            marginLeft: 8,
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
        <span style={{ color: "#555", fontSize: 11, flexShrink: 0, marginLeft: 8 }}>
          {collapsed ? "Expand" : "Collapse"}
        </span>
      </button>

      {!collapsed && (
        <div
          id={`milestone-panel-${milestone}`}
          style={{
            display: "flex",
            flexDirection: "column",
            gap: 8,
            padding: "0 12px 12px",
            opacity: isComplete ? 0.65 : 1,
          }}
        >
          {tasks.map((t) => (
            <TaskCard key={t.id} task={t} allTasks={allTasks} />
          ))}
        </div>
      )}
    </section>
  );
}
