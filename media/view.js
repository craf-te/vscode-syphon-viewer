// Webview side. Draws the raw frames sent by the extension host onto a canvas.
(function () {
  const vscode = acquireVsCodeApi();

  const serverSelect = document.getElementById('server');
  const toggleButton = document.getElementById('toggle');
  const statusEl = document.getElementById('status');
  const statsEl = document.getElementById('stats');
  const canvas = document.getElementById('canvas');
  const placeholder = document.getElementById('placeholder');
  const ctx = canvas.getContext('2d', { alpha: false });

  let connected = false;

  function setStatus(text, isError) {
    statusEl.textContent = text;
    statusEl.classList.toggle('error', Boolean(isError));
  }

  function setConnected(value) {
    connected = value;
    toggleButton.textContent = value ? 'Disconnect' : 'Connect';
    toggleButton.disabled = !value && !serverSelect.value;
    canvas.classList.toggle('live', value);
    placeholder.classList.toggle('hidden', value);
    if (!value) statsEl.textContent = '';
  }

  serverSelect.addEventListener('change', () => {
    toggleButton.disabled = !serverSelect.value;
  });

  toggleButton.addEventListener('click', () => {
    if (connected) {
      vscode.postMessage({ type: 'disconnect' });
    } else if (serverSelect.value) {
      vscode.postMessage({ type: 'connect', uuid: serverSelect.value });
    }
  });

  function renderServers(servers) {
    const previous = serverSelect.value;
    serverSelect.textContent = '';

    const empty = document.createElement('option');
    empty.value = '';
    empty.textContent = servers.length ? 'Select a server' : 'No servers found';
    serverSelect.appendChild(empty);

    for (const s of servers) {
      const option = document.createElement('option');
      option.value = s.uuid;
      option.textContent = s.name ? `${s.appName} — ${s.name}` : s.appName;
      serverSelect.appendChild(option);
    }

    if (servers.some((s) => s.uuid === previous)) {
      serverSelect.value = previous;
    }
    toggleButton.disabled = !connected && !serverSelect.value;
  }

  function drawFrame(width, height, bytes) {
    try {
      // Raw RGBA arrives as-is. No decode step, so this can be synchronous.
      // postMessage can turn a Uint8Array into a plain array on the way, so
      // normalise it first.
      const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
      if (view.length !== width * height * 4) return;

      const data = new ImageData(
        new Uint8ClampedArray(view.buffer, view.byteOffset, view.length),
        width,
        height
      );
      if (canvas.width !== width || canvas.height !== height) {
        canvas.width = width;
        canvas.height = height;
      }
      ctx.putImageData(data, 0, 0);
    } catch (error) {
      // Drop a malformed frame silently; the next one recovers.
    }
  }

  window.addEventListener('message', (event) => {
    const message = event.data;
    switch (message.type) {
      case 'servers':
        renderServers(message.servers);
        break;
      case 'frame':
        drawFrame(message.width, message.height, message.pixels);
        break;
      case 'status':
        if (message.state === 'connected') {
          setConnected(true);
          setStatus(message.name ? `Connected: ${message.name}` : 'Connected', false);
        } else if (message.state === 'connecting') {
          setStatus('Connecting…', false);
        } else if (message.state === 'error') {
          setConnected(false);
          setStatus(message.message || 'Error', true);
        } else {
          setConnected(false);
          setStatus(message.message || 'Not connected', false);
        }
        break;
      case 'stats':
        {
          const src = `${message.sourceWidth}×${message.sourceHeight}`;
          const out = `${canvas.width}×${canvas.height}`;
          // No point printing the same dimensions twice when nothing scaled.
          const size = src === out ? src : `${src} → ${out}`;
          statsEl.textContent =
            `${size} · ${message.fps.toFixed(1)} fps · ` +
            `${(message.kbps / 8000).toFixed(0)} MB/s`;
        }
        break;
    }
  });

  vscode.postMessage({ type: 'ready' });
})();
