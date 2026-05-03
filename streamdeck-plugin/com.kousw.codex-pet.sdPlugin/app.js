const ACTION_UUID = 'com.kousw.codex-pet.live';
const FRAME_DATA_URL_PATH = 'frames/latest-data-url.txt';
const FRAME_STATUS_PATH = 'frames/status.json';
const DEFAULT_REFRESH_MS = 1000;
const MIN_REFRESH_MS = 67;
const MAX_REFRESH_MS = 1000;
const STATUS_REFRESH_MS = 1000;

let websocket = null;
let pluginUUID = null;
let timer = null;
let timerWorker = null;
let frameSendCount = 0;
let isLoopRunning = false;
let currentRefreshMs = DEFAULT_REFRESH_MS;
let lastStatusReadAt = 0;
const visibleContexts = new Set();
const lastImageByContext = new Map();

function connectElgatoStreamDeckSocket(port, uuid, registerEvent, info, actionInfo) {
  pluginUUID = uuid;
  websocket = new WebSocket(`ws://127.0.0.1:${port}`);

  websocket.onopen = () => {
    websocket.send(JSON.stringify({ event: registerEvent, uuid }));
    log('Codex Pet plugin connected');
  };

  websocket.onmessage = (event) => {
    const message = JSON.parse(event.data);
    handleMessage(message);
  };

  websocket.onerror = (event) => {
    console.warn('Codex Pet websocket error', event);
  };

  websocket.onclose = () => {
    stopTimer();
  };
}

function handleMessage(message) {
  if (message.action !== ACTION_UUID) {
    return;
  }

  if (message.event === 'willAppear') {
    visibleContexts.add(message.context);
    sendTitle(message.context, '');
    sendFrame(message.context);
    startTimer();
  }

  if (message.event === 'willDisappear') {
    visibleContexts.delete(message.context);
    lastImageByContext.delete(message.context);
    if (visibleContexts.size === 0) {
      stopTimer();
    }
  }

  if (message.event === 'keyUp') {
    openCodex();
    sendFrame(message.context);
  }
}

function openCodex() {
  if (!websocket || websocket.readyState !== WebSocket.OPEN) {
    return;
  }

  websocket.send(JSON.stringify({
    event: 'openUrl',
    payload: {
      url: 'codex://'
    }
  }));
  log('Requested Codex foreground via codex://');
}

function startTimer() {
  if (isLoopRunning) {
    return;
  }

  isLoopRunning = true;
  startWorkerTimer();
}

function stopTimer() {
  stopWorkerTimer();
  if (timer !== null) {
    window.clearTimeout(timer);
    timer = null;
  }
  isLoopRunning = false;
}

function startWorkerTimer() {
  if (timerWorker !== null) {
    return;
  }

  try {
    const workerSource = `
      let interval = ${DEFAULT_REFRESH_MS};
      let timer = null;

      function tick() {
        self.postMessage({ type: 'tick' });
      }

      self.onmessage = (event) => {
        if (!event.data) return;
        if (event.data.type === 'start') {
          interval = event.data.interval || interval;
          if (timer !== null) clearInterval(timer);
          tick();
          timer = setInterval(tick, interval);
        }
        if (event.data.type === 'stop') {
          if (timer !== null) clearInterval(timer);
          timer = null;
        }
      };
    `;
    const workerURL = URL.createObjectURL(new Blob([workerSource], { type: 'application/javascript' }));
    timerWorker = new Worker(workerURL);
    URL.revokeObjectURL(workerURL);
    timerWorker.onmessage = (event) => {
      if (event.data && event.data.type === 'tick') {
        sendFramesForVisibleContexts();
      }
    };
    timerWorker.onerror = (error) => {
      log(`Worker timer failed, falling back: ${error.message || error}`);
      stopWorkerTimer();
      scheduleNextFrame(0);
    };
    timerWorker.postMessage({ type: 'start', interval: currentRefreshMs });
    log('Codex Pet worker timer started');
  } catch (error) {
    log(`Unable to start worker timer, falling back: ${error}`);
    scheduleNextFrame(0);
  }
}

function stopWorkerTimer() {
  if (timerWorker === null) {
    return;
  }

  try {
    timerWorker.postMessage({ type: 'stop' });
    timerWorker.terminate();
  } finally {
    timerWorker = null;
  }
}

function scheduleNextFrame(delay) {
  timer = window.setTimeout(() => {
    timer = null;

    if (!isLoopRunning || visibleContexts.size === 0) {
      isLoopRunning = false;
      return;
    }

    sendFramesForVisibleContexts();

    scheduleNextFrame(currentRefreshMs);
  }, delay);
}

function sendFramesForVisibleContexts() {
  if (!isLoopRunning || visibleContexts.size === 0) {
    return;
  }

  for (const context of visibleContexts) {
    sendFrame(context);
  }
}

function sendFrame(context) {
  if (!websocket || websocket.readyState !== WebSocket.OPEN || !context) {
    return;
  }

  refreshFrameStatusIfNeeded();

  readText(`${FRAME_DATA_URL_PATH}?t=${Date.now()}`, (image) => {
    if (!image || !image.startsWith('data:image/png;base64,')) {
      log('Codex pet frame data URL is missing or invalid');
      return;
    }

    if (lastImageByContext.get(context) === image) {
      return;
    }

    websocket.send(JSON.stringify({
      event: 'setImage',
      context,
      payload: {
        image,
        target: 0
      }
    }));

    frameSendCount += 1;
    lastImageByContext.set(context, image);
    if (frameSendCount % 10 === 1) {
      log(`Sent Codex pet frame ${frameSendCount}`);
    }
  });
}

function refreshFrameStatusIfNeeded() {
  const now = Date.now();
  if (now - lastStatusReadAt < STATUS_REFRESH_MS) {
    return;
  }

  lastStatusReadAt = now;
  readText(`${FRAME_STATUS_PATH}?t=${now}`, (statusText) => {
    try {
      const status = JSON.parse(statusText);
      updateRefreshInterval(refreshMsForFPS(status.captureFPS));
    } catch (error) {
      log(`Failed to parse Codex pet status: ${error}`);
    }
  }, 'status');
}

function refreshMsForFPS(fps) {
  const numericFPS = Number(fps);
  if (!Number.isFinite(numericFPS) || numericFPS <= 0) {
    return DEFAULT_REFRESH_MS;
  }

  return Math.max(MIN_REFRESH_MS, Math.min(MAX_REFRESH_MS, Math.round(1000 / numericFPS)));
}

function updateRefreshInterval(refreshMs) {
  if (refreshMs === currentRefreshMs) {
    return;
  }

  currentRefreshMs = refreshMs;
  if (timerWorker !== null) {
    timerWorker.postMessage({ type: 'start', interval: currentRefreshMs });
  }
  log(`Codex Pet refresh interval set to ${currentRefreshMs}ms`);
}

function readText(path, callback, label = 'frame') {
  const request = new XMLHttpRequest();
  request.overrideMimeType('text/plain');
  request.open('GET', path, true);
  request.onreadystatechange = () => {
    if (request.readyState !== 4) {
      return;
    }

    if (request.status === 0 || (request.status >= 200 && request.status < 300)) {
      callback(request.responseText);
      return;
    }

    log(`Failed to read Codex pet ${label}: ${request.status}`);
  };
  request.onerror = () => {
    log(`Failed to read Codex pet ${label}: XHR error`);
  };
  request.send();
}

function sendTitle(context, title) {
  if (!websocket || websocket.readyState !== WebSocket.OPEN || !context) {
    return;
  }

  websocket.send(JSON.stringify({
    event: 'setTitle',
    context,
    payload: {
      title,
      target: 0
    }
  }));
}

function log(message) {
  if (!websocket || websocket.readyState !== WebSocket.OPEN) {
    return;
  }

  websocket.send(JSON.stringify({
    event: 'logMessage',
    payload: { message }
  }));
}
