"use client";
import type { Task, Decision } from "../types";

function DecisionCard({
  d,
  tasks,
  resolved,
}: {
  d: Decision;
  tasks: Task[];
  resolved: boolean;
}) {
  const blockedTasks = d.blocks
    .map((id) => tasks.find((t) => t.id === id))
    .filter(Boolean) as Task[];
  const accent = resolved ? "#16a34a" : d.kind === "blocker" ? "#ff6b6b" : "#d97706";

  return (
    <div
      style={{
        background: resolved ? "#101510" : "#161310",
        border: `1px solid ${accent}55`,
        borderLeft: `3px solid ${accent}`,
        borderRadius: 8,
        padding: "14px 16px",
        display: "flex",
        flexDirection: "column",
        gap: 8,
        opacity: resolved ? 0.85 : 1,
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "flex-start",
          justifyContent: "space-between",
          gap: 10,
        }}
      >
        <span style={{ fontWeight: 600, lineHeight: 1.4 }}>
          {resolved && "✓ "}
          {d.title}
        </span>
        <span
          style={{
            background: accent + "22",
            color: accent,
            border: `1px solid ${accent}44`,
            borderRadius: 4,
            padding: "1px 8px",
            fontSize: 11,
            fontWeight: 600,
            whiteSpace: "nowrap",
          }}
        >
          {resolved ? "Decided" : `${d.needs === "joseph" ? "Joseph" : d.needs} to act`}
        </span>
      </div>

      {resolved && d.resolution ? (
        <p style={{ color: "#16a34a", fontSize: 13, lineHeight: 1.5 }}>{d.resolution}</p>
      ) : (
        <p style={{ color: "#aaa", fontSize: 13, lineHeight: 1.5 }}>{d.detail}</p>
      )}

      {!resolved && d.recommendation && (
        <p style={{ color: "#16a34a", fontSize: 12, lineHeight: 1.5 }}>
          <strong>Recommendation:</strong> {d.recommendation}
        </p>
      )}

      {!resolved && blockedTasks.length > 0 && (
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap", alignItems: "center" }}>
          <span style={{ color: "#666", fontSize: 11 }}>Blocks {blockedTasks.length}:</span>
          {blockedTasks.slice(0, 6).map((t) => (
            <span
              key={t.id}
              title={t.title}
              style={{
                background: "#ff444411",
                color: "#ff6b6b",
                border: "1px solid #ff444433",
                borderRadius: 4,
                padding: "1px 7px",
                fontSize: 11,
              }}
            >
              {t.id}
            </span>
          ))}
          {blockedTasks.length > 6 && (
            <span style={{ color: "#666", fontSize: 11 }}>+{blockedTasks.length - 6} more</span>
          )}
        </div>
      )}

      <div style={{ display: "flex", gap: 8, fontSize: 11, color: "#555" }}>
        <span>raised by {d.raisedBy}</span>
        <span>·</span>
        <span>{d.kind}</span>
      </div>
    </div>
  );
}

export default function DecisionsPanel({
  decisions,
  tasks,
}: {
  decisions: Decision[];
  tasks: Task[];
}) {
  const open = decisions.filter((d) => d.status === "open");
  const decided = decisions.filter((d) => d.status === "decided");
  if (open.length === 0 && decided.length === 0) return null;

  return (
    <div style={{ marginBottom: 40 }}>
      {open.length > 0 && (
        <>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 14 }}>
            <span style={{ fontSize: 16 }}>⚠️</span>
            <h2 style={{ fontSize: 16, fontWeight: 700, color: "#e8e8e8" }}>Needs a decision</h2>
            <span style={{ color: "#666", fontSize: 12 }}>{open.length} open</span>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 10, marginBottom: decided.length > 0 ? 24 : 0 }}>
            {open.map((d) => (
              <DecisionCard key={d.id} d={d} tasks={tasks} resolved={false} />
            ))}
          </div>
        </>
      )}

      {open.length === 0 && decided.length > 0 && (
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            marginBottom: 14,
            padding: "10px 14px",
            background: "#101510",
            border: "1px solid #16a34a33",
            borderRadius: 8,
          }}
        >
          <span style={{ fontSize: 16 }}>✓</span>
          <span style={{ fontSize: 14, fontWeight: 600, color: "#16a34a" }}>
            All decisions resolved — nothing blocking you
          </span>
        </div>
      )}

      {decided.length > 0 && (
        <>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 14 }}>
            <h2 style={{ fontSize: 14, fontWeight: 600, color: "#888" }}>Recently decided</h2>
            <span style={{ color: "#555", fontSize: 12 }}>{decided.length}</span>
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
            {decided.map((d) => (
              <DecisionCard key={d.id} d={d} tasks={tasks} resolved={true} />
            ))}
          </div>
        </>
      )}
    </div>
  );
}
