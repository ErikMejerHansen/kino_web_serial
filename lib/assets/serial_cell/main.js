// Web Serial Smart Cell.
//
// All state lives in Elixir and arrives here as views to render. The only
// browser-side state is what the Web Serial API cannot hand over to
// Elixir: the open SerialPort, its reader and writer.

const LINE_ENDING_LABELS = {
  none: "No line ending",
  lf: "LF",
  cr: "CR",
  crlf: "CR+LF",
};

export function init(ctx, payload) {
  ctx.importCSS("main.css");
  ctx.importCSS(
    "https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&family=JetBrains+Mono&display=swap",
  );

  let serialPort = null;
  let writer = null;
  let reader = null;
  let reading = null;
  let closing = false;

  const choices = payload.choices;
  const maxEntries = payload.max_entries;
  let fields = payload.fields;
  let port = payload.port;

  ctx.root.innerHTML = `
    <div class="app">
      <div class="header">
        <div class="row">
          <div class="inline-field">
            <label class="inline-input-label" for="baud_rate">Baud rate</label>
            <input class="input input--sm" id="baud_rate" data-field="baud_rate" type="text"
              inputmode="numeric" list="baud_rates" spellcheck="false" />
            <datalist id="baud_rates">
              ${choices.baud_rate.map((rate) => `<option value="${rate}"></option>`).join("")}
            </datalist>
          </div>
          <div class="inline-field">
            <label class="inline-input-label" for="usb_vendor_id">USB vendor</label>
            <input class="input input--xs" id="usb_vendor_id" data-field="usb_vendor_id" type="text"
              spellcheck="false" placeholder="any" />
          </div>
          <div class="inline-field">
            <label class="inline-input-label" for="usb_product_id">Product</label>
            <input class="input input--xs" id="usb_product_id" data-field="usb_product_id" type="text"
              spellcheck="false" placeholder="any" />
          </div>
          <div class="grow"></div>
          <div class="inline-field">
            <label class="inline-input-label" for="variable">Assign to</label>
            <input class="input input--sm" id="variable" data-field="variable" type="text" spellcheck="false" />
          </div>
          <button class="button button--primary" id="connect" type="button"></button>
        </div>
        <div class="row">
          ${select("data_bits", "Data bits", choices.data_bits)}
          ${select("parity", "Parity", choices.parity)}
          ${select("stop_bits", "Stop bits", choices.stop_bits)}
          ${select("flow_control", "Flow control", choices.flow_control)}
        </div>
      </div>
      <div class="body">
        <div class="status" id="status"></div>
        <div class="monitor">
          <div class="monitor-toolbar">
            <span class="tag">Monitor</span>
            <div class="grow"></div>
            <div class="toggle" role="group" aria-label="Show data as">
              <button class="toggle-option" type="button" data-display="text">Text</button>
              <button class="toggle-option" type="button" data-display="hex">Hex</button>
            </div>
            <button class="button button--sm" id="clear" type="button">Clear</button>
          </div>
          <div class="log" id="log"></div>
          <div class="send">
            <input class="input input--send grow" id="send_value" type="text" spellcheck="false"
              placeholder="Data to send" />
            <select class="input" id="send_format">
              ${choices.formats.map((f) => `<option value="${f}">${f}</option>`).join("")}
            </select>
            <select class="input" id="send_line_ending">
              ${choices.line_endings
                .map((e) => `<option value="${e}">${LINE_ENDING_LABELS[e] || e}</option>`)
                .join("")}
            </select>
            <button class="button" id="send" type="button">Send</button>
          </div>
        </div>
      </div>
    </div>
  `;

  const $ = (selector) => ctx.root.querySelector(selector);
  const fieldInputs = [...ctx.root.querySelectorAll("[data-field]")];
  const optionInputs = fieldInputs.filter((input) => input.id !== "variable");
  const connectButton = $("#connect");
  const status = $("#status");
  const log = $("#log");
  const sendValue = $("#send_value");
  const sendFormat = $("#send_format");
  const sendLineEnding = $("#send_line_ending");
  const sendButton = $("#send");

  // Rendering

  function renderFields() {
    fieldInputs.forEach((input) => setInputValue(input, String(fields[input.dataset.field])));
    setInputValue(sendValue, fields.send.value);
    setInputValue(sendFormat, fields.send.format);
    setInputValue(sendLineEnding, fields.send.line_ending);

    log.classList.toggle("log--hex", fields.display === "hex");
    ctx.root.querySelectorAll("[data-display]").forEach((button) => {
      button.classList.toggle("toggle-option--active", button.dataset.display === fields.display);
    });
  }

  function renderPort() {
    const connected = port.status === "connected";

    connectButton.textContent = connected ? "Disconnect" : "Connect";
    connectButton.classList.toggle("button--primary", !connected);
    connectButton.disabled = !connected && !navigator.serial;
    optionInputs.forEach((input) => (input.disabled = connected));
    [sendValue, sendFormat, sendLineEnding, sendButton].forEach((el) => (el.disabled = !connected));

    if (connected) {
      status.innerHTML = `
        <div class="port">
          <span class="status-dot"></span>
          <span>Connected to <strong>${escape(port.name)}</strong></span>
          <span class="port-options">${escape(describeOptions(port.options))}</span>
        </div>
      `;
    } else {
      status.innerHTML = `
        ${
          navigator.serial
            ? `<p class="help">Choose the connection options and click <strong>Connect</strong> to pick a serial port.</p>`
            : `<div class="box box--warning">Web Serial is not available in this browser. Use a Chromium based browser, such as Chrome or Edge.</div>`
        }
        ${port.error ? `<div class="box box--error">${escape(port.error)}</div>` : ""}
      `;
    }
  }

  function renderEntries(entries) {
    const atBottom = log.scrollHeight - log.scrollTop - log.clientHeight < 8;

    entries.forEach((entry) => {
      const html = renderEntry(entry);
      const existing = log.querySelector(`[data-id="${entry.id}"]`);
      if (existing) {
        existing.outerHTML = html;
      } else {
        log.insertAdjacentHTML("beforeend", html);
      }
    });

    while (log.children.length > maxEntries) log.firstElementChild.remove();
    if (atBottom) log.scrollTop = log.scrollHeight;
  }

  function renderEntry(entry) {
    const arrow = { rx: "←", tx: "→", error: "!" }[entry.direction];
    const error = entry.direction === "error";

    return `
      <div class="entry entry--${entry.direction}" data-id="${entry.id}">
        <span class="entry-time">${escape(new Date(entry.at).toLocaleTimeString())}</span>
        <span class="entry-direction">${arrow}</span>
        <code class="entry-text">${escape(entry.text)}</code>
        <code class="entry-hex">${escape(error ? entry.text : entry.hex)}</code>
      </div>
    `;
  }

  // UI events

  fieldInputs.forEach((input) => {
    input.addEventListener("change", (event) => {
      ctx.pushEvent("update_field", { field: input.dataset.field, value: event.target.value });
    });
  });

  ctx.root.querySelectorAll("[data-display]").forEach((button) => {
    button.addEventListener("click", () => {
      ctx.pushEvent("update_field", { field: "display", value: button.dataset.display });
    });
  });

  connectButton.addEventListener("click", () => {
    if (port.status === "connected") {
      ctx.pushEvent("disconnect", {});
    } else {
      connect();
    }
  });

  [sendValue, sendFormat, sendLineEnding].forEach((input) => {
    input.addEventListener("change", pushSendInput);
  });

  sendButton.addEventListener("click", () => {
    pushSendInput();
    ctx.pushEvent("send", {});
  });

  sendValue.addEventListener("keydown", (event) => {
    if (event.key === "Enter") sendButton.click();
  });

  $("#clear").addEventListener("click", () => ctx.pushEvent("clear", {}));

  function pushSendInput() {
    ctx.pushEvent("update_send", {
      value: sendValue.value,
      format: sendFormat.value,
      line_ending: sendLineEnding.value,
    });
  }

  // Server events

  ctx.handleEvent("fields", (newFields) => {
    fields = newFields;
    renderFields();
  });

  ctx.handleEvent("port", (newPort) => {
    port = newPort;
    renderPort();
  });

  ctx.handleEvent("log", renderEntries);

  ctx.handleEvent("log_cleared", () => {
    log.innerHTML = "";
  });

  ctx.handleEvent("request", handleRequest);

  ctx.handleSync(() => {
    // Flush pending input changes before evaluation
    document.activeElement && document.activeElement.dispatchEvent(new Event("change", { bubbles: true }));
  });

  // Web Serial

  async function connect() {
    const options = openOptions();
    let selected;

    try {
      selected = await navigator.serial.requestPort({ filters: fields.filters });
      await closePort();
      await selected.open(options);
    } catch (error) {
      ctx.pushEvent("connect_error", { message: errorMessage(error) });
      return;
    }

    serialPort = selected;
    writer = serialPort.writable.getWriter();

    const info = serialPort.getInfo();

    ctx.pushEvent("connected", {
      info: { usbVendorId: info.usbVendorId ?? null, usbProductId: info.usbProductId ?? null },
      options: fields,
    });

    reading = readLoop(serialPort);
  }

  function openOptions() {
    return {
      baudRate: fields.baud_rate,
      dataBits: fields.data_bits,
      stopBits: fields.stop_bits,
      parity: fields.parity,
      flowControl: fields.flow_control,
    };
  }

  // Reads until the port is closed or lost. After a non-fatal error,
  // such as a framing error, the port offers a new readable stream.
  async function readLoop(port) {
    while (port === serialPort && port.readable && !closing) {
      reader = port.readable.getReader();

      try {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          if (value.byteLength > 0) ctx.pushEvent("data", [{}, toArrayBuffer(value)]);
        }
      } catch (error) {
        if (!closing) ctx.pushEvent("read_error", { message: errorMessage(error) });
      } finally {
        reader.releaseLock();
        reader = null;
      }
    }

    if (port === serialPort && !closing) {
      // The port was lost, for example unplugged
      releaseWriter();
      serialPort = null;
      port.close().catch(() => {});
      ctx.pushEvent("disconnected", {});
    }
  }

  async function closePort() {
    if (!serialPort) return;

    const port = serialPort;
    closing = true;

    try {
      if (reader) await reader.cancel().catch(() => {});
      await reading;
      releaseWriter();
      await port.close();
    } catch (error) {
      console.warn("[KinoWebSerial] closing the port failed", error);
    } finally {
      serialPort = null;
      reading = null;
      closing = false;
    }
  }

  function releaseWriter() {
    if (!writer) return;
    try {
      writer.releaseLock();
    } catch (_error) {
      // Already released
    }
    writer = null;
  }

  async function handleRequest(payload) {
    // Writes carry their data as a binary payload
    const [request, buffer] = Array.isArray(payload) ? payload : [payload, null];
    const { ref, op } = request;

    if (op === "close") {
      await closePort();
      return;
    }

    const reply = (result) => ctx.pushEvent("response", { ref, ...result });

    if (!serialPort) {
      reply({ error: "port not open" });
      return;
    }

    try {
      switch (op) {
        case "write":
          await writer.write(new Uint8Array(buffer));
          reply({});
          break;

        case "set_signals":
          await serialPort.setSignals(request.signals);
          reply({});
          break;

        case "get_signals":
          reply({ signals: await serialPort.getSignals() });
          break;

        default:
          reply({ error: `unknown operation ${op}` });
      }
    } catch (error) {
      reply({ error: errorMessage(error) });
    }
  }

  renderFields();
  renderPort();
  renderEntries(payload.log);
}

function select(field, label, options) {
  return `
    <div class="inline-field">
      <label class="inline-input-label" for="${field}">${label}</label>
      <select class="input" id="${field}" data-field="${field}">
        ${options.map((option) => `<option value="${option}">${option}</option>`).join("")}
      </select>
    </div>
  `;
}

// Like "115200 baud, 8N1"
function describeOptions(options) {
  if (!options) return "";

  const frame = `${options.data_bits}${options.parity[0].toUpperCase()}${options.stop_bits}`;
  const flow = options.flow_control === "hardware" ? ", hardware flow control" : "";
  return `${options.baud_rate} baud, ${frame}${flow}`;
}

function toArrayBuffer(bytes) {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}

function errorMessage(error) {
  return (error && error.message) || String(error);
}

function setInputValue(input, value) {
  if (document.activeElement !== input && input.value !== value) {
    input.value = value;
  }
}

function escape(string) {
  return String(string)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
