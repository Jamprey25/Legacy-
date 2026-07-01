import { NextResponse } from "next/server";
import {
  isValidThreadAuthor,
  replyTextTooLarge,
} from "@/lib/dashboardAuth";
import { authorizeDashboardWrite } from "@/lib/dashboardWriteGuard";
import { readTasksFile, addResponse, resolveDiscussion, writeTasksFile } from "@/lib/tasksFile";
import type { ThreadResponse } from "@/app/types";

export const dynamic = "force-dynamic";

interface RespondBody {
  itemId: string;
  author: string;
  text: string;
  resolve?: boolean;
  secret?: string;
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

  if (!isValidThreadAuthor(body.author)) {
    return NextResponse.json({ error: "Invalid author" }, { status: 400 });
  }

  if (replyTextTooLarge(body.text)) {
    return NextResponse.json({ error: "Reply text too large" }, { status: 413 });
  }

  const auth = authorizeDashboardWrite(request as import("next/server").NextRequest, body.secret);
  if (!auth.ok) {
    return NextResponse.json(
      { error: auth.error, retry_after_s: auth.retryAfterS },
      { status: auth.status },
    );
  }

  try {
    const { data: current, sha } = await readTasksFile();

    const response: ThreadResponse = {
      author: body.author,
      text: body.text,
      date: new Date().toISOString().slice(0, 10),
    };

    let { data, decision } = addResponse(current, body.itemId, response);

    if (body.resolve) {
      ({ data, decision } = resolveDiscussion(data, body.itemId));
    }

    await writeTasksFile(data, `dashboard: ${body.author} replied to ${body.itemId}`, sha);
    return NextResponse.json({ ok: true, decision });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Failed to save response";
    const status = message.includes("not found") ? 400 : 500;
    return NextResponse.json({ error: message }, { status });
  }
}
