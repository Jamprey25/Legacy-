import { readTasksFile } from "@/lib/tasksFile";
import type { TasksFile } from "./types";
import DashboardClient from "./DashboardClient";

// ISR: regenerate at most once every 30 seconds so Vercel serves cached HTML
// immediately — no loading spinner on first paint.
export const revalidate = 30;

export default async function Page() {
  let initialData: TasksFile | null = null;
  try {
    const { data } = await readTasksFile();
    initialData = data;
  } catch {
    // DashboardClient handles null — will show error state after client fetch
  }
  return <DashboardClient initialData={initialData} />;
}
