import { test } from "node:test";
import assert from "node:assert/strict";
import {
  applySentPush,
  nextNightlyRefreshPlan,
  nextPushPlan
} from "./index.js";

test("nightly refresh retries hourly until success is reported", () => {
  const registration = {};
  const seven = {date: "2026-10-11", previousDate: "2026-10-10", hour: 19, minute: 0, minuteOfDay: 1140};
  const initial = nextPushPlan(registration, seven);
  assert.equal(initial.kind, "nightly");
  assert.equal(initial.payload.retryAttempt, 0);
  applySentPush(registration, seven, initial);

  for (const [hour, retryAttempt] of [[20, 1], [21, 2], [22, 3], [23, 4]]) {
    const plan = nextNightlyRefreshPlan(registration, {
      date: "2026-10-11",
      previousDate: "2026-10-10",
      hour,
      minute: 0,
      minuteOfDay: hour * 60
    });
    assert.equal(plan.payload.refreshDate, "2026-10-11");
    assert.equal(plan.payload.retryAttempt, retryAttempt);
    applySentPush(registration, {date: "2026-10-11", previousDate: "2026-10-10", hour}, plan);
  }

  for (const [hour, retryAttempt] of [[0, 5], [1, 6], [2, 7]]) {
    const plan = nextNightlyRefreshPlan(registration, {
      date: "2026-10-12",
      previousDate: "2026-10-11",
      hour,
      minute: 0,
      minuteOfDay: hour * 60
    });
    assert.equal(plan.payload.refreshDate, "2026-10-11");
    assert.equal(plan.payload.retryAttempt, retryAttempt);
    applySentPush(registration, {date: "2026-10-12", previousDate: "2026-10-11", hour}, plan);
  }

  assert.equal(nextNightlyRefreshPlan(registration, {
    date: "2026-10-12",
    previousDate: "2026-10-11",
    hour: 3,
    minute: 0,
    minuteOfDay: 180
  }), null);
});

test("nightly refresh stops after success result", () => {
  const registration = {
    nightlyRefreshLocalDate: "2026-10-11",
    nightlyRefreshHoursSent: [19],
    nightlyRefreshCompletedLocalDate: "2026-10-11"
  };
  const plan = nextNightlyRefreshPlan(registration, {
    date: "2026-10-11",
    previousDate: "2026-10-10",
    hour: 20,
    minute: 0,
    minuteOfDay: 1200
  });
  assert.equal(plan, null);
});

test("nightly refresh does not resend same retry hour", () => {
  const registration = {
    nightlyRefreshLocalDate: "2026-10-11",
    nightlyRefreshHoursSent: [19, 20]
  };
  const plan = nextNightlyRefreshPlan(registration, {
    date: "2026-10-11",
    previousDate: "2026-10-10",
    hour: 20,
    minute: 0,
    minuteOfDay: 1200
  });
  assert.equal(plan, null);
});
