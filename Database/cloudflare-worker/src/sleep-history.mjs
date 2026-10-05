export const sleepHistoryDays = 56;

export async function fetchSleepHistory(endpoint, get, provider, now = new Date()) {
  const cutoff = new Date(now.getTime() - sleepHistoryDays * 86400000);
  const url = new URL(endpoint);
  if (provider === "whoop") {
    url.searchParams.set("start", cutoff.toISOString());
    url.searchParams.set("end", now.toISOString());
    url.searchParams.set("limit", "25");
  } else {
    url.searchParams.set("start_date", cutoff.toISOString().slice(0, 10));
    url.searchParams.set("end_date", now.toISOString().slice(0, 10));
  }
  const records = [];
  const tokens = new Set();
  while (true) {
    const page = await get(url.toString());
    records.push(...(page[provider === "whoop" ? "records" : "data"] || []));
    if (!page.next_token) break;
    if (tokens.has(page.next_token)) throw new Error("Repeated sleep history pagination token");
    tokens.add(page.next_token);
    url.searchParams.set("next_token", page.next_token);
  }
  return records.filter(record => {
    const wake = Date.parse(provider === "whoop" ? record.end : record.bedtime_end ?? record.end_datetime);
    return wake >= cutoff.getTime() && wake <= now.getTime();
  }).sort((a, b) => Date.parse(provider === "whoop" ? b.end : b.bedtime_end ?? b.end_datetime)
    - Date.parse(provider === "whoop" ? a.end : a.bedtime_end ?? a.end_datetime));
}
