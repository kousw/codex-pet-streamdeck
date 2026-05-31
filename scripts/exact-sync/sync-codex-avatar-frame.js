#!/usr/bin/env node

const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const port = Number(process.argv[2] || process.env.CODEX_REMOTE_DEBUGGING_PORT || 9222);
const intervalMs = Number(process.env.CODEX_AVATAR_SYNC_MS || 100);
const statePath = path.join(os.homedir(), ".codex", "pet-streamdeck-state.json");

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function readJSON(url) {
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`${url} returned ${response.status}`);
  }
  return response.json();
}

async function connectOverlayTarget() {
  const targets = await readJSON(`http://127.0.0.1:${port}/json/list`);
  const target = targets.find((entry) => entry.url.includes("avatar-overlay"));
  if (!target) {
    throw new Error("Codex avatar overlay DevTools target was not found.");
  }

  const socket = new WebSocket(target.webSocketDebuggerUrl);
  const pending = new Map();
  let nextID = 1;

  socket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    const resolve = pending.get(message.id);
    if (resolve) {
      pending.delete(message.id);
      resolve(message);
    }
  };

  await new Promise((resolve, reject) => {
    socket.onopen = resolve;
    socket.onerror = reject;
  });

  function send(method, params = {}) {
    const id = nextID++;
    socket.send(JSON.stringify({ id, method, params }));
    return new Promise((resolve) => pending.set(id, resolve));
  }

  await send("Runtime.enable");
  return { socket, send };
}

function stateForRow(row) {
  if (row === 5) return "failed";
  if (row === 6) return "waiting";
  if (row === 7) return "running";
  if (row === 8) return "review";
  return "idle";
}

function readExistingState() {
  try {
    return JSON.parse(fs.readFileSync(statePath, "utf8"));
  } catch {
    return {};
  }
}

function writeState(update) {
  fs.mkdirSync(path.dirname(statePath), { recursive: true });
  const existing = readExistingState();
  const next = {
    ...existing,
    ...update,
    source: "codex-debug-overlay",
    updatedAt: new Date().toISOString(),
  };
  const tmp = `${statePath}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmp, `${JSON.stringify(next, null, 2)}\n`);
  fs.renameSync(tmp, statePath);
}

const expression = `(() => {
  const el = document.querySelector('.codex-avatar-root');
  if (!el) return { found: false };
  const style = getComputedStyle(el);
  const [xRaw, yRaw] = style.backgroundPosition.split(' ');
  const x = parseFloat(xRaw);
  const y = parseFloat(yRaw);
  const badge = Array.from(document.querySelectorAll('button[aria-label]'))
    .map((button) => {
      const label = button.getAttribute('aria-label') || '';
      const match = label.match(/^Open activity tray,\\s*(\\d+)\\s+items?$/);
      return match ? Number(match[1]) : null;
    })
    .find((count) => Number.isInteger(count));
  return {
    found: true,
    backgroundPosition: style.backgroundPosition,
    spriteColumn: Number.isFinite(x) ? Math.round(x / (100 / 7)) : null,
    spriteRow: Number.isFinite(y) ? Math.round(y / (100 / 8)) : null,
    notificationBadgeCount: badge ?? null,
  };
})()`;

async function syncOnce() {
  const { socket, send } = await connectOverlayTarget();
  console.log(`Syncing Codex avatar frame from DevTools port ${port} to ${statePath}`);

  process.on("SIGINT", () => {
    socket.close();
    process.exit(0);
  });

  while (true) {
    const response = await send("Runtime.evaluate", {
      expression,
      returnByValue: true,
    });
    const value = response?.result?.result?.value;
    if (
      value?.found &&
      Number.isInteger(value.spriteRow) &&
      Number.isInteger(value.spriteColumn)
    ) {
      writeState({
        state: stateForRow(value.spriteRow),
        spriteRow: value.spriteRow,
        spriteColumn: value.spriteColumn,
        notificationBadgeCount: value.notificationBadgeCount,
        backgroundPosition: value.backgroundPosition,
      });
      console.log(
        `state=${stateForRow(value.spriteRow)} row=${value.spriteRow} col=${value.spriteColumn} badge=${value.notificationBadgeCount ?? 0} bg=${value.backgroundPosition}`
      );
    }
    await sleep(intervalMs);
  }
}

async function main() {
  while (true) {
    try {
      await syncOnce();
    } catch (error) {
      console.error(error.message || error);
      await sleep(2000);
    }
  }
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});
