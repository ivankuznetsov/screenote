/**
 * Screenote Content Script
 *
 * Injects an annotation overlay onto the current page.
 * Reuses the same percentage-based coordinate system and visual style
 * as Screenote's web annotation UI.
 *
 * Coordinate system:
 *   x_percent, y_percent: position as % of viewport width/height (0-100)
 *   width_percent, height_percent: region size as % (null for point annotations)
 */

(() => {
  // Prevent double-injection
  if (window.__screenoteInjected) return;
  window.__screenoteInjected = true;

  const SCREENOTE_ORIGIN = "http://localhost:3005";

  let state = {
    active: false,
    projectId: null,
    screenshotId: null,
    screenshotDataUrl: null,
    annotations: [],
    drawing: false,
    drawStart: null,
    mode: "point", // "point" or "region"
  };

  // ── DOM Setup ──

  const overlay = document.createElement("div");
  overlay.id = "screenote-overlay";
  overlay.style.display = "none";

  const canvas = document.createElement("div");
  canvas.id = "screenote-canvas";

  const sidebar = document.createElement("div");
  sidebar.id = "screenote-sidebar";

  const toolbar = document.createElement("div");
  toolbar.id = "screenote-toolbar";

  overlay.appendChild(toolbar);
  overlay.appendChild(canvas);
  overlay.appendChild(sidebar);

  document.documentElement.appendChild(overlay);

  // ── Toolbar ──

  function renderToolbar() {
    toolbar.innerHTML = `
      <div class="sn-toolbar__left">
        <button class="sn-toolbar__btn ${state.mode === "point" ? "sn-toolbar__btn--active" : ""}" data-mode="point" title="Point annotation">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor"><circle cx="8" cy="8" r="6"/></svg>
        </button>
        <button class="sn-toolbar__btn ${state.mode === "region" ? "sn-toolbar__btn--active" : ""}" data-mode="region" title="Region annotation">
          <svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2"><rect x="2" y="2" width="12" height="12" rx="1"/></svg>
        </button>
      </div>
      <div class="sn-toolbar__right">
        <a class="sn-toolbar__link" href="${SCREENOTE_ORIGIN}/projects/${state.projectId}/screenshots/${state.screenshotId}" target="_blank" title="Open in Screenote">Open in Screenote</a>
        <button class="sn-toolbar__btn sn-toolbar__btn--close" title="Close overlay">✕</button>
      </div>
    `;

    toolbar.querySelector("[data-mode='point']").addEventListener("click", () => {
      state.mode = "point";
      renderToolbar();
    });
    toolbar.querySelector("[data-mode='region']").addEventListener("click", () => {
      state.mode = "region";
      renderToolbar();
    });
    toolbar.querySelector(".sn-toolbar__btn--close").addEventListener("click", deactivate);
  }

  // ── Canvas (annotation drawing) ──

  function setupCanvas() {
    // Show the captured screenshot as background
    canvas.style.backgroundImage = `url(${state.screenshotDataUrl})`;
    canvas.style.backgroundSize = "100% 100%";

    canvas.addEventListener("mousedown", onCanvasMouseDown);
    canvas.addEventListener("mousemove", onCanvasMouseMove);
    canvas.addEventListener("mouseup", onCanvasMouseUp);
  }

  function onCanvasMouseDown(e) {
    if (e.target.closest(".sn-pin") || e.target.closest(".sn-form")) return;

    // Close any open forms
    const openForm = canvas.querySelector(".sn-form");
    if (openForm) openForm.remove();

    const rect = canvas.getBoundingClientRect();
    const xPercent = ((e.clientX - rect.left) / rect.width) * 100;
    const yPercent = ((e.clientY - rect.top) / rect.height) * 100;

    if (state.mode === "point") {
      showAnnotationForm({
        x_percent: round2(xPercent),
        y_percent: round2(yPercent),
        width_percent: null,
        height_percent: null,
      });
    } else {
      state.drawing = true;
      state.drawStart = { x: e.clientX - rect.left, y: e.clientY - rect.top, xPercent, yPercent };

      const sel = document.createElement("div");
      sel.className = "sn-selection";
      sel.style.left = `${xPercent}%`;
      sel.style.top = `${yPercent}%`;
      sel.style.width = "0";
      sel.style.height = "0";
      canvas.appendChild(sel);
    }
  }

  function onCanvasMouseMove(e) {
    if (!state.drawing || !state.drawStart) return;

    const rect = canvas.getBoundingClientRect();
    const sel = canvas.querySelector(".sn-selection");
    if (!sel) return;

    const curX = e.clientX - rect.left;
    const curY = e.clientY - rect.top;

    const left = Math.min(state.drawStart.x, curX);
    const top = Math.min(state.drawStart.y, curY);
    const width = Math.abs(curX - state.drawStart.x);
    const height = Math.abs(curY - state.drawStart.y);

    sel.style.left = `${(left / rect.width) * 100}%`;
    sel.style.top = `${(top / rect.height) * 100}%`;
    sel.style.width = `${(width / rect.width) * 100}%`;
    sel.style.height = `${(height / rect.height) * 100}%`;
  }

  function onCanvasMouseUp(e) {
    if (!state.drawing) return;
    state.drawing = false;

    const sel = canvas.querySelector(".sn-selection");
    if (!sel) return;

    const rect = canvas.getBoundingClientRect();
    const curX = e.clientX - rect.left;
    const curY = e.clientY - rect.top;

    const left = Math.min(state.drawStart.xPercent, (curX / rect.width) * 100);
    const top = Math.min(state.drawStart.yPercent, (curY / rect.height) * 100);
    const width = Math.abs((curX / rect.width) * 100 - state.drawStart.xPercent);
    const height = Math.abs((curY / rect.height) * 100 - state.drawStart.yPercent);

    sel.remove();

    // If region too small, treat as point
    if (width < 1 && height < 1) {
      showAnnotationForm({
        x_percent: round2(left),
        y_percent: round2(top),
        width_percent: null,
        height_percent: null,
      });
    } else {
      showAnnotationForm({
        x_percent: round2(left),
        y_percent: round2(top),
        width_percent: round2(width),
        height_percent: round2(height),
      });
    }

    state.drawStart = null;
  }

  // ── Annotation Form ──

  function showAnnotationForm(coords) {
    // Remove existing form
    const existing = canvas.querySelector(".sn-form");
    if (existing) existing.remove();

    const form = document.createElement("div");
    form.className = "sn-form";

    // Position near the annotation point
    if (coords.width_percent) {
      form.style.left = `${coords.x_percent + coords.width_percent}%`;
      form.style.top = `${coords.y_percent}%`;
    } else {
      form.style.left = `${coords.x_percent + 2}%`;
      form.style.top = `${coords.y_percent}%`;
    }

    form.innerHTML = `
      <textarea class="sn-form__textarea" placeholder="Add a comment..." rows="3"></textarea>
      <div class="sn-form__actions">
        <button class="sn-form__btn sn-form__btn--primary" type="button">Save</button>
        <button class="sn-form__btn sn-form__btn--cancel" type="button">Cancel</button>
      </div>
    `;

    // Show preview pin/region
    const preview = coords.width_percent
      ? createRegionPin(coords, state.annotations.length + 1, false, true)
      : createPointPin(coords, state.annotations.length + 1, false, true);
    canvas.appendChild(preview);

    const textarea = form.querySelector("textarea");
    const saveBtn = form.querySelector(".sn-form__btn--primary");
    const cancelBtn = form.querySelector(".sn-form__btn--cancel");

    saveBtn.addEventListener("click", async () => {
      const comment = textarea.value.trim();
      if (!comment) {
        textarea.focus();
        return;
      }

      saveBtn.disabled = true;
      saveBtn.textContent = "Saving...";

      try {
        const result = await apiCreateAnnotation({
          ...coords,
          comment,
        });

        state.annotations.push(result);
        form.remove();
        preview.remove();
        renderPins();
        renderSidebar();
      } catch (err) {
        saveBtn.disabled = false;
        saveBtn.textContent = "Save";
        console.error("Screenote: Failed to save annotation", err);
      }
    });

    cancelBtn.addEventListener("click", () => {
      form.remove();
      preview.remove();
    });

    // Handle Enter key (Ctrl+Enter or Cmd+Enter to submit)
    textarea.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) {
        e.preventDefault();
        saveBtn.click();
      }
      if (e.key === "Escape") {
        e.preventDefault();
        cancelBtn.click();
      }
    });

    canvas.appendChild(form);
    textarea.focus();
  }

  // ── Pins (reuses Screenote's visual style) ──

  function createPointPin(coords, number, isResolved = false, isPreview = false) {
    const pin = document.createElement("div");
    pin.className = `sn-pin sn-pin--point${isResolved ? " sn-pin--resolved" : ""}${isPreview ? " sn-pin--preview" : ""}`;
    pin.style.left = `${coords.x_percent}%`;
    pin.style.top = `${coords.y_percent}%`;
    pin.textContent = number;
    return pin;
  }

  function createRegionPin(coords, number, isResolved = false, isPreview = false) {
    const region = document.createElement("div");
    region.className = `sn-pin sn-pin--region${isResolved ? " sn-pin--resolved" : ""}${isPreview ? " sn-pin--preview" : ""}`;
    region.style.left = `${coords.x_percent}%`;
    region.style.top = `${coords.y_percent}%`;
    region.style.width = `${coords.width_percent}%`;
    region.style.height = `${coords.height_percent}%`;

    const label = document.createElement("span");
    label.className = "sn-pin__label";
    label.textContent = number;
    region.appendChild(label);

    return region;
  }

  function renderPins() {
    canvas.querySelectorAll(".sn-pin").forEach((el) => el.remove());

    state.annotations.forEach((ann, i) => {
      const coords = ann.coordinates || ann;
      const isResolved = ann.status === "resolved";
      const pin = coords.width_percent
        ? createRegionPin(coords, i + 1, isResolved)
        : createPointPin(coords, i + 1, isResolved);
      canvas.appendChild(pin);
    });
  }

  // ── Sidebar ──

  function renderSidebar() {
    const annotations = state.annotations;

    sidebar.innerHTML = `
      <div class="sn-sidebar__header">
        <h2 class="sn-sidebar__title">Annotations (${annotations.length})</h2>
      </div>
      <div class="sn-sidebar__list">
        ${annotations.length === 0
          ? '<div class="sn-sidebar__empty">No annotations yet. Click on the screenshot to add one.</div>'
          : annotations.map((ann, i) => renderAnnotationItem(ann, i + 1)).join("")
        }
      </div>
    `;

    // Wire resolve buttons
    sidebar.querySelectorAll("[data-resolve]").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = parseInt(btn.dataset.resolve);
        const ann = annotations.find((a) => a.id === id);
        if (!ann) return;

        const newStatus = ann.status === "open" ? "resolved" : "open";
        try {
          const updated = await apiUpdateAnnotation(id, { status: newStatus });
          Object.assign(ann, updated);
          renderPins();
          renderSidebar();
        } catch (err) {
          console.error("Screenote: Failed to update annotation", err);
        }
      });
    });
  }

  function renderAnnotationItem(ann, number) {
    const isResolved = ann.status === "resolved";
    return `
      <div class="sn-item${isResolved ? " sn-item--resolved" : ""}">
        <div class="sn-item__header">
          <span class="sn-item__number">${number}</span>
          <span class="sn-item__author">${ann.author || "You"}</span>
        </div>
        <div class="sn-item__comment">${escapeHtml(ann.comment)}</div>
        <div class="sn-item__actions">
          <button class="sn-item__btn" data-resolve="${ann.id}">
            ${isResolved ? "Reopen" : "Resolve"}
          </button>
        </div>
      </div>
    `;
  }

  // ── API helpers (from content script context) ──

  async function getToken() {
    const data = await chrome.storage.local.get("access_token");
    return data.access_token;
  }

  async function apiFetch(path, options = {}) {
    const token = await getToken();
    if (!token) throw new Error("Not authenticated");

    const url = `${SCREENOTE_ORIGIN}${path}`;
    const headers = {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
      ...options.headers,
    };

    const response = await fetch(url, { ...options, headers });
    if (!response.ok) {
      throw new Error(`API error: ${response.status}`);
    }
    return response.json();
  }

  async function apiCreateAnnotation(params) {
    return apiFetch(
      `/api/v1/projects/${state.projectId}/screenshots/${state.screenshotId}/annotations`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(params),
      }
    );
  }

  async function apiUpdateAnnotation(annotationId, fields) {
    return apiFetch(
      `/api/v1/projects/${state.projectId}/screenshots/${state.screenshotId}/annotations/${annotationId}`,
      {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(fields),
      }
    );
  }

  async function apiGetAnnotations() {
    return apiFetch(
      `/api/v1/projects/${state.projectId}/screenshots/${state.screenshotId}/annotations`
    );
  }

  // ── Activation / Deactivation ──

  async function activate(data) {
    state.active = true;
    state.projectId = data.projectId;
    state.screenshotId = data.screenshotId;
    state.screenshotDataUrl = data.screenshotDataUrl;
    state.annotations = [];
    state.mode = "point";

    overlay.style.display = "";
    document.body.style.overflow = "hidden";

    setupCanvas();
    renderToolbar();

    // Load existing annotations
    try {
      const result = await apiGetAnnotations();
      state.annotations = result.annotations || [];
    } catch {
      // New screenshot, no annotations yet
    }

    renderPins();
    renderSidebar();
  }

  function deactivate() {
    state.active = false;
    overlay.style.display = "none";
    document.body.style.overflow = "";
    canvas.style.backgroundImage = "";
    canvas.innerHTML = "";
    sidebar.innerHTML = "";
    toolbar.innerHTML = "";
  }

  // ── Message listener ──

  chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
    if (message.action === "activateAnnotation") {
      activate(message).then(() => sendResponse({ success: true }));
      return true;
    }
    if (message.action === "deactivateAnnotation") {
      deactivate();
      sendResponse({ success: true });
    }
    if (message.action === "ping") {
      sendResponse({ active: state.active });
    }
  });

  // ── Escape key to close ──
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && state.active) {
      // If there's a form open, close just the form
      const form = canvas.querySelector(".sn-form");
      if (form) {
        form.remove();
        canvas.querySelectorAll(".sn-pin--preview").forEach((el) => el.remove());
      } else {
        deactivate();
      }
    }
  });

  // ── Helpers ──

  function round2(n) {
    return Math.round(n * 100) / 100;
  }

  function escapeHtml(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
  }
})();
