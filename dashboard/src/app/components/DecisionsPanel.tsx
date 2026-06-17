"use client";
import { useCallback, useEffect, useState } from "react";
import type { Task, Decision, DecisionOption } from "../types";

const SECRET_KEY = "legacy-dashboard-secret";

function getStoredSecret(): string {
  if (typeof window === "undefined") return "";
  return sessionStorage.getItem(SECRET_KEY) ?? "";
}

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
  const chosen =
    resolved && d.chosenOptionId
      ? d.options?.find((o) => o.id === d.chosenOptionId)
      : undefined;

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

      {resolved && chosen && (
        <p style={{ color: "#16a34a", fontSize: 13, fontWeight: 600, lineHeight: 1.5 }}>
          Chose: {chosen.label}
        </p>
      )}

      {resolved && d.resolution ? (
        <p style={{ color: "#888", fontSize: 13, lineHeight: 1.5 }}>{d.resolution}</p>
      ) : (
        !resolved && <p style={{ color: "#aaa", fontSize: 13, lineHeight: 1.5 }}>{d.detail}</p>
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

function OptionButton({
  option,
  selected,
  disabled,
  onSelect,
}: {
  option: DecisionOption;
  selected: boolean;
  disabled: boolean;
  onSelect: () => void;
}) {
  return (
    <button
      type="button"
      disabled={disabled}
      onClick={onSelect}
      style={{
        textAlign: "left",
        width: "100%",
        padding: "14px 16px",
        borderRadius: 8,
        cursor: disabled ? "not-allowed" : "pointer",
        opacity: disabled ? 0.6 : 1,
        background: selected ? "#d9770618" : "#1a1a1a",
        border: selected ? "2px solid #d97706" : "1px solid #333",
        display: "flex",
        flexDirection: "column",
        gap: 6,
        transition: "border-color 0.15s, background 0.15s",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 8, justifyContent: "space-between" }}>
        <span style={{ fontWeight: 600, color: "#e8e8e8", fontSize: 14 }}>{option.label}</span>
        <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
          {option.recommended && (
            <span
              style={{
                fontSize: 10,
                fontWeight: 700,
                color: "#16a34a",
                background: "#16a34a22",
                border: "1px solid #16a34a44",
                borderRadius: 4,
                padding: "2px 6px",
              }}
            >
              Recommended
            </span>
          )}
          {selected && (
            <span style={{ fontSize: 11, color: "#d97706", fontWeight: 700 }}>Selected</span>
          )}
        </div>
      </div>
      {option.description && (
        <span style={{ color: "#888", fontSize: 12, lineHeight: 1.5 }}>{option.description}</span>
      )}
    </button>
  );
}

function OpenDecisionCard({
  d,
  tasks,
  onResolved,
}: {
  d: Decision;
  tasks: Task[];
  onResolved: () => void;
}) {
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [needsSecret, setNeedsSecret] = useState(false);
  const [secretInput, setSecretInput] = useState("");

  const options = d.options ?? [];

  useEffect(() => {
    const recommended = options.find((o) => o.recommended);
    if (recommended && !selectedId) setSelectedId(recommended.id);
  }, [options, selectedId]);

  const submit = useCallback(
    async (optionId: string, secret?: string) => {
      setSubmitting(true);
      setError(null);
      try {
        const headers: Record<string, string> = { "Content-Type": "application/json" };
        const stored = secret ?? getStoredSecret();
        if (stored) headers["X-Decisions-Secret"] = stored;

        const res = await fetch("/api/decisions/resolve", {
          method: "POST",
          headers,
          body: JSON.stringify({
            decisionId: d.id,
            optionId,
            secret: stored || undefined,
          }),
        });

        const json = (await res.json()) as { error?: string };

        if (res.status === 401) {
          setNeedsSecret(true);
          setError("Enter your decision PIN to lock in choices on the live dashboard.");
          return;
        }
        if (!res.ok) throw new Error(json.error ?? `Request failed (${res.status})`);

        if (secret) sessionStorage.setItem(SECRET_KEY, secret);
        setNeedsSecret(false);
        onResolved();
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to save decision");
      } finally {
        setSubmitting(false);
      }
    },
    [d.id, onResolved]
  );

  const handleConfirm = () => {
    if (!selectedId) return;
    if (needsSecret && !secretInput.trim()) {
      setError("PIN required");
      return;
    }
    void submit(selectedId, needsSecret ? secretInput.trim() : undefined);
  };

  return (
    <div
      style={{
        background: "#161310",
        border: "1px solid #d9770655",
        borderLeft: "4px solid #d97706",
        borderRadius: 10,
        padding: "18px 18px 16px",
        display: "flex",
        flexDirection: "column",
        gap: 14,
      }}
    >
      <DecisionCard d={d} tasks={tasks} resolved={false} />

      {options.length === 0 ? (
        <p style={{ color: "#ff6b6b", fontSize: 12, lineHeight: 1.5 }}>
          This decision is missing <code style={{ color: "#ff6b6b" }}>options[]</code> in tasks.json.
          Claude/Cursor must add choosable options before you can decide here.
        </p>
      ) : (
        <>
          <div>
            <p style={{ fontSize: 12, fontWeight: 700, color: "#d97706", marginBottom: 10, letterSpacing: 0.3 }}>
              YOUR CHOICE — pick one
            </p>
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {options.map((option) => (
                <OptionButton
                  key={option.id}
                  option={option}
                  selected={selectedId === option.id}
                  disabled={submitting}
                  onSelect={() => setSelectedId(option.id)}
                />
              ))}
            </div>
          </div>

          {d.recommendation && (
            <p style={{ color: "#666", fontSize: 11, lineHeight: 1.5 }}>
              <strong style={{ color: "#888" }}>Context:</strong> {d.recommendation}
            </p>
          )}

          {needsSecret && (
            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
              <label style={{ fontSize: 11, color: "#888" }}>Decision PIN (set in Vercel as DECISIONS_SECRET)</label>
              <input
                type="password"
                value={secretInput}
                onChange={(e) => setSecretInput(e.target.value)}
                placeholder="Enter PIN"
                style={{
                  padding: "8px 12px",
                  borderRadius: 6,
                  border: "1px solid #333",
                  background: "#0e0e0e",
                  color: "#e8e8e8",
                  fontSize: 13,
                }}
              />
            </div>
          )}

          {error && (
            <p style={{ color: "#ff6b6b", fontSize: 12 }}>{error}</p>
          )}

          <button
            type="button"
            disabled={!selectedId || submitting}
            onClick={handleConfirm}
            style={{
              alignSelf: "flex-start",
              padding: "10px 20px",
              borderRadius: 6,
              border: "none",
              background: selectedId && !submitting ? "#d97706" : "#333",
              color: selectedId && !submitting ? "#111" : "#666",
              fontWeight: 700,
              fontSize: 13,
              cursor: selectedId && !submitting ? "pointer" : "not-allowed",
            }}
          >
            {submitting ? "Saving…" : "Lock in this choice"}
          </button>
        </>
      )}
    </div>
  );
}

export default function DecisionsPanel({
  decisions,
  tasks,
  onResolved,
  prominent = false,
}: {
  decisions: Decision[];
  tasks: Task[];
  onResolved: () => void;
  prominent?: boolean;
}) {
  const open = decisions.filter((d) => d.status === "open");
  const decided = decisions.filter((d) => d.status === "decided");
  if (open.length === 0 && decided.length === 0) return null;

  return (
    <div
      style={{
        marginBottom: prominent ? 32 : 40,
        ...(prominent
          ? {
              padding: "18px 18px 6px",
              background: "#1a1408",
              border: "1px solid #d9770644",
              borderRadius: 12,
            }
          : {}),
      }}
    >
      {open.length > 0 && (
        <>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 16 }}>
            <span style={{ fontSize: 18 }}>⚠️</span>
            <h2 style={{ fontSize: 18, fontWeight: 800, color: "#e8e8e8" }}>
              Needs your decision
            </h2>
            <span style={{ color: "#d97706", fontSize: 12, fontWeight: 600 }}>{open.length} open</span>
          </div>
          <p style={{ color: "#888", fontSize: 13, marginBottom: 16, lineHeight: 1.5 }}>
            Pick an option below — your choice is saved to <code>tasks.json</code> and unblocks the team.
          </p>
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: 16,
              marginBottom: decided.length > 0 ? 24 : 0,
            }}
          >
            {open.map((d) => (
              <OpenDecisionCard key={d.id} d={d} tasks={tasks} onResolved={onResolved} />
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

      {decided.length > 0 && !prominent && (
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
