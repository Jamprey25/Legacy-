"use client";
import { useCallback, useState } from "react";
import type { ManualTest, ManualTestStatus } from "../types";
import {
  DASHBOARD_SECRET_HEADER,
  DASHBOARD_SECRET_STORAGE_KEY,
} from "@/lib/dashboardAuth";

function getStoredSecret(): string {
  if (typeof window === "undefined") return "";
  return sessionStorage.getItem(DASHBOARD_SECRET_STORAGE_KEY) ?? "";
}

function authorLabel(by: string) {
  if (by === "ios") return "Cursor";
  if (by === "backend") return "Claude";
  if (by === "joseph") return "Joseph";
  return by;
}

function TestRow({
  test,
  onUpdate,
}: {
  test: ManualTest;
  onUpdate: () => void;
}) {
  const [expanded, setExpanded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [needsSecret, setNeedsSecret] = useState(false);
  const [secretInput, setSecretInput] = useState("");

  const setStatus = useCallback(
    async (status: ManualTestStatus, secret?: string) => {
      setBusy(true);
      setError(null);
      try {
        const stored = secret ?? getStoredSecret();
        const headers: Record<string, string> = { "Content-Type": "application/json" };
        if (stored) headers[DASHBOARD_SECRET_HEADER] = stored;

        const res = await fetch("/api/manual-tests/update", {
          method: "POST",
          headers,
          body: JSON.stringify({
            testId: test.id,
            status,
            secret: stored || undefined,
          }),
        });
        const json = (await res.json()) as { error?: string };

        if (res.status === 401) {
          setNeedsSecret(true);
          setError("Enter your dashboard PIN to save QA results.");
          return;
        }
        if (!res.ok) throw new Error(json.error ?? `Request failed (${res.status})`);

        if (secret) sessionStorage.setItem(DASHBOARD_SECRET_STORAGE_KEY, secret);
        setNeedsSecret(false);
        onUpdate();
      } catch (err) {
        setError(err instanceof Error ? err.message : "Failed to save");
      } finally {
        setBusy(false);
      }
    },
    [test.id, onUpdate]
  );

  const handlePass = () => {
    if (needsSecret && !secretInput.trim()) {
      setError("PIN required");
      return;
    }
    void setStatus("passed", needsSecret ? secretInput.trim() : undefined);
  };

  const isPassed = test.status === "passed";
  const isFailed = test.status === "failed";

  return (
    <div
      style={{
        background: isPassed ? "#101510" : isFailed ? "#161010" : "#141414",
        border: `1px solid ${isPassed ? "#16a34a44" : isFailed ? "#ff444444" : "#242424"}`,
        borderRadius: 8,
        padding: "12px 14px",
        opacity: isPassed ? 0.75 : 1,
      }}
    >
      <div style={{ display: "flex", alignItems: "flex-start", gap: 12 }}>
        <button
          type="button"
          disabled={busy}
          onClick={() => (isPassed ? void setStatus("pending") : handlePass())}
          title={isPassed ? "Mark pending again" : "Mark passed"}
          style={{
            width: 22,
            height: 22,
            flexShrink: 0,
            marginTop: 1,
            borderRadius: 5,
            border: isPassed ? "none" : "2px solid #555",
            background: isPassed ? "#16a34a" : "transparent",
            color: isPassed ? "#fff" : "transparent",
            cursor: busy ? "not-allowed" : "pointer",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 14,
            fontWeight: 700,
          }}
        >
          {isPassed ? "✓" : ""}
        </button>

        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: "flex", alignItems: "flex-start", gap: 8, flexWrap: "wrap" }}>
            <span
              style={{
                fontWeight: 500,
                lineHeight: 1.4,
                textDecoration: isPassed ? "line-through" : "none",
                color: isFailed ? "#ff6b6b" : "#e8e8e8",
              }}
            >
              {test.title}
            </span>
            <span style={{ fontSize: 10, color: "#555" }}>
              {test.milestone ?? "—"} · {authorLabel(test.addedBy)}
            </span>
            {isFailed && (
              <span
                style={{
                  fontSize: 10,
                  fontWeight: 700,
                  color: "#ff6b6b",
                  background: "#ff444422",
                  padding: "1px 6px",
                  borderRadius: 4,
                }}
              >
                Failed
              </span>
            )}
            {isPassed && test.verifiedAt && (
              <span style={{ fontSize: 10, color: "#16a34a" }}>✓ {test.verifiedAt}</span>
            )}
          </div>

          {test.relatedTasks && test.relatedTasks.length > 0 && (
            <div style={{ display: "flex", gap: 4, flexWrap: "wrap", marginTop: 6 }}>
              {test.relatedTasks.map((id) => (
                <span
                  key={id}
                  style={{
                    fontSize: 10,
                    color: "#666",
                    background: "#1a1a1a",
                    border: "1px solid #2a2a2a",
                    borderRadius: 3,
                    padding: "1px 6px",
                  }}
                >
                  {id}
                </span>
              ))}
            </div>
          )}

          <button
            type="button"
            onClick={() => setExpanded((e) => !e)}
            style={{
              marginTop: 8,
              background: "none",
              border: "none",
              color: "#666",
              fontSize: 11,
              cursor: "pointer",
              padding: 0,
            }}
          >
            {expanded ? "Hide steps" : `Show steps (${test.steps.length})`}
          </button>

          {expanded && (
            <ol
              style={{
                margin: "8px 0 0",
                paddingLeft: 18,
                color: "#aaa",
                fontSize: 12,
                lineHeight: 1.6,
              }}
            >
              {test.steps.map((step, i) => (
                <li key={i}>{step}</li>
              ))}
            </ol>
          )}

          {needsSecret && (
            <div style={{ marginTop: 10, display: "flex", gap: 8, alignItems: "center" }}>
              <input
                type="password"
                value={secretInput}
                onChange={(e) => setSecretInput(e.target.value)}
                placeholder="Dashboard PIN"
                style={{
                  padding: "6px 10px",
                  borderRadius: 5,
                  border: "1px solid #333",
                  background: "#0e0e0e",
                  color: "#e8e8e8",
                  fontSize: 12,
                  flex: 1,
                  maxWidth: 180,
                }}
              />
            </div>
          )}

          {error && <p style={{ color: "#ff6b6b", fontSize: 11, marginTop: 8 }}>{error}</p>}
        </div>

        <div style={{ display: "flex", flexDirection: "column", gap: 4, flexShrink: 0 }}>
          {!isPassed && (
            <button
              type="button"
              disabled={busy}
              onClick={() => void setStatus("passed")}
              style={{
                padding: "4px 10px",
                fontSize: 11,
                fontWeight: 600,
                borderRadius: 4,
                border: "1px solid #16a34a55",
                background: "#16a34a18",
                color: "#16a34a",
                cursor: busy ? "not-allowed" : "pointer",
              }}
            >
              Pass
            </button>
          )}
          {!isFailed && test.status !== "passed" && (
            <button
              type="button"
              disabled={busy}
              onClick={() => void setStatus("failed")}
              style={{
                padding: "4px 10px",
                fontSize: 11,
                fontWeight: 600,
                borderRadius: 4,
                border: "1px solid #ff444455",
                background: "#ff444411",
                color: "#ff6b6b",
                cursor: busy ? "not-allowed" : "pointer",
              }}
            >
              Fail
            </button>
          )}
          {(isPassed || isFailed) && (
            <button
              type="button"
              disabled={busy}
              onClick={() => void setStatus("pending")}
              style={{
                padding: "4px 10px",
                fontSize: 11,
                borderRadius: 4,
                border: "1px solid #333",
                background: "transparent",
                color: "#666",
                cursor: busy ? "not-allowed" : "pointer",
              }}
            >
              Reset
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

export default function ManualTestPanel({
  tests,
  onUpdate,
}: {
  tests: ManualTest[];
  onUpdate: () => void;
}) {
  const [showPassed, setShowPassed] = useState(false);

  if (tests.length === 0) {
    return (
      <div
        id="manual-qa"
        style={{
          marginBottom: 32,
          padding: "16px 18px",
          background: "#121218",
          border: "1px dashed #333",
          borderRadius: 10,
        }}
      >
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 6 }}>
          <span style={{ fontSize: 18 }}>📱</span>
          <h2 style={{ fontSize: 17, fontWeight: 800, color: "#e8e8e8", margin: 0 }}>
            Manual QA — Xcode
          </h2>
        </div>
        <p style={{ color: "#888", fontSize: 12, margin: 0, lineHeight: 1.5 }}>
          No checklist items yet. Agents add entries to{" "}
          <code style={{ color: "#aaa" }}>tasks.json → manualTests[]</code> — they appear here
          automatically after the next refresh.
        </p>
      </div>
    );
  }

  const pending = tests.filter((t) => t.status === "pending");
  const passed = tests.filter((t) => t.status === "passed");
  const failed = tests.filter((t) => t.status === "failed");
  const pct = tests.length > 0 ? Math.round((passed.length / tests.length) * 100) : 0;

  return (
    <div
      id="manual-qa"
      style={{
        marginBottom: 32,
        padding: "16px 18px",
        background: "#121218",
        border: "1px solid #0ea5e933",
        borderRadius: 10,
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 6 }}>
        <span style={{ fontSize: 18 }}>📱</span>
        <h2 style={{ fontSize: 17, fontWeight: 800, color: "#e8e8e8" }}>Manual QA — Xcode</h2>
        <span style={{ fontSize: 12, color: "#0ea5e9", fontWeight: 600 }}>
          {passed.length}/{tests.length} passed
        </span>
      </div>
      <p style={{ color: "#888", fontSize: 12, marginBottom: 14, lineHeight: 1.5 }}>
        Run these in Xcode or the simulator. Check off when confirmed — Claude and Cursor add items
        to <code style={{ color: "#aaa" }}>tasks.json → manualTests[]</code>.
      </p>

      <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 16 }}>
        <div style={{ flex: 1, height: 5, background: "#242424", borderRadius: 3, overflow: "hidden" }}>
          <div
            style={{
              height: "100%",
              width: `${pct}%`,
              background: "#16a34a",
              transition: "width 0.4s",
            }}
          />
        </div>
        <span style={{ fontSize: 11, color: "#16a34a", fontWeight: 700 }}>{pct}%</span>
      </div>

      {failed.length > 0 && (
        <div style={{ marginBottom: 12 }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: "#ff6b6b", marginBottom: 8 }}>
            Failed ({failed.length})
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {failed.map((t) => (
              <TestRow key={t.id} test={t} onUpdate={onUpdate} />
            ))}
          </div>
        </div>
      )}

      {pending.length > 0 && (
        <div style={{ marginBottom: passed.length > 0 && !showPassed ? 0 : 12 }}>
          <div style={{ fontSize: 11, fontWeight: 700, color: "#d97706", marginBottom: 8 }}>
            To test ({pending.length})
          </div>
          <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
            {pending.map((t) => (
              <TestRow key={t.id} test={t} onUpdate={onUpdate} />
            ))}
          </div>
        </div>
      )}

      {passed.length > 0 && (
        <div style={{ marginTop: 12 }}>
          <button
            type="button"
            onClick={() => setShowPassed((s) => !s)}
            style={{
              background: "none",
              border: "none",
              color: "#666",
              fontSize: 12,
              cursor: "pointer",
              padding: 0,
              marginBottom: showPassed ? 8 : 0,
            }}
          >
            {showPassed ? "▲ Hide passed" : `▼ Show passed (${passed.length})`}
          </button>
          {showPassed && (
            <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
              {passed.map((t) => (
                <TestRow key={t.id} test={t} onUpdate={onUpdate} />
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
