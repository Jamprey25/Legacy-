"use client";

import type { Task } from "../types";

type ArchitecturePanelProps = {
  tasks: Task[];
};

type FlowStep = {
  title: string;
  detail: string;
};

const REPO_WEB_ROOT =
  process.env.NEXT_PUBLIC_REPO_WEB_ROOT ?? "https://github.com/Jamprey25/Legacy-/tree/main";
const DOCS_WEB_ROOT =
  process.env.NEXT_PUBLIC_DOCS_WEB_ROOT ?? "https://github.com/Jamprey25/Legacy-/blob/main";

const IOS_MODULES: Array<{ name: string; deps: string; href: string }> = [
  { name: "DesignSystem", deps: "None", href: `${REPO_WEB_ROOT}/ios/LegacyModules/Sources/DesignSystem` },
  { name: "APIClient", deps: "None", href: `${REPO_WEB_ROOT}/ios/LegacyModules/Sources/APIClient` },
  { name: "LocationEngine", deps: "None", href: `${REPO_WEB_ROOT}/ios/LegacyModules/Sources/LocationEngine` },
  { name: "AuthFeature", deps: "DesignSystem + APIClient", href: `${REPO_WEB_ROOT}/ios/LegacyModules/Sources/AuthFeature` },
  {
    name: "DropFeature",
    deps: "DesignSystem + APIClient + LocationEngine",
    href: `${REPO_WEB_ROOT}/ios/LegacyModules/Sources/DropFeature`,
  },
  {
    name: "WanderFeature",
    deps: "DesignSystem + APIClient + LocationEngine",
    href: `${REPO_WEB_ROOT}/ios/LegacyModules/Sources/WanderFeature`,
  },
  {
    name: "MemoryLaneFeature",
    deps: "DesignSystem + APIClient",
    href: `${REPO_WEB_ROOT}/ios/LegacyModules/Sources/MemoryLaneFeature`,
  },
  {
    name: "ImportFeature",
    deps: "DesignSystem + APIClient + LocationEngine",
    href: `${REPO_WEB_ROOT}/ios/LegacyModules/Sources/ImportFeature`,
  },
];

const DROP_FLOW: FlowStep[] = [
  { title: "Compose", detail: "User picks media or writes note in iOS feature coordinators." },
  { title: "Privacy Prep", detail: "Image metadata is stripped client-side before any upload." },
  { title: "Create Memory", detail: "iOS calls POST /v1/memories with location + memory metadata." },
  { title: "Upload", detail: "Client uploads encrypted media to signed storage URL from backend." },
];

const SCAN_FLOW: FlowStep[] = [
  { title: "Location Fix", detail: "LocationEngine gets a new fix and movement gate decides scan timing." },
  { title: "Proximity Check", detail: "POST /v1/discovery/scan validates distance server-side only." },
  { title: "Warmth Teaser", detail: "Response returns non-directional warmth bands and teaser-safe metadata." },
  { title: "UI Render", detail: "Wander updates warmth overlays without exposing exact coordinates." },
];

const UNLOCK_FLOW: FlowStep[] = [
  { title: "Unlock Attempt", detail: "User taps a teaser and requests POST /v1/memories/:id/unlock." },
  { title: "Dwell + Seal Eval", detail: "Backend enforces dwell checks plus seal and condition rules." },
  { title: "Authorization", detail: "Only eligible unlocks receive signed media URL and find record." },
  { title: "Reveal", detail: "Wander displays unlocked media and ownership-safe details." },
];

function FlowCard({ title, steps, href }: { title: string; steps: FlowStep[]; href: string }) {
  return (
    <div
      style={{
        background: "#121212",
        border: "1px solid #252525",
        borderRadius: 10,
        padding: "14px 16px",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 8, marginBottom: 10 }}>
        <h3 style={{ fontSize: 14, margin: 0, color: "#e8e8e8" }}>{title}</h3>
        <a
          href={href}
          target="_blank"
          rel="noreferrer"
          style={{ color: "#60a5fa", fontSize: 11, textDecoration: "none", fontWeight: 700 }}
        >
          Open docs ↗
        </a>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
        {steps.map((step, idx) => (
          <div key={step.title} style={{ display: "flex", gap: 10, alignItems: "flex-start" }}>
            <div
              style={{
                width: 20,
                height: 20,
                borderRadius: "50%",
                background: "#0ea5e922",
                border: "1px solid #0ea5e955",
                color: "#7dd3fc",
                fontSize: 11,
                fontWeight: 700,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                flexShrink: 0,
              }}
            >
              {idx + 1}
            </div>
            <div>
              <div style={{ fontSize: 12, color: "#d1d5db", fontWeight: 600 }}>{step.title}</div>
              <div style={{ fontSize: 12, color: "#8a8a8a", marginTop: 2 }}>{step.detail}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

export default function TechnicalArchitecturePanel({ tasks }: ArchitecturePanelProps) {
  const iosTotal = tasks.filter((t) => t.owner === "ios").length;
  const backendTotal = tasks.filter((t) => t.owner === "backend").length;
  const doneTotal = tasks.filter((t) => t.status === "done").length;
  const completion = tasks.length > 0 ? Math.round((doneTotal / tasks.length) * 100) : 0;

  return (
    <section
      style={{
        background: "#101010",
        border: "1px solid #222",
        borderRadius: 12,
        padding: "18px 18px 20px",
        marginBottom: 24,
      }}
    >
      <h2 style={{ margin: 0, marginBottom: 6, color: "#f3f4f6", fontSize: 18 }}>Technical Structure Map</h2>
      <p style={{ margin: 0, marginBottom: 16, color: "#9ca3af", fontSize: 13 }}>
        Live architecture view spanning iOS modules, backend API flow, and decision-control docs.
      </p>
      <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginBottom: 16 }}>
        <a
          href={`${DOCS_WEB_ROOT}/docs/engineering/TECHNICAL_INTERNAL.md`}
          target="_blank"
          rel="noreferrer"
          style={{
            color: "#93c5fd",
            textDecoration: "none",
            fontSize: 12,
            border: "1px solid #1e3a8a55",
            borderRadius: 999,
            padding: "4px 10px",
            background: "#1e3a8a22",
          }}
        >
          TECHNICAL_INTERNAL ↗
        </a>
        <a
          href={`${DOCS_WEB_ROOT}/docs/engineering/api-contract.md`}
          target="_blank"
          rel="noreferrer"
          style={{
            color: "#86efac",
            textDecoration: "none",
            fontSize: 12,
            border: "1px solid #16653477",
            borderRadius: 999,
            padding: "4px 10px",
            background: "#14532d22",
          }}
        >
          API Contract ↗
        </a>
        <a
          href={`${DOCS_WEB_ROOT}/docs/engineering/AGENT_WORKFLOW.md`}
          target="_blank"
          rel="noreferrer"
          style={{
            color: "#fdba74",
            textDecoration: "none",
            fontSize: 12,
            border: "1px solid #9a341277",
            borderRadius: 999,
            padding: "4px 10px",
            background: "#7c2d1222",
          }}
        >
          Agent Workflow ↗
        </a>
      </div>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(210px, 1fr))",
          gap: 10,
          marginBottom: 16,
        }}
      >
        <div style={{ background: "#0f172a66", border: "1px solid #1e293b", borderRadius: 8, padding: 12 }}>
          <div style={{ fontSize: 11, color: "#93c5fd", textTransform: "uppercase", letterSpacing: 0.5 }}>Client</div>
          <div style={{ color: "#e2e8f0", marginTop: 4, fontWeight: 700 }}>iOS App (SwiftUI)</div>
          <div style={{ color: "#94a3b8", fontSize: 12, marginTop: 4 }}>Feature coordinators + APIClient + LocationEngine</div>
          <a href={`${REPO_WEB_ROOT}/ios`} target="_blank" rel="noreferrer" style={{ color: "#93c5fd", fontSize: 11, textDecoration: "none" }}>
            Open iOS workspace ↗
          </a>
        </div>
        <div style={{ background: "#052e1626", border: "1px solid #14532d", borderRadius: 8, padding: 12 }}>
          <div style={{ fontSize: 11, color: "#86efac", textTransform: "uppercase", letterSpacing: 0.5 }}>API</div>
          <div style={{ color: "#dcfce7", marginTop: 4, fontWeight: 700 }}>Backend (Node/TypeScript)</div>
          <div style={{ color: "#86efac", fontSize: 12, marginTop: 4 }}>Validation + proximity + seal evaluation</div>
          <a
            href={`${REPO_WEB_ROOT}/backend`}
            target="_blank"
            rel="noreferrer"
            style={{ color: "#86efac", fontSize: 11, textDecoration: "none" }}
          >
            Open backend ↗
          </a>
        </div>
        <div style={{ background: "#2e106533", border: "1px solid #581c87", borderRadius: 8, padding: 12 }}>
          <div style={{ fontSize: 11, color: "#d8b4fe", textTransform: "uppercase", letterSpacing: 0.5 }}>Storage</div>
          <div style={{ color: "#f3e8ff", marginTop: 4, fontWeight: 700 }}>Postgres + Blob/S3</div>
          <div style={{ color: "#d8b4fe", fontSize: 12, marginTop: 4 }}>Memory metadata + signed media uploads</div>
          <a
            href={`${REPO_WEB_ROOT}/backend/migrations`}
            target="_blank"
            rel="noreferrer"
            style={{ color: "#d8b4fe", fontSize: 11, textDecoration: "none" }}
          >
            Open DB migrations ↗
          </a>
        </div>
        <div style={{ background: "#42200644", border: "1px solid #7c2d12", borderRadius: 8, padding: 12 }}>
          <div style={{ fontSize: 11, color: "#fdba74", textTransform: "uppercase", letterSpacing: 0.5 }}>Control Plane</div>
          <div style={{ color: "#ffedd5", marginTop: 4, fontWeight: 700 }}>Dashboard + docs</div>
          <div style={{ color: "#fdba74", fontSize: 12, marginTop: 4 }}>tasks.json + decisions + collab workflow</div>
          <a
            href={`${REPO_WEB_ROOT}/dashboard`}
            target="_blank"
            rel="noreferrer"
            style={{ color: "#fdba74", fontSize: 11, textDecoration: "none" }}
          >
            Open dashboard code ↗
          </a>
        </div>
      </div>

      <div
        style={{
          marginBottom: 16,
          borderRadius: 8,
          border: "1px solid #222",
          padding: "12px 14px",
          background: "#131313",
          fontSize: 12,
          color: "#9ca3af",
        }}
      >
        <span style={{ color: "#e5e7eb", fontWeight: 600 }}>Data direction:</span>{" "}
        iOS → API (`/v1/*`) → Storage for writes, and iOS ← API for scan/unlock responses. Dashboard reads
        `tasks.json` as the operational source of truth.
      </div>

      <h3 style={{ margin: 0, marginBottom: 10, color: "#f3f4f6", fontSize: 15 }}>iOS module dependency graph</h3>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(230px, 1fr))", gap: 8, marginBottom: 16 }}>
        {IOS_MODULES.map((module) => (
          <div key={module.name} style={{ border: "1px solid #242424", borderRadius: 8, padding: 10, background: "#111" }}>
            <div style={{ color: "#e5e7eb", fontWeight: 700, fontSize: 13 }}>{module.name}</div>
            <div style={{ color: "#9ca3af", fontSize: 12, marginTop: 4 }}>Depends on: {module.deps}</div>
            <a href={module.href} target="_blank" rel="noreferrer" style={{ color: "#7dd3fc", fontSize: 11, textDecoration: "none" }}>
              Open module ↗
            </a>
          </div>
        ))}
      </div>

      <h3 style={{ margin: 0, marginBottom: 10, color: "#f3f4f6", fontSize: 15 }}>Core runtime flows</h3>
      <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))", gap: 10, marginBottom: 16 }}>
        <FlowCard title="Drop flow" steps={DROP_FLOW} href={`${DOCS_WEB_ROOT}/docs/engineering/api-contract.md#3-post-v1memories-drop-a-memory-and-get-upload-url`} />
        <FlowCard title="Scan flow" steps={SCAN_FLOW} href={`${DOCS_WEB_ROOT}/docs/engineering/api-contract.md#4-post-v1discoveryscan-scan-nearby-memories`} />
        <FlowCard title="Unlock flow" steps={UNLOCK_FLOW} href={`${DOCS_WEB_ROOT}/docs/engineering/api-contract.md#5-post-v1memoriesidunlock-attempt-unlock`} />
      </div>

      <div
        style={{
          display: "flex",
          gap: 12,
          flexWrap: "wrap",
          background: "#121212",
          border: "1px solid #242424",
          borderRadius: 8,
          padding: "10px 12px",
        }}
      >
        <div style={{ color: "#9ca3af", fontSize: 12 }}>
          <span style={{ color: "#e5e7eb", fontWeight: 700 }}>{completion}%</span> overall task completion
        </div>
        <div style={{ color: "#9ca3af", fontSize: 12 }}>
          <span style={{ color: "#7dd3fc", fontWeight: 700 }}>{iosTotal}</span> iOS-owned tasks
        </div>
        <div style={{ color: "#9ca3af", fontSize: 12 }}>
          <span style={{ color: "#a5b4fc", fontWeight: 700 }}>{backendTotal}</span> backend-owned tasks
        </div>
      </div>
    </section>
  );
}
