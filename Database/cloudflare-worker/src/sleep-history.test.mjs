import { test } from "node:test";
import assert from "node:assert/strict";
import { fetchSleepHistory } from "./sleep-history.mjs";

for (const provider of ["whoop", "oura"]) {
  test(`${provider} imports all pages within eight weeks`, async () => {
    const now = new Date("2026-10-05T12:00:00Z");
    const cutoff = new Date(now.getTime() - 56 * 86400000).toISOString();
    const key = provider === "whoop" ? "records" : "data";
    const record = wake => ({ [provider === "whoop" ? "end" : "bedtime_end"]: wake });
    const urls = [];
    const records = await fetchSleepHistory("https://example.com/sleep", async url => {
      urls.push(new URL(url));
      return urls.length === 1
        ? { [key]: [record(cutoff)], next_token: "page two" }
        : { [key]: [record("2026-10-04T07:00:00Z"), record("2026-01-01T07:00:00Z"), record("2027-01-01T07:00:00Z")] };
    }, provider, now);
    assert.equal(records.length, 2);
    assert.equal(urls[1].searchParams.get("next_token"), "page two");
    assert.equal(urls[0].searchParams.get(provider === "whoop" ? "start" : "start_date"), provider === "whoop" ? cutoff : cutoff.slice(0, 10));
    assert.deepEqual(records[0], record("2026-10-04T07:00:00Z"));
  });
  test(`${provider} accepts empty or shorter history`, async () => {
    const key = provider === "whoop" ? "records" : "data";
    assert.deepEqual(await fetchSleepHistory("https://example.com/sleep", async () => ({ [key]: [] }), provider), []);
  });
}

test("repeated pagination tokens fail instead of looping", async () => {
  await assert.rejects(fetchSleepHistory("https://example.com/sleep", async () => ({ records: [], next_token: "same" }), "whoop"), /Repeated/);
});
