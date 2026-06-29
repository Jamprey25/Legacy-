"use client";
import { useCallback, useEffect, useState } from "react";
import type { Task, Decision, DecisionOption, ThreadResponse } from "../types";

import {
  clearStoredDashboardSecret,
  getStoredDashboardSecret,
  setStoredDashboardSecret,
} from "@/lib/dashboardAuth";

function resolveSecret(explicit?: string): string {
  return (explicit ?? getStoredDashboardSecret()).trim();
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
  const blockedTasks = (d.blocks ?? [])
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
        const stored = resolveSecret(secret);
        if (!stored) {
          setNeedsSecret(true);
          setError("Save your dashboard PIN at the top of the page first.");
          return;
        }
        const headers: Record<string, string> = { "Content-Type": "application/json" };
        headers["X-Decisions-Secret"] = stored;

        const res = await fetch("/api/decisions/resolve", {
          method: "POST",
          headers,
          body: JSON.stringify({
            decisionId: d.id,
            optionId,
            secret: stored,
          }),
        });

        const json = (await res.json()) as { error?: string };

        if (res.status === 401) {
          clearStoredDashboardSecret();
          setNeedsSecret(true);
          setError("PIN didn't match. Re-enter at the top bar (check Vercel DECISIONS_SECRET).");
          return;
        }
        if (!res.ok) throw new Error(json.error ?? `Request failed (${res.status})`);

        setStoredDashboardSecret(stored);
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
    const inline = secretInput.trim();
    const stored = resolveSecret(inline || undefined);
    if (!stored) {
      setNeedsSecret(true);
      setError("Save your dashboard PIN at the top of the page first.");
      return;
    }
    void submit(selectedId, inline || undefined);
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

const KIND_META: Record<string, { emoji: string; color: string; label: string }> = {
  question: { emoji: "❓", color: "#0ea5e9", label: "Question" },
  concern:  { emoji: "⚠️", color: "#f59e0b", label: "Concern"  },
  idea:     { emoji: "💡", color: "#8b5cf6", label: "Idea"     },
};

const AUTHOR_COLOR: Record<string, string> = {
  backend: "#6366f1",
  ios:     "#0ea5e9",
  joseph:  "#16a34a",
  either:  "#8b5cf6",
};

function ThreadCard({
  d,
  onResponded,
}: {
  d: Decision;
  onResponded: () => void;
}) {
  const meta = KIND_META[d.kind] ?? KIND_META.question;
  const isResolved = d.status === "resolved";
  const [replyText, setReplyText] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [open, setOpen] = useState(!isResolved);
  const [needsSecret, setNeedsSecret] = useState(false);
  const [secretInput, setSecretInput] = useState("");

  const submit = useCallback(async (secret?: string) => {
    if (!replyText.trim()) return;
    setSubmitting(true);
    setError(null);
    try {
      const stored = resolveSecret(secret);
      if (!stored) {
        setNeedsSecret(true);
        setError("Save your dashboard PIN at the top of the page first.");
        setSubmitting(false);
        return;
      }
      const headers: Record<string, string> = { "Content-Type": "application/json" };
      headers["X-Decisions-Secret"] = stored;

      const res = await fetch("/api/discussions/respond", {
        method: "POST",
        headers,
        body: JSON.stringify({ itemId: d.id, author: "joseph", text: replyText.trim(), secret: stored }),
      });
      const json = (await res.json()) as { error?: string };

      if (res.status === 401) {
        clearStoredDashboardSecret();
        setNeedsSecret(true);
        setError("PIN didn't match. Re-enter at the top bar (check Vercel DECISIONS_SECRET).");
        setSubmitting(false);
        return;
      }
      if (!res.ok) throw new Error(json.error ?? `Request failed (${res.status})`);

      setStoredDashboardSecret(stored);
      setReplyText("");
      setNeedsSecret(false);
      onResponded();
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save reply");
    } finally {
      setSubmitting(false);
    }
  }, [d.id, replyText, onResponded]);

  const handleReplyClick = () => {
    if (!replyText.trim()) return;
    const inline = secretInput.trim();
    const stored = resolveSecret(inline || undefined);
    if (!stored) {
      setNeedsSecret(true);
      setError("Save your dashboard PIN at the top of the page first.");
      return;
    }
    void submit(inline || undefined);
  };

  return (
    <div style={{
      background: isResolved ? "#0f1210" : "#12111a",
      border: `1px solid ${meta.color}33`,
      borderLeft: `3px solid ${isResolved ? "#16a34a" : meta.color}`,
      borderRadius: 8,
      overflow: "hidden",
      opacity: isResolved ? 0.8 : 1,
    }}>
      {/* Header */}
      <button
        type="button"
        onClick={() => setOpen(o => !o)}
        style={{
          width: "100%", textAlign: "left", background: "none", border: "none",
          padding: "12px 14px", cursor: "pointer",
          display: "flex", alignItems: "center", gap: 8,
        }}
      >
        <span style={{ fontSize: 14 }}>{isResolved ? "✓" : meta.emoji}</span>
        <span style={{ fontWeight: 600, color: "#e8e8e8", fontSize: 13, flex: 1 }}>{d.title}</span>
        <span style={{
          fontSize: 10, fontWeight: 700, padding: "2px 7px", borderRadius: 4,
          background: meta.color + "22", color: meta.color, border: `1px solid ${meta.color}44`,
        }}>{meta.label}</span>
        <span style={{ fontSize: 10, color: "#555" }}>
          {d.raisedBy} · {(d.responses ?? []).length} repl{(d.responses ?? []).length === 1 ? "y" : "ies"}
        </span>
        <span style={{ fontSize: 10, color: "#444" }}>{open ? "▲" : "▼"}</span>
      </button>

      {open && (
        <div style={{ padding: "0 14px 14px", display: "flex", flexDirection: "column", gap: 10 }}>
          {/* Original post */}
          <p style={{ color: "#aaa", fontSize: 13, lineHeight: 1.6, margin: 0 }}>{d.detail}</p>

          {/* Thread */}
          {(d.responses ?? []).length > 0 && (
            <div style={{ display: "flex", flexDirection: "column", gap: 6, borderLeft: "2px solid #222", paddingLeft: 12 }}>
              {(d.responses ?? []).map((r: ThreadResponse, i: number) => (
                <div key={i} style={{ display: "flex", flexDirection: "column", gap: 2 }}>
                  <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
                    <span style={{
                      fontSize: 10, fontWeight: 700,
                      color: AUTHOR_COLOR[r.author] ?? "#888",
                    }}>{r.author}</span>
                    <span style={{ fontSize: 10, color: "#444" }}>{r.date}</span>
                  </div>
                  <p style={{ color: "#ccc", fontSize: 12, lineHeight: 1.6, margin: 0 }}>
                    {r.text ?? (r as { message?: string }).message ?? ""}
                  </p>
                </div>
              ))}
            </div>
          )}

          {/* Joseph reply box */}
          {!isResolved && (
            <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
              <textarea
                value={replyText}
                onChange={e => setReplyText(e.target.value)}
                placeholder="Reply as Joseph…"
                rows={2}
                style={{
                  padding: "8px 10px", borderRadius: 6, border: "1px solid #2a2a2a",
                  background: "#0e0e0e", color: "#e8e8e8", fontSize: 12,
                  resize: "vertical", fontFamily: "inherit",
                }}
              />

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

              {error && <p style={{ color: "#ff6b6b", fontSize: 11, margin: 0 }}>{error}</p>}
              <button
                type="button"
                disabled={!replyText.trim() || submitting}
                onClick={handleReplyClick}
                style={{
                  alignSelf: "flex-start", padding: "6px 14px", borderRadius: 6,
                  border: "none", fontWeight: 600, fontSize: 12, cursor: "pointer",
                  background: replyText.trim() && !submitting ? meta.color : "#333",
                  color: replyText.trim() && !submitting ? "#fff" : "#666",
                }}
              >
                {submitting ? "Saving…" : "Reply"}
              </button>
            </div>
          )}
        </div>
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
  const THREAD_KINDS = new Set(["question", "concern", "idea"]);
  const DECISION_KINDS = new Set(["decision", "blocker"]);

  const open = decisions.filter((d) => d.status === "open" && DECISION_KINDS.has(d.kind));
  const decided = decisions.filter((d) => d.status === "decided");
  const threads = decisions.filter((d) => THREAD_KINDS.has(d.kind));
  const openThreads = threads.filter((d) => d.status !== "resolved");

  if (open.length === 0 && decided.length === 0 && threads.length === 0) return null;

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

      {open.length === 0 && decided.length > 0 && openThreads.length === 0 && (
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
      {open.length === 0 && openThreads.length > 0 && (
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            marginBottom: 14,
            padding: "10px 14px",
            background: "#0e1318",
            border: "1px solid #0ea5e933",
            borderRadius: 8,
          }}
        >
          <span style={{ fontSize: 16 }}>💬</span>
          <span style={{ fontSize: 14, fontWeight: 600, color: "#0ea5e9" }}>
            {openThreads.length} open question{openThreads.length !== 1 ? "s" : ""} or concern{openThreads.length !== 1 ? "s" : ""} — see below
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

      {threads.length > 0 && (
        <div style={{ marginTop: (open.length > 0 || decided.length > 0) ? 32 : 0 }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8, marginBottom: 14 }}>
            <h2 style={{ fontSize: 16, fontWeight: 700, color: "#e8e8e8" }}>
              Questions, Concerns & Ideas
            </h2>
            {openThreads.length > 0 && (
              <span style={{
                background: "#0ea5e922", color: "#0ea5e9",
                border: "1px solid #0ea5e944",
                borderRadius: 4, padding: "1px 8px", fontSize: 11, fontWeight: 600,
              }}>{openThreads.length} open</span>
            )}
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {threads.map((d) => (
              <ThreadCard key={d.id} d={d} onResponded={onResolved} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
