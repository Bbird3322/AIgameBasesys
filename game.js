"use strict";

const systemPrompt = [
  "You are the game master for a short Japanese text RPG.",
  "Keep responses in Japanese.",
  "Always describe scene, result, and 2-3 choices.",
  "Use concise style and preserve continuity from past turns."
].join(" ");

const logEl = document.getElementById("log");
const inputEl = document.getElementById("input");
const sendBtn = document.getElementById("sendBtn");
const statusEl = document.getElementById("status");
const healthEl = document.getElementById("healthLabel");
const agentCountEl = document.getElementById("agentCount");

const history = [
  { role: "system", content: systemPrompt },
  { role: "assistant", content: "夜霧が街を包む。あなたは石畳の路地に立っている。最初の行動を選んでください。" }
];

function addMessage(role, text) {
  const div = document.createElement("div");
  div.className = "msg " + (role === "user" ? "user" : "gm");
  div.textContent = text;
  logEl.appendChild(div);
  logEl.scrollTop = logEl.scrollHeight;
}

function setBusy(isBusy) {
  sendBtn.disabled = isBusy;
  inputEl.disabled = isBusy;
  if (agentCountEl) {
    agentCountEl.disabled = isBusy;
  }
  statusEl.textContent = isBusy ? "thinking..." : "ready";
}

function getAgentCount() {
  const parsed = parseInt(agentCountEl ? agentCountEl.value : "1", 10);
  if (Number.isNaN(parsed)) {
    return 1;
  }
  return Math.max(1, Math.min(parsed, 3));
}

async function askOneAgent(payload, agentIndex) {
  const response = await fetch("/api/chat", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    const raw = await response.text();
    throw new Error("HTTP " + response.status + " " + raw.slice(0, 220));
  }

  const data = await response.json();
  const reply = data && data.choices && data.choices[0] && data.choices[0].message
    ? data.choices[0].message.content
    : "応答の解析に失敗しました。";

  return {
    agentIndex,
    reply
  };
}

async function checkServer() {
  try {
    const response = await fetch("/__health", { method: "GET" });
    if (response.ok) {
      healthEl.textContent = "game-server: ok";
      healthEl.className = "ok";
    } else {
      healthEl.textContent = "game-server: unhealthy";
      healthEl.className = "bad";
    }
  } catch (_error) {
    healthEl.textContent = "game-server: offline";
    healthEl.className = "bad";
  }
}

async function sendTurn() {
  const userText = inputEl.value.trim();
  if (!userText) {
    return;
  }

  addMessage("user", userText);
  history.push({ role: "user", content: userText });
  inputEl.value = "";
  setBusy(true);

  const payload = {
    model: "local-model",
    messages: history,
    temperature: 0.8,
    max_tokens: 500
  };

  try {
    const agentCount = getAgentCount();
    const tasks = [];
    for (let i = 0; i < agentCount; i += 1) {
      tasks.push(askOneAgent(payload, i + 1));
    }

    const results = await Promise.allSettled(tasks);
    const successfulReplies = [];

    results.forEach((result, index) => {
      const label = "Agent " + (index + 1);
      if (result.status === "fulfilled") {
        const text = "[" + label + "]\n" + result.value.reply;
        addMessage("assistant", text);
        successfulReplies.push(result.value.reply);
      } else {
        const errText = "[" + label + "] 通信エラー: " + (result.reason && result.reason.message ? result.reason.message : String(result.reason));
        addMessage("assistant", errText);
      }
    });

    if (successfulReplies.length === 0) {
      throw new Error("全エージェントの応答に失敗しました。");
    }

    history.push({ role: "assistant", content: successfulReplies[0] });
  } catch (error) {
    const msg = "通信エラー: " + (error && error.message ? error.message : String(error));
    addMessage("assistant", msg);
    history.push({ role: "assistant", content: msg });
  } finally {
    setBusy(false);
    inputEl.focus();
  }
}

sendBtn.addEventListener("click", sendTurn);
inputEl.addEventListener("keydown", (event) => {
  if ((event.ctrlKey || event.metaKey) && event.key === "Enter") {
    sendTurn();
  }
});

addMessage("assistant", history[1].content);
checkServer();
inputEl.focus();
