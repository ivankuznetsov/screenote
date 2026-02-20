const SCREENOTE_ORIGIN = "http://localhost:3005";

const $ = (sel) => document.querySelector(sel);

const loadingEl = $("#loading");
const authScreen = $("#auth-screen");
const mainScreen = $("#main-screen");
const loginBtn = $("#login-btn");
const logoutBtn = $("#logout-btn");
const userEmailEl = $("#user-email");
const projectSelect = $("#project-select");
const urlMatchEl = $("#url-match");
const showNewProjectBtn = $("#show-new-project");
const newProjectForm = $("#new-project-form");
const newProjectNameInput = $("#new-project-name");
const createProjectBtn = $("#create-project-btn");
const captureBtn = $("#capture-btn");
const statusEl = $("#status");

let currentTabUrl = "";
let projects = [];

// ── Initialization ──

async function init() {
  // Get current tab URL
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  currentTabUrl = tab?.url || "";

  // Check auth status
  const { access_token } = await chrome.storage.local.get("access_token");

  if (!access_token) {
    showScreen("auth");
    return;
  }

  // Verify token and get user info
  try {
    const user = await apiFetch("/api/v1/me");
    userEmailEl.textContent = user.email;
    await loadProjects();
    showScreen("main");
  } catch (err) {
    // Token might be expired
    showScreen("auth");
  }
}

function showScreen(screen) {
  loadingEl.style.display = "none";
  authScreen.style.display = screen === "auth" ? "" : "none";
  mainScreen.style.display = screen === "main" ? "" : "none";
}

function showStatus(type, message) {
  statusEl.className = `status status--visible status--${type}`;
  statusEl.textContent = message;
  if (type === "success") {
    setTimeout(() => {
      statusEl.className = "status";
    }, 3000);
  }
}

function clearStatus() {
  statusEl.className = "status";
}

// ── API helper ──

async function apiFetch(path, options = {}) {
  const { access_token } = await chrome.storage.local.get("access_token");
  if (!access_token) throw new Error("Not authenticated");

  const url = `${SCREENOTE_ORIGIN}${path}`;
  const headers = {
    Authorization: `Bearer ${access_token}`,
    Accept: "application/json",
    ...options.headers,
  };

  const response = await fetch(url, { ...options, headers });

  if (response.status === 401) {
    throw new Error("Authentication expired");
  }

  if (!response.ok) {
    const body = await response.text();
    throw new Error(body);
  }

  return response.json();
}

// ── Projects ──

async function loadProjects() {
  try {
    const data = await apiFetch("/api/v1/projects");
    projects = data.projects || [];
    renderProjectSelect();
    autoMatchProject();
  } catch (err) {
    showStatus("error", "Failed to load projects");
  }
}

function renderProjectSelect() {
  projectSelect.innerHTML =
    '<option value="">Select a project...</option>' +
    projects
      .map((p) => `<option value="${p.id}">${escapeHtml(p.name)}</option>`)
      .join("");
}

function autoMatchProject() {
  if (!currentTabUrl) return;

  // Try to match by URL hostname
  let hostname;
  try {
    hostname = new URL(currentTabUrl).hostname;
  } catch {
    return;
  }

  // Look for a project whose name matches the hostname
  const match = projects.find((p) => {
    const name = p.name.toLowerCase();
    return (
      name === hostname.toLowerCase() ||
      hostname.toLowerCase().includes(name.replace(/\s+/g, "")) ||
      name.includes(hostname.replace("www.", "").split(".")[0])
    );
  });

  if (match) {
    projectSelect.value = match.id;
    urlMatchEl.textContent = `Matched to "${match.name}" based on current URL`;
    urlMatchEl.classList.add("url-match--visible");
    updateCaptureButton();
  }
}

// ── Auth ──

loginBtn.addEventListener("click", async () => {
  loginBtn.disabled = true;
  loginBtn.textContent = "Signing in...";

  try {
    await chrome.runtime.sendMessage({ action: "login" });
    // Re-init after login
    await init();
  } catch (err) {
    loginBtn.disabled = false;
    loginBtn.textContent = "Sign in to Screenote";
    showStatus("error", err.message || "Sign in failed. Please try again.");
  }
});

logoutBtn.addEventListener("click", async () => {
  await chrome.runtime.sendMessage({ action: "logout" });
  showScreen("auth");
});

// ── Project selector ──

projectSelect.addEventListener("change", () => {
  urlMatchEl.classList.remove("url-match--visible");
  updateCaptureButton();
});

function updateCaptureButton() {
  captureBtn.disabled = !projectSelect.value;
}

// ── New project ──

showNewProjectBtn.addEventListener("click", () => {
  newProjectForm.classList.add("new-project--visible");
  newProjectNameInput.focus();

  // Pre-fill with hostname
  if (currentTabUrl) {
    try {
      const hostname = new URL(currentTabUrl).hostname.replace("www.", "");
      newProjectNameInput.value = hostname;
      newProjectNameInput.select();
    } catch {
      // ignore
    }
  }
});

createProjectBtn.addEventListener("click", async () => {
  const name = newProjectNameInput.value.trim();
  if (!name) {
    newProjectNameInput.focus();
    return;
  }

  createProjectBtn.disabled = true;
  createProjectBtn.textContent = "Creating...";

  try {
    const project = await apiFetch("/api/v1/projects", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name }),
    });

    projects.push(project);
    renderProjectSelect();
    projectSelect.value = project.id;
    newProjectForm.classList.remove("new-project--visible");
    newProjectNameInput.value = "";
    updateCaptureButton();
    showStatus("success", `Project "${name}" created`);
  } catch (err) {
    showStatus("error", "Failed to create project");
  } finally {
    createProjectBtn.disabled = false;
    createProjectBtn.textContent = "Create";
  }
});

newProjectNameInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter") {
    e.preventDefault();
    createProjectBtn.click();
  }
  if (e.key === "Escape") {
    newProjectForm.classList.remove("new-project--visible");
  }
});

// ── Capture & Annotate ──

captureBtn.addEventListener("click", async () => {
  const projectId = projectSelect.value;
  if (!projectId) return;

  captureBtn.disabled = true;
  captureBtn.textContent = "Capturing...";
  clearStatus();

  try {
    // 1. Capture screenshot
    const { dataUrl, error: captureError } = await chrome.runtime.sendMessage({
      action: "captureScreenshot",
    });

    if (captureError) throw new Error(captureError);

    captureBtn.textContent = "Uploading...";

    // 2. Generate title from tab info
    const [tab] = await chrome.tabs.query({
      active: true,
      currentWindow: true,
    });
    const title = tab?.title || "Screenshot";

    // 3. Upload to Screenote
    const result = await chrome.runtime.sendMessage({
      action: "captureAndUpload",
      projectId,
      title,
    });

    if (result.error) throw new Error(result.error);

    captureBtn.textContent = "Opening overlay...";

    // 4. Activate annotation overlay on the page
    await chrome.runtime.sendMessage({
      action: "startAnnotating",
      projectId,
      screenshotId: result.id,
      screenshotDataUrl: dataUrl,
    });

    showStatus("success", "Screenshot captured! Annotate on the page.");

    // Close popup so user can interact with the overlay
    window.close();
  } catch (err) {
    showStatus("error", err.message || "Failed to capture screenshot");
    captureBtn.disabled = false;
    captureBtn.textContent = "Capture & Annotate";
  }
});

// ── Helpers ──

function escapeHtml(str) {
  const div = document.createElement("div");
  div.textContent = str;
  return div.innerHTML;
}

// ── Start ──
init();
