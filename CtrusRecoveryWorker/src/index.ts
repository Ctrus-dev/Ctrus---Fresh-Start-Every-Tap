interface Env {
  RECOVERY_CODES: KVNamespace;
}

interface CodeEntry {
  code: string;
  createdAt: number;
  expiresAt: number;
  used: boolean;
  attempts: number;
}

const CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ"; // no 0/O, 1/I
const CODE_LENGTH = 8;
const CODE_TTL_SECONDS = 15 * 60;
const MAX_VERIFY_ATTEMPTS = 5;
const HISTORY_WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
const HISTORY_TTL_SECONDS = 7 * 24 * 60 * 60;
const MAX_DEVICE_ID_LENGTH = 128;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "GET" && url.pathname === "/") {
      return new Response(RECOVERY_PAGE_HTML, {
        headers: { "content-type": "text/html; charset=utf-8" },
      });
    }

    if (request.method === "POST" && url.pathname === "/request-code") {
      return handleRequestCode(request, env);
    }

    if (request.method === "POST" && url.pathname === "/verify-code") {
      return handleVerifyCode(request, env);
    }

    return new Response("Not found", { status: 404 });
  },
};

async function handleRequestCode(request: Request, env: Env): Promise<Response> {
  const deviceId = await readDeviceId(request);
  if (!deviceId) {
    return json({ error: "invalid deviceId" }, 400);
  }

  const key = `code:${deviceId}`;
  const now = Date.now();
  const existing = await env.RECOVERY_CODES.get<CodeEntry>(key, "json");

  if (existing && !existing.used && existing.expiresAt > now) {
    return json({ code: formatCode(existing.code) });
  }

  const code = generateCode();
  const entry: CodeEntry = {
    code,
    createdAt: now,
    expiresAt: now + CODE_TTL_SECONDS * 1000,
    used: false,
    attempts: 0,
  };
  await env.RECOVERY_CODES.put(key, JSON.stringify(entry), {
    expirationTtl: CODE_TTL_SECONDS,
  });

  return json({ code: formatCode(code) });
}

async function handleVerifyCode(request: Request, env: Env): Promise<Response> {
  const body = await readJsonBody(request);
  const deviceId = normalizeDeviceId(body?.deviceId);
  const submittedCode = normalizeCode(typeof body?.code === "string" ? body.code : "");

  if (!deviceId || !submittedCode) {
    return json({ valid: false });
  }

  const key = `code:${deviceId}`;
  const now = Date.now();
  const entry = await env.RECOVERY_CODES.get<CodeEntry>(key, "json");

  if (!entry || entry.used || entry.expiresAt <= now) {
    await env.RECOVERY_CODES.delete(key);
    return json({ valid: false });
  }

  if (entry.code !== submittedCode) {
    entry.attempts += 1;
    if (entry.attempts >= MAX_VERIFY_ATTEMPTS) {
      await env.RECOVERY_CODES.delete(key);
    } else {
      const remainingTtl = Math.max(1, Math.ceil((entry.expiresAt - now) / 1000));
      await env.RECOVERY_CODES.put(key, JSON.stringify(entry), {
        expirationTtl: remainingTtl,
      });
    }
    return json({ valid: false });
  }

  await env.RECOVERY_CODES.delete(key);
  const recentUnlockCount = await recordUnlock(env, deviceId, now);

  return json({ valid: true, recentUnlockCount });
}

async function recordUnlock(env: Env, deviceId: string, now: number): Promise<number> {
  const historyKey = `history:${deviceId}`;
  const history = (await env.RECOVERY_CODES.get<number[]>(historyKey, "json")) ?? [];
  const cutoff = now - HISTORY_WINDOW_MS;
  const pruned = history.filter((timestamp) => timestamp > cutoff);
  pruned.push(now);

  await env.RECOVERY_CODES.put(historyKey, JSON.stringify(pruned), {
    expirationTtl: HISTORY_TTL_SECONDS,
  });

  return pruned.length;
}

function generateCode(): string {
  const bytes = new Uint8Array(CODE_LENGTH);
  crypto.getRandomValues(bytes);
  let code = "";
  for (const byte of bytes) {
    code += CODE_ALPHABET[byte % CODE_ALPHABET.length];
  }
  return code;
}

function formatCode(code: string): string {
  return `${code.slice(0, 4)}-${code.slice(4)}`;
}

function normalizeCode(raw: string): string {
  return raw.toUpperCase().replace(/[^A-Z0-9]/g, "");
}

function normalizeDeviceId(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  if (trimmed.length === 0 || trimmed.length > MAX_DEVICE_ID_LENGTH) return null;
  return trimmed;
}

async function readDeviceId(request: Request): Promise<string | null> {
  const body = await readJsonBody(request);
  return normalizeDeviceId(body?.deviceId);
}

async function readJsonBody(request: Request): Promise<any | null> {
  try {
    return await request.json();
  } catch {
    return null;
  }
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

const RECOVERY_PAGE_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title data-i18n="title">Ctrus - Recovery Code</title>
<style>
  :root { color-scheme: light dark; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    max-width: 480px;
    margin: 48px auto;
    padding: 0 20px;
    line-height: 1.5;
  }
  h1 { font-size: 1.4rem; margin-right: 40px; }
  input {
    width: 100%;
    box-sizing: border-box;
    font-size: 1rem;
    padding: 12px;
    margin: 12px 0;
    border-radius: 8px;
    border: 1px solid #999;
  }
  button {
    width: 100%;
    font-size: 1rem;
    padding: 12px;
    border-radius: 8px;
    border: none;
    background: #ff8a00;
    color: white;
    cursor: pointer;
  }
  button:disabled { opacity: 0.5; cursor: default; }
  #result {
    margin-top: 20px;
    font-size: 1.8rem;
    font-weight: 600;
    letter-spacing: 2px;
    text-align: center;
    display: none;
  }
  #error {
    margin-top: 12px;
    color: #c0392b;
    display: none;
  }

  #langToggle {
    position: fixed;
    top: 16px;
    right: 16px;
    width: auto;
    padding: 8px 12px;
    font-size: 1.1rem;
    background: transparent;
    border: 1px solid #999;
    color: inherit;
  }

  #langOverlay {
    display: none;
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.4);
    z-index: 10;
  }
  #langOverlay.open { display: block; }

  #langPanel {
    position: fixed;
    top: 0;
    right: 0;
    height: 100%;
    width: 240px;
    max-width: 80vw;
    background: Canvas;
    color: CanvasText;
    box-shadow: -4px 0 16px rgba(0, 0, 0, 0.3);
    z-index: 11;
    padding: 20px;
    box-sizing: border-box;
    transform: translateX(100%);
    transition: transform 0.2s ease-out;
  }
  #langPanel.open { transform: translateX(0); }

  #langPanel h2 { font-size: 1rem; margin: 0 0 16px; }
  .lang-option {
    display: flex;
    justify-content: space-between;
    align-items: center;
    width: 100%;
    background: transparent;
    color: inherit;
    border: 1px solid #999;
    margin-bottom: 8px;
    padding: 10px 12px;
  }
  .lang-option[data-active="true"] {
    border-color: #ff8a00;
    color: #ff8a00;
  }
</style>
</head>
<body>
  <button id="langToggle" aria-haspopup="true" aria-controls="langPanel">🌐</button>

  <h1 data-i18n="heading">Get unlock code</h1>
  <p data-i18n="description">Paste here the Device ID shown in Ctrus app Settings (section "Lost your Ctrus?").</p>
  <input id="deviceId" data-i18n-placeholder="placeholder" placeholder="Device ID" autocomplete="off" autocapitalize="off" spellcheck="false" />
  <button id="submit" data-i18n="button">Get code</button>
  <div id="result"></div>
  <p id="error" data-i18n="error">Couldn't get a code. Check the Device ID and try again.</p>
  <p><small data-i18n="footnote">The code is valid for 15 minutes and can only be used once.</small></p>

  <div id="langOverlay"></div>
  <div id="langPanel" role="dialog" aria-label="Language">
    <h2 data-i18n="langLabel">Language</h2>
    <button class="lang-option" data-lang="en">English</button>
    <button class="lang-option" data-lang="pt">Português</button>
  </div>

  <script>
    const TRANSLATIONS = {
      en: {
        title: "Ctrus - Recovery Code",
        heading: "Get unlock code",
        description: 'Paste here the Device ID shown in Ctrus app Settings (section "Lost your Ctrus?").',
        placeholder: "Device ID",
        button: "Get code",
        error: "Couldn't get a code. Check the Device ID and try again.",
        footnote: "The code is valid for 15 minutes and can only be used once.",
        langLabel: "Language",
      },
      pt: {
        title: "Ctrus - Código de Recuperação",
        heading: "Obter código de desbloqueio",
        description: 'Cola aqui o Device ID que aparece nas Definições da app Ctrus (secção "Perdeste o teu Ctrus?").',
        placeholder: "Device ID",
        button: "Obter código",
        error: "Não foi possível obter um código. Verifica o Device ID e tenta novamente.",
        footnote: "O código é válido por 15 minutos e só pode ser usado uma vez.",
        langLabel: "Idioma",
      },
    };

    function applyLanguage(lang) {
      const strings = TRANSLATIONS[lang] || TRANSLATIONS.en;
      document.documentElement.lang = lang;
      document.querySelectorAll("[data-i18n]").forEach((el) => {
        el.textContent = strings[el.dataset.i18n];
      });
      document.querySelectorAll("[data-i18n-placeholder]").forEach((el) => {
        el.placeholder = strings[el.dataset.i18nPlaceholder];
      });
      document.querySelectorAll(".lang-option").forEach((el) => {
        el.dataset.active = String(el.dataset.lang === lang);
      });
      localStorage.setItem("ctrus-lang", lang);
    }

    function detectInitialLanguage() {
      const saved = localStorage.getItem("ctrus-lang");
      if (saved && TRANSLATIONS[saved]) return saved;
      return navigator.language && navigator.language.toLowerCase().startsWith("pt") ? "pt" : "en";
    }

    const langToggle = document.getElementById("langToggle");
    const langPanel = document.getElementById("langPanel");
    const langOverlay = document.getElementById("langOverlay");

    function openLangPanel() {
      langPanel.classList.add("open");
      langOverlay.classList.add("open");
    }
    function closeLangPanel() {
      langPanel.classList.remove("open");
      langOverlay.classList.remove("open");
    }

    langToggle.addEventListener("click", openLangPanel);
    langOverlay.addEventListener("click", closeLangPanel);
    document.querySelectorAll(".lang-option").forEach((el) => {
      el.addEventListener("click", () => {
        applyLanguage(el.dataset.lang);
        closeLangPanel();
      });
    });

    applyLanguage(detectInitialLanguage());

    const input = document.getElementById("deviceId");
    const button = document.getElementById("submit");
    const result = document.getElementById("result");
    const error = document.getElementById("error");

    button.addEventListener("click", async () => {
      const deviceId = input.value.trim();
      if (!deviceId) return;

      button.disabled = true;
      result.style.display = "none";
      error.style.display = "none";

      try {
        const response = await fetch("/request-code", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ deviceId }),
        });

        if (!response.ok) throw new Error("request failed");

        const data = await response.json();
        result.textContent = data.code;
        result.style.display = "block";
      } catch {
        error.style.display = "block";
      } finally {
        button.disabled = false;
      }
    });
  </script>
</body>
</html>`;
