import { NextResponse } from "next/server";
import { readTasksFile, addResponse, resolveDiscussion, writeTasksFile } from "@/lib/tasksFile";
import type { ThreadResponse } from "@/app/types";

export const dynamic = "force-dynamic";

interface RespondBody {
  itemId: string;
  author: string;
  text: string;
  resolve?: boolean;  // optionally mark the thread resolved
  secret?: string;
}

function checkSecret(request: Request, body: RespondBody): boolean {
  const expected = process.env.DECISIONS_SECRET;
  if (!expected) return true;
  const provided = request.headers.get("x-decisions-secret") ?? body.secret ?? "";
  return provided === expected;
}

export async function POST(request: Request) {
  let body: RespondBody;
  try {
    body = (await request.json()) as RespondBody;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  if (!body.itemId || !body.author || !body.text) {
    return NextResponse.json({ error: "itemId, author, and text are required" }, { status: 400 });
  }

  if (!checkSecret(request, body)) {
    return NextResponse.json({ error: "Invalid secret" }, { status: 401 });
  }

  try {
    const current = await readTasksFile();

    const response: ThreadResponse = {
      author: body.author as ThreadResponse["author"],
      text: body.text,
      date: new Date().toISOString().slice(0, 10),
    };

    let { data, decision } = addResponse(current, body.itemId, response);

    if (body.resolve) {
      ({ data, decision } = resolveDiscussion(data, body.itemId));
    }

    await writeTasksFile(data, `dashboard: ${body.author} replied to ${body.itemId}`);
    return NextResponse.json({ ok: true, decision });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to save response";
    const status = message.includes("not found") ? 400 : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
