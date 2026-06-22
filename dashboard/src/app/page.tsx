"use client";
import { useState, useEffect, useCallback } from "react";
import type { TasksFile, Task, Owner, ManualTest } from "./types";
import TaskCard from "./components/TaskCard";
import MilestoneGroup, {
  collapseMilestones,
  expandAllMilestones,
} from "./components/MilestoneGroup";
import DecisionsPanel from "./components/DecisionsPanel";
import ManualTestPanel from "./components/ManualTestPanel";

const POLL_INTERVAL = 30;

const ANIMATIONS = `
  @keyframes pulse-ring {
    0%   { box-shadow: 0 0 0 0 #d9770688; }
    70%  { box-shadow: 0 0 0 5px #d9770600; }
    100% { box-shadow: 0 0 0 0 #d9770600; }
  }
  .pulse-dot { animation: pulse-ring 1.5s ease-out infinite; }

  @keyframes shimmer-move {
    0%   { background-position: -200% 0; }
    100% { background-position: 200% 0; }
  }
  .shimmer-bar {
    background: linear-gradient(90deg,#d97706 30%,#fbbf24 50%,#d97706 70%) !important;
    background-size: 300% 100% !important;
    animation: shimmer-move 2s linear infinite !important;
  }

  @keyframes header-flash {
    0%   { box-shadow: none; }
    20%  { box-shadow: 0 0 0 3px #16a34a55; }
    100% { box-shadow: none; }
  }
  .flash-anim { animation: header-flash 1.2s ease-out; }

  @keyframes live-pulse {
    0%, 100% { opacity: 1; }
    50%       { opacity: 0.25; }
  }
  .live-dot { animation: live-pulse 1.8s ease-in-out infinite; }
`;

function ownerColor(o: Owner | string) {
  if (o === "backend") return "#6366f1";
  if (o === "ios") return "#0ea5e9";
  return "#8b5cf6";
}

function OwnerBar({ label, owner, tasks }: { label: string; owner: Owner; tasks: Task[] }) {
  const ownerTasks = tasks.filter((t) => t.owner === owner);
  const done = ownerTasks.filter((t) => t.status === "done").length;
  const pct = ownerTasks.length > 0 ? Math.round((done / ownerTasks.length) * 100) : 0;
  const color = ownerColor(owner);
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10, fontSize: 12 }}>
      <span style={{ color: "#aaa", width: 56, flexShrink: 0 }}>{label}</span>
      <div style={{ flex: 1, height: 6, background: "#242424", borderRadius: 3, maxWidth: 180, overflow: "hidden" }}>
        <div style={{ height: "100%", width: `${pct}%`, background: color, borderRadius: 3, transition: "width 0.4s" }} />
      </div>
      <span style={{ color, fontWeight: 700, width: 34 }}>{pct}%</span>
      <span style={{ color: "#555" }}>({done}/{ownerTasks.length})</span>
    </div>
  );
}

export default function Dashboard() {
  const [data, setData] = useState<TasksFile | null>(null);
  const [fetchFailed, setFetchFailed] = useState(false);
  const [countdown, setCountdown] = useState(POLL_INTERVAL);
  const [flashKey, setFlashKey] = useState(0);
  const [readyOpen, setReadyOpen] = useState(false);
  const [milestoneCollapseRevision, setMilestoneCollapseRevision] = useState(0);

  const fetchTasks = useCallback(async () => {
    try {
      const res = await fetch(`/api/tasks?t=${Date.now()}`, { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json: TasksFile = await res.json();
      setData(json);
      setFetchFailed(false);
      setFlashKey((k) => k + 1);
      setCountdown(POLL_INTERVAL);
    } catch {
      setFetchFailed(true);
    }
  }, []);

  const handleManualTestUpdate = useCallback((updated: ManualTest) => {
    setData((prev) => {
      if (!prev) return prev;
      const manualTests = (prev.manualTests ?? []).map((t) =>
        t.id === updated.id ? updated : t
      );
      return { ...prev, manualTests };
    });
    void fetchTasks();
  }, [fetchTasks]);

  useEffect(() => { fetchTasks(); }, [fetchTasks]);

  useEffect(() => {
    const id = setInterval(fetchTasks, POLL_INTERVAL * 1000);
    return () => clearInterval(id);
  }, [fetchTasks]);

  useEffect(() => {
    const id = setInterval(() => setCountdown((c) => (c > 0 ? c - 1 : 0)), 1000);
    return () => clearInterval(id);
  }, []);

  if (!data && fetchFailed) {
    return (
      <main style={{ padding: 40, color: "#ff6b6b" }}>
        Failed to load tasks.json. Check that the dashboard can read tasks (local file or GITHUB_TOKEN).
      </main>
    );
  }
  if (!data) {
    return <main style={{ padding: 40, color: "#666" }}>Loading…</main>;
  }

  const { tasks, meta } = data;
  const decisions = data.decisions ?? [];
  const manualTests = data.manualTests ?? [];
  const qaPassed = manualTests.filter((t) => t.status === "passed").length;
  const qaPending = manualTests.filter((t) => t.status === "pending").length;
  const openDecisions = decisions.filter((d) => d.status === "open");
  const total = tasks.length;
  const done = tasks.filter((t) => t.status === "done").length;
  const inProgress = tasks.filter((t) => t.status === "in-progress").length;
  const todoCount = total - done - inProgress;
  const donePct = total > 0 ? Math.round((done / total) * 100) : 0;
  const inProgPct = total > 0 ? Math.round((inProgress / total) * 100) : 0;

  const blockedCount = tasks.filter(
    (t) =>
      t.status !== "done" &&
      t.blockedBy.some((id) => {
        const dep = tasks.find((x) => x.id === id);
        return dep && dep.status !== "done";
      })
  ).length;

  const readyTasks = tasks.filter(
    (t) =>
      t.status === "todo" &&
      t.blockedBy.every((id) => {
        const dep = tasks.find((x) => x.id === id);
        return !dep || dep.status === "done";
      })
  );

  const phases = ([0, 1, 2, 3] as const)
    .map((p) => {
      const pt = tasks.filter((t) => t.phase === p);
      const pd = pt.filter((t) => t.status === "done").length;
      return { phase: p, total: pt.length, done: pd };
    })
    .filter((p) => p.total > 0);

  const milestoneOrder = [...new Set(tasks.map((t) => t.milestone))].sort((a, b) => {
    const num = (m: string) => {
      const match = /^M(\d+)$/i.exec(m.trim());
      return match ? parseInt(match[1], 10) : 9999;
    };
    return num(a) - num(b);
  });
  const byMilestone = milestoneOrder.map((m) => ({
    milestone: m,
    tasks: tasks.filter((t) => t.milestone === m),
  }));

  const readyByOwner: { owner: Owner; label: string }[] = [
    { owner: "backend", label: "Backend" },
    { owner: "ios", label: "iOS" },
    { owner: "either", label: "Either" },
  ];

  return (
    <>
      <style>{ANIMATIONS}</style>
      <main style={{ maxWidth: 860, margin: "0 auto", padding: "40px 24px" }}>

        {/* ── Header ── */}
        <div style={{ marginBottom: 32 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 4 }}>
            <h1 style={{ fontSize: 28, fontWeight: 800, letterSpacing: -0.5 }}>Legacy</h1>
            {/* Live / Stale indicator */}
            <div style={{ display: "flex", alignItems: "center", gap: 5, marginLeft: 6 }}>
              <span
                className="live-dot"
                style={{
                  width: 7, height: 7, borderRadius: "50%",
                  background: fetchFailed ? "#ff6b6b" : "#16a34a",
                  display: "inline-block",
                }}
              />
              <span style={{ fontSize: 11, color: fetchFailed ? "#ff6b6b" : "#16a34a", fontWeight: 600 }}>
                {fetchFailed ? "Stale" : "Live"}
              </span>
            </div>
          </div>
          <p style={{ color: "#666", fontSize: 13 }}>
            Last updated: {meta.lastUpdated} · ↻ Refreshing in {countdown}s…
          </p>

          {/* Stats block — flashes green on each successful refresh */}
          <div
            key={`flash-${flashKey}`}
            className={flashKey > 0 ? "flash-anim" : ""}
            style={{
              display: "flex", gap: 28, marginTop: 20,
              padding: "16px 20px", background: "#141414",
              border: "1px solid #242424", borderRadius: 10,
            }}
          >
            {[
              { label: "Total",       value: total,      color: "#e8e8e8" },
              { label: "Done",        value: done,       color: "#16a34a" },
              { label: "In Progress", value: inProgress, color: "#d97706" },
              { label: "Todo",        value: todoCount,  color: "#666"    },
            ].map(({ label, value, color }) => (
              <div key={label}>
                <div style={{ fontSize: 28, fontWeight: 700, color }}>{value}</div>
                <div style={{ fontSize: 12, color: "#666", marginTop: 2 }}>{label}</div>
              </div>
            ))}
            {manualTests.length > 0 && (
              <a
                href="#manual-qa"
                style={{
                  textDecoration: "none",
                  marginLeft: "auto",
                  padding: "10px 14px",
                  background: qaPending > 0 ? "#0ea5e918" : "#16a34a18",
                  border: `1px solid ${qaPending > 0 ? "#0ea5e955" : "#16a34a55"}`,
                  borderRadius: 8,
                  flexShrink: 0,
                }}
              >
                <div
                  style={{
                    fontSize: 22,
                    fontWeight: 800,
                    color: qaPending > 0 ? "#0ea5e9" : "#16a34a",
                  }}
                >
                  {qaPassed}/{manualTests.length}
                </div>
                <div style={{ fontSize: 11, color: "#888", marginTop: 2 }}>
                  Manual QA {qaPending > 0 ? `· ${qaPending} to test` : "· all passed"}
                </div>
              </a>
            )}
          </div>

          {/* Manual QA — Joseph's Xcode checklist (prominent, near top) */}
          <ManualTestPanel tests={manualTests} onUpdate={handleManualTestUpdate} />

          {/* Segmented progress bar */}
          <div style={{ display: "flex", alignItems: "center", gap: 12, marginTop: 14 }}>
            <div
              style={{
                flex: 1, height: 6, background: "#242424", borderRadius: 3,
                display: "flex", overflow: "hidden",
              }}
            >
              <div style={{ height: "100%", width: `${donePct}%`, background: "#16a34a", transition: "width 0.5s" }} />
              <div style={{ height: "100%", width: `${inProgPct}%`, background: "#d97706", transition: "width 0.5s" }} />
            </div>
            <span style={{ fontSize: 12, color: "#16a34a", fontWeight: 700, whiteSpace: "nowrap" }}>
              {donePct}% done
            </span>
          </div>

          {/* Per-owner progress bars */}
          <div style={{ marginTop: 12, display: "flex", flexDirection: "column", gap: 7 }}>
            <OwnerBar label="Backend" owner="backend" tasks={tasks} />
            <OwnerBar label="iOS"     owner="ios"     tasks={tasks} />
          </div>

          {/* Blocked task warning */}
          {blockedCount > 0 && (
            <div
              style={{
                marginTop: 12, display: "flex", alignItems: "center", gap: 7,
                padding: "8px 12px", background: "#d9770611",
                border: "1px solid #d9770633", borderRadius: 6,
                fontSize: 12, color: "#d97706",
              }}
            >
              <span>⚠</span>
              <span>{blockedCount} task{blockedCount !== 1 ? "s" : ""} blocked by incomplete dependencies</span>
            </div>
          )}
        </div>

        {/* ── Decisions (top priority when open) ── */}
        {(openDecisions.length > 0 || decisions.some((d) => d.status === "decided")) && (
          <DecisionsPanel
            decisions={decisions}
            tasks={tasks}
            onResolved={fetchTasks}
            prominent={openDecisions.length > 0}
          />
        )}

        {/* ── Phase swimlane ── */}
        {phases.length > 0 && (
          <div
            style={{
              display: "flex", gap: 10, marginBottom: 28,
              padding: "14px 16px", background: "#141414",
              border: "1px solid #242424", borderRadius: 8,
            }}
          >
            {phases.map(({ phase, total: pt, done: pd }) => {
              const pct = pt > 0 ? Math.round((pd / pt) * 100) : 0;
              const isPhaseComplete = pct === 100;
              return (
                <div key={phase} style={{ flex: 1 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", marginBottom: 5 }}>
                    <span style={{ fontSize: 11, color: "#888", fontWeight: 600 }}>Phase {phase}</span>
                    <span style={{ fontSize: 11, color: isPhaseComplete ? "#16a34a" : "#555" }}>{pct}%</span>
                  </div>
                  <div style={{ height: 4, background: "#242424", borderRadius: 2, overflow: "hidden" }}>
                    <div
                      style={{
                        height: "100%", width: `${pct}%`,
                        background: isPhaseComplete ? "#16a34a" : "#6366f1",
                        borderRadius: 2, transition: "width 0.5s",
                      }}
                    />
                  </div>
                  <div style={{ fontSize: 10, color: "#555", marginTop: 3 }}>{pd}/{pt}</div>
                </div>
              );
            })}
          </div>
        )}

        {/* ── Legend ── */}
        <div style={{ display: "flex", gap: 16, marginBottom: 24, flexWrap: "wrap" }}>
          {[
            { label: "Backend (Claude)", color: "#6366f1" },
            { label: "iOS (Cursor)",     color: "#0ea5e9" },
            { label: "Either",           color: "#8b5cf6" },
          ].map(({ label, color }) => (
            <div key={label} style={{ display: "flex", alignItems: "center", gap: 6 }}>
              <div style={{ width: 8, height: 8, borderRadius: "50%", background: color }} />
              <span style={{ fontSize: 12, color: "#888" }}>{label}</span>
            </div>
          ))}
        </div>

        {/* ── Ready to build ── */}
        {readyTasks.length > 0 && (
          <div style={{ marginBottom: 32 }}>
            <button
              onClick={() => setReadyOpen((o) => !o)}
              style={{
                display: "flex", alignItems: "center", gap: 8,
                background: "#16a34a11", border: "1px solid #16a34a33",
                borderRadius: 6, padding: "8px 14px", cursor: "pointer",
                color: "#16a34a", fontSize: 13, fontWeight: 600,
                width: "100%", textAlign: "left",
              }}
            >
              <span>✓ Ready to build ({readyTasks.length} task{readyTasks.length !== 1 ? "s" : ""})</span>
              <span style={{ marginLeft: "auto", fontSize: 10 }}>{readyOpen ? "▲" : "▼"}</span>
            </button>
            {readyOpen && (
              <div style={{ marginTop: 12 }}>
                {readyByOwner.map(({ owner, label }) => {
                  const group = readyTasks.filter((t) => t.owner === owner);
                  if (group.length === 0) return null;
                  return (
                    <div key={owner} style={{ marginBottom: 10 }}>
                      <div style={{ fontSize: 11, color: "#666", fontWeight: 600, marginBottom: 5 }}>{label}</div>
                      <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
                        {group.map((t) => (
                          <span
                            key={t.id}
                            title={t.title}
                            style={{
                              background: "#141414", border: "1px solid #242424",
                              borderRadius: 4, padding: "3px 10px",
                              fontSize: 11, color: "#ccc",
                              display: "flex", alignItems: "center", gap: 5,
                              maxWidth: 240, overflow: "hidden", whiteSpace: "nowrap",
                            }}
                          >
                            <span
                              style={{
                                width: 6, height: 6, borderRadius: "50%",
                                background: ownerColor(owner), flexShrink: 0, display: "inline-block",
                              }}
                            />
                            <span style={{ overflow: "hidden", textOverflow: "ellipsis" }}>
                              {t.title.length > 38 ? t.title.slice(0, 38) + "…" : t.title}
                            </span>
                          </span>
                        ))}
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        )}

        {/* ── Milestones (M0 … M11) ── */}
        {byMilestone.length > 0 && (
          <div style={{ marginBottom: 8 }}>
            <div
              style={{
                display: "flex",
                alignItems: "center",
                gap: 10,
                marginBottom: 12,
              }}
            >
              <h2 style={{ fontSize: 15, fontWeight: 800, color: "#e8e8e8", margin: 0 }}>
                Milestones
              </h2>
              <span style={{ color: "#555", fontSize: 11 }}>
                Click ▼ on any row to collapse
              </span>
              <div style={{ marginLeft: "auto", display: "flex", gap: 8 }}>
                <button
                  type="button"
                  onClick={() => {
                    const complete = byMilestone
                      .filter(
                        ({ tasks: mt }) => mt.length > 0 && mt.every((t) => t.status === "done")
                      )
                      .map(({ milestone: m }) => m);
                    collapseMilestones(complete);
                    setMilestoneCollapseRevision((n) => n + 1);
                  }}
                  style={{
                    background: "#141414",
                    border: "1px solid #333",
                    borderRadius: 4,
                    color: "#aaa",
                    fontSize: 11,
                    padding: "4px 10px",
                    cursor: "pointer",
                  }}
                >
                  Collapse completed
                </button>
                <button
                  type="button"
                  onClick={() => {
                    expandAllMilestones();
                    setMilestoneCollapseRevision((n) => n + 1);
                  }}
                  style={{
                    background: "#141414",
                    border: "1px solid #333",
                    borderRadius: 4,
                    color: "#aaa",
                    fontSize: 11,
                    padding: "4px 10px",
                    cursor: "pointer",
                  }}
                >
                  Expand all
                </button>
              </div>
            </div>
          </div>
        )}
        {byMilestone.map(({ milestone, tasks: mt }) => (
          <MilestoneGroup
            key={milestone}
            milestone={milestone}
            tasks={mt}
            allTasks={tasks}
            collapseRevision={milestoneCollapseRevision}
          />
        ))}
      </main>
    </>
  );
}
