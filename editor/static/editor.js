"use strict";

const RANGES = {
  dur:  { min: 0.03, max: 1.5,  step: 0.01, unit: "s" },
  f0:   { min: 80,   max: 5000, step: 10,   unit: "Hz" },
  f1:   { min: 80,   max: 5000, step: 10,   unit: "Hz" },
  mf:   { min: 0,    max: 120,  step: 1,    unit: "Hz" },
  md:   { min: 0,    max: 4.0,  step: 0.05, unit: "" },
  amp:  { min: 0.1,  max: 1.0,  step: 0.05, unit: "" },
};

let audioCtx = null;
let debounceTimers = {};

function getAudioCtx() {
  if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  return audioCtx;
}

async function playWavBlob(blob) {
  const ctx = getAudioCtx();
  const buf = await blob.arrayBuffer();
  const decoded = await ctx.decodeAudioData(buf);
  const src = ctx.createBufferSource();
  src.buffer = decoded;
  src.connect(ctx.destination);
  src.start();
}

async function playInstalledSound(name) {
  const res = await fetch(`/audio/${name}`);
  if (!res.ok) { alert("Could not load sound. Run install.sh first."); return; }
  await playWavBlob(await res.blob());
}

async function previewSegments(segments) {
  const res = await fetch("/preview", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ segments }),
  });
  if (!res.ok) return;
  await playWavBlob(await res.blob());
}

function readSegmentsFromPanel(panel) {
  return Array.from(panel.querySelectorAll(".segment-block")).map(block => {
    const type = block.dataset.type;
    const seg = { type };
    block.querySelectorAll("input[type=range]").forEach(inp => {
      seg[inp.dataset.param] = parseFloat(inp.value);
    });
    return seg;
  });
}

function makeSlider(param, value, onChange) {
  const r = RANGES[param];
  const row = document.createElement("div");
  row.className = "param-row";

  const label = document.createElement("label");
  label.textContent = param;

  const input = document.createElement("input");
  input.type = "range";
  input.min = r.min; input.max = r.max; input.step = r.step;
  input.value = value;
  input.dataset.param = param;

  const valDisplay = document.createElement("span");
  valDisplay.className = "val";
  valDisplay.textContent = value + r.unit;

  input.addEventListener("input", () => {
    valDisplay.textContent = parseFloat(input.value) + r.unit;
    onChange();
  });

  row.append(label, input, valDisplay);
  return row;
}

function buildSegmentBlock(seg, index, onSliderChange) {
  const block = document.createElement("div");
  block.className = `segment-block ${seg.type}-seg`;
  block.dataset.type = seg.type;

  const label = document.createElement("div");
  label.className = "seg-label";
  label.textContent = seg.type === "gap"
    ? `gap ${index + 1}`
    : `chirp ${index + 1}`;
  block.appendChild(label);

  if (seg.type === "gap") {
    block.appendChild(makeSlider("dur", seg.dur, onSliderChange));
  } else {
    for (const param of ["dur", "f0", "f1", "mf", "md", "amp"]) {
      const val = seg[param] !== undefined ? seg[param] : RANGES[param].min;
      block.appendChild(makeSlider(param, val, onSliderChange));
    }
  }
  return block;
}

function buildCard(name, defn) {
  const card = document.createElement("div");
  card.className = "sound-card";

  // ── header ──
  const header = document.createElement("div");
  header.className = "card-header";

  const nameEl = document.createElement("span");
  nameEl.className = "name";
  nameEl.textContent = name;

  const descEl = document.createElement("span");
  descEl.className = "desc";
  descEl.textContent = defn.description;

  const pill = document.createElement("span");
  pill.className = "events-pill";
  pill.textContent = defn.events.length === 1
    ? defn.events[0]
    : `${defn.events.length} events`;
  pill.title = defn.events.join(", ");

  const btnPlay = document.createElement("button");
  btnPlay.className = "btn btn-play";
  btnPlay.textContent = "▶ Play";
  btnPlay.addEventListener("click", () => playInstalledSound(name));

  const btnEdit = document.createElement("button");
  btnEdit.className = "btn btn-edit";
  btnEdit.textContent = "✎ Edit";
  btnEdit.addEventListener("click", () => togglePanel(name, panel, defn.segments));

  header.append(nameEl, descEl, pill, btnPlay, btnEdit);

  // ── edit panel ──
  const panel = document.createElement("div");
  panel.className = "edit-panel";
  panel.dataset.name = name;

  card.append(header, panel);
  return card;
}

let savedSegments = {};

function openPanel(name, panel, segments) {
  panel.innerHTML = "";
  const segContainer = document.createElement("div");

  const makeDebounced = () => {
    clearTimeout(debounceTimers[name]);
    debounceTimers[name] = setTimeout(() => {
      previewSegments(readSegmentsFromPanel(panel));
    }, 150);
  };

  segments.forEach((seg, i) => {
    segContainer.appendChild(buildSegmentBlock(seg, i, makeDebounced));
  });
  panel.appendChild(segContainer);

  // footer buttons
  const footer = document.createElement("div");
  footer.className = "panel-footer";

  const btnPreview = document.createElement("button");
  btnPreview.className = "btn btn-preview";
  btnPreview.textContent = "▶ Preview";
  btnPreview.addEventListener("click", () => {
    previewSegments(readSegmentsFromPanel(panel));
  });

  const btnSave = document.createElement("button");
  btnSave.className = "btn btn-save";
  btnSave.textContent = "✓ Save";
  btnSave.addEventListener("click", async () => {
    const segs = readSegmentsFromPanel(panel);
    btnSave.disabled = true;
    btnSave.classList.add("saving");
    toast.className = "toast";
    toast.textContent = "";
    const res = await fetch(`/save/${name}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ segments: segs }),
    });
    btnSave.disabled = false;
    btnSave.classList.remove("saving");
    if (res.ok) {
      savedSegments[name] = JSON.parse(JSON.stringify(segs));
      toast.textContent = "Saved";
      toast.className = "toast ok";
    } else {
      const err = await res.json();
      toast.textContent = "Error: " + (err.error || "unknown");
      toast.className = "toast fail";
    }
    setTimeout(() => { toast.className = "toast"; }, 3000);
  });

  const btnReset = document.createElement("button");
  btnReset.className = "btn btn-reset";
  btnReset.textContent = "↺ Reset";
  btnReset.addEventListener("click", () => {
    openPanel(name, panel, JSON.parse(JSON.stringify(savedSegments[name])));
  });

  const toast = document.createElement("span");
  toast.className = "toast";

  footer.append(btnPreview, btnSave, btnReset, toast);
  panel.appendChild(footer);
  panel.classList.add("open");
}

function togglePanel(name, panel, segments) {
  const wasOpen = panel.classList.contains("open");
  document.querySelectorAll(".edit-panel.open").forEach(p => p.classList.remove("open"));
  if (wasOpen) return;
  savedSegments[name] = JSON.parse(JSON.stringify(segments));
  openPanel(name, panel, segments);
}

async function init() {
  const res = await fetch("/sounds");
  const defs = await res.json();
  const list = document.getElementById("sound-list");
  for (const [name, defn] of Object.entries(defs)) {
    list.appendChild(buildCard(name, defn));
  }
}

document.addEventListener("DOMContentLoaded", init);
