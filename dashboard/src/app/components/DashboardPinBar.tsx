"use client";

import { useCallback, useEffect, useState } from "react";
import {
  clearStoredDashboardSecret,
  getStoredDashboardSecret,
  setStoredDashboardSecret,
} from "@/lib/dashboardAuth";

export default function DashboardPinBar() {
  const [pinRequired, setPinRequired] = useState(false);
  const [input, setInput] = useState("");
  const [saved, setSaved] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    void fetch("/api/dashboard/status", { cache: "no-store" })
      .then((res) => res.json())
      .then((json: { pinRequired?: boolean }) => {
        setPinRequired(Boolean(json.pinRequired));
        setSaved(Boolean(getStoredDashboardSecret()));
      })
      .catch(() => setPinRequired(false));
  }, []);

  const savePin = useCallback(() => {
    const trimmed = input.trim();
    if (!trimmed) {
      setMessage("Enter your dashboard PIN first.");
      return;
    }
    setStoredDashboardSecret(trimmed);
    setSaved(true);
    setInput("");
    setMessage("PIN saved for this browser session.");
  }, [input]);

  const clearPin = useCallback(() => {
    clearStoredDashboardSecret();
    setSaved(false);
    setMessage("PIN cleared — enter it again before saving QA or decisions.");
  }, []);

  if (!pinRequired) return null;

  return (
    <div
      style={{
        marginBottom: 16,
        padding: "12px 14px",
        borderRadius: 8,
        border: "1px solid #d9770644",
        background: "#161310",
        display: "flex",
        flexWrap: "wrap",
        gap: 10,
        alignItems: "center",
      }}
    >
      <div style={{ flex: "1 1 220px", minWidth: 0 }}>
        <p style={{ margin: 0, fontSize: 12, fontWeight: 700, color: "#d97706" }}>
          Dashboard PIN {saved ? "· saved this session" : "· required for reads and writes"}
        </p>
        <p style={{ margin: "4px 0 0", fontSize: 11, color: "#888", lineHeight: 1.45 }}>
          Must match <code style={{ color: "#aaa" }}>DECISIONS_SECRET</code> on Vercel (Production).
          Enter once here, then browse, pass QA, decide, or reply.
        </p>
      </div>
      <input
        type="password"
        value={input}
        onChange={(e) => {
          setInput(e.target.value);
          setMessage(null);
        }}
        onKeyDown={(e) => {
          if (e.key === "Enter") savePin();
        }}
        placeholder={saved ? "Replace PIN…" : "Dashboard PIN"}
        autoComplete="off"
        style={{
          padding: "8px 12px",
          borderRadius: 6,
          border: "1px solid #333",
          background: "#0e0e0e",
          color: "#e8e8e8",
          fontSize: 13,
          width: 160,
        }}
      />
      <button
        type="button"
        onClick={savePin}
        style={{
          padding: "8px 14px",
          borderRadius: 6,
          border: "none",
          background: "#d97706",
          color: "#111",
          fontWeight: 700,
          fontSize: 12,
          cursor: "pointer",
        }}
      >
        Save PIN
      </button>
      {saved && (
        <button
          type="button"
          onClick={clearPin}
          style={{
            padding: "8px 10px",
            borderRadius: 6,
            border: "1px solid #333",
            background: "transparent",
            color: "#888",
            fontSize: 12,
            cursor: "pointer",
          }}
        >
          Clear
        </button>
      )}
      {message && (
        <span style={{ width: "100%", fontSize: 11, color: saved ? "#16a34a" : "#ff6b6b" }}>
          {message}
        </span>
      )}
    </div>
  );
}
