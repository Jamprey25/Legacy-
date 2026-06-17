import fs from "fs/promises";
import path from "path";
import type { Decision, TasksFile, ThreadResponse } from "../app/types";

const GITHUB_REPO = process.env.GITHUB_REPO ?? "Jamprey25/Legacy-";
const GITHUB_BRANCH = process.env.GITHUB_BRANCH ?? "main";
const TASKS_FILE = "tasks.json";

function tasksFilePath(): string {
  return process.env.TASKS_FILE_PATH ?? path.join(process.cwd(), "..", TASKS_FILE);
}

function githubHeaders(): HeadersInit {
  const token = process.env.GITHUB_TOKEN;
  if (!token) throw new Error("GITHUB_TOKEN is not configured");
  return {
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  };
}

async function readFromGitHub(): Promise<{ data: TasksFile; sha: string }> {
  const url = `https://api.github.com/repos/${GITHUB_REPO}/contents/${TASKS_FILE}?ref=${GITHUB_BRANCH}`;
  const res = await fetch(url, { headers: githubHeaders(), cache: "no-store" });
  if (!res.ok) throw new Error(`GitHub read failed: ${res.status}`);
  const json = (await res.json()) as { content: string; sha: string };
  const raw = Buffer.from(json.content, "base64").toString("utf-8");
  return { data: JSON.parse(raw) as TasksFile, sha: json.sha };
}

async function readFromDisk(): Promise<TasksFile> {
  const raw = await fs.readFile(tasksFilePath(), "utf-8");
  return JSON.parse(raw) as TasksFile;
}

export async function readTasksFile(): Promise<TasksFile> {
  if (process.env.GITHUB_TOKEN) return (await readFromGitHub()).data;
  return readFromDisk();
}

async function writeToGitHub(data: TasksFile, message: string): Promise<void> {
  const { sha } = await readFromGitHub();
  const content = Buffer.from(JSON.stringify(data, null, 2) + "\n").toString("base64");
  const url = `https://api.github.com/repos/${GITHUB_REPO}/contents/${TASKS_FILE}`;
  const res = await fetch(url, {
    method: "PUT",
    headers: { ...githubHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify({ message, content, sha, branch: GITHUB_BRANCH }),
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`GitHub write failed: ${res.status} ${err}`);
  }
}

async function writeToDisk(data: TasksFile): Promise<void> {
  await fs.writeFile(tasksFilePath(), JSON.stringify(data, null, 2) + "\n", "utf-8");
}

export async function writeTasksFile(data: TasksFile, message: string): Promise<void> {
  data.meta.lastUpdated = new Date().toISOString();
  if (process.env.GITHUB_TOKEN) {
    await writeToGitHub(data, message);
  } else {
    await writeToDisk(data);
  }
}

export function addResponse(
  data: TasksFile,
  itemId: string,
  response: ThreadResponse
): { data: TasksFile; decision: Decision } {
  const decisions = data.decisions ?? [];
  const index = decisions.findIndex((d) => d.id === itemId);
  if (index === -1) throw new Error(`Item not found: ${itemId}`);

  const current = decisions[index];
  const updated: Decision = {
    ...current,
    responses: [...(current.responses ?? []), response],
  };

  const next = { ...data, decisions: [...decisions] };
  next.decisions![index] = updated;
  return { data: next, decision: updated };
}

export function resolveDiscussion(
  data: TasksFile,
  itemId: string
): { data: TasksFile; decision: Decision } {
  const decisions = data.decisions ?? [];
  const index = decisions.findIndex((d) => d.id === itemId);
  if (index === -1) throw new Error(`Item not found: ${itemId}`);

  const current = decisions[index];
  const updated: Decision = { ...current, status: "resolved" };
  const next = { ...data, decisions: [...decisions] };
  next.decisions![index] = updated;
  return { data: next, decision: updated };
}

export function resolveDecision(
  data: TasksFile,
  decisionId: string,
  optionId: string
): { data: TasksFile; decision: Decision } {
  const decisions = data.decisions ?? [];
  const index = decisions.findIndex((d) => d.id === decisionId);
  if (index === -1) throw new Error(`Decision not found: ${decisionId}`);

  const current = decisions[index];
  if (current.status !== "open") throw new Error(`Decision already closed: ${decisionId}`);

  const option = current.options?.find((o) => o.id === optionId);
  if (!option) throw new Error(`Invalid option: ${optionId}`);

  const decidedAt = new Date().toISOString().slice(0, 10);
  const decision: Decision = {
    ...current,
    status: "decided",
    chosenOptionId: optionId,
    decidedAt,
    resolution: `${option.label}. Decided by Joseph ${decidedAt}. ${option.description ?? ""}`.trim(),
  };

  const next = { ...data, decisions: [...decisions] };
  next.decisions![index] = decision;
  return { data: next, decision };
}
