import { NextResponse } from "next/server";
import { readTasksFile, resolveDecision, writeTasksFile } from "@/lib/tasksFile";

export const dynamic = "force-dynamic";

interface ResolveBody {
  decisionId: string;
  optionId: string;
  secret?: string;
}

function checkSecret(request: Request, body: ResolveBody): boolean {
  const expected = process.env.DECISIONS_SECRET;
  if (!expected) return true;
  const provided =
    request.headers.get("x-decisions-secret") ??
    body.secret ??
    "";
  return provided === expected;
}

export async function POST(request: Request) {
  let body: ResolveBody;
  try {
    body = (await request.json()) as ResolveBody;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!body.decisionId || !body.optionId) {
    return NextResponse.json({ error: "decisionId and optionId are required" }, { status: 400 });
  }

  if (!checkSecret(request, body)) {
    return NextResponse.json({ error: "Invalid decision secret" }, { status: 401 });
  }

  try {
    const current = await readTasksFile();
    const { data, decision } = resolveDecision(current, body.decisionId, body.optionId);
    await writeTasksFile(
      data,
      `dashboard: decide ${body.decisionId} → ${body.optionId}`
    );
    return NextResponse.json({ ok: true, decision, meta: data.meta });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to resolve decision";
    const status = message.includes("not found") || message.includes("Invalid option") ? 400 : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
