import { SCREENOTE_ORIGIN } from "./config.js";

/**
 * Screenote API client.
 * All methods assume an OAuth access token is stored in chrome.storage.local.
 */

async function getToken() {
  const { access_token } = await chrome.storage.local.get("access_token");
  return access_token;
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

  if (response.status === 401) {
    // Token expired — try refresh
    const refreshed = await refreshToken();
    if (refreshed) {
      headers.Authorization = `Bearer ${refreshed}`;
      const retry = await fetch(url, { ...options, headers });
      if (!retry.ok) throw new ApiError(retry.status, await retry.text());
      return retry.json();
    }
    throw new ApiError(401, "Authentication expired. Please sign in again.");
  }

  if (!response.ok) {
    const body = await response.text();
    throw new ApiError(response.status, body);
  }

  return response.json();
}

async function refreshToken() {
  const stored = await chrome.storage.local.get([
    "refresh_token",
    "client_id",
  ]);
  if (!stored.refresh_token || !stored.client_id) return null;

  const body = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: stored.refresh_token,
    client_id: stored.client_id,
  });

  const response = await fetch(`${SCREENOTE_ORIGIN}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body,
  });

  if (!response.ok) return null;

  const data = await response.json();
  await chrome.storage.local.set({
    access_token: data.access_token,
    refresh_token: data.refresh_token,
  });

  return data.access_token;
}

class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

// ── Public API ──

export async function getMe() {
  return apiFetch("/api/v1/me");
}

export async function getProjects() {
  return apiFetch("/api/v1/projects");
}

export async function createProject(name) {
  return apiFetch("/api/v1/projects", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ name }),
  });
}

export async function getScreenshots(projectId) {
  return apiFetch(`/api/v1/projects/${projectId}/screenshots`);
}

export async function createScreenshot(projectId, title, imageBlob) {
  const formData = new FormData();
  formData.append("title", title);
  formData.append("image", imageBlob, "screenshot.png");

  return apiFetch(`/api/v1/projects/${projectId}/screenshots`, {
    method: "POST",
    body: formData,
  });
}

export async function getAnnotations(projectId, screenshotId) {
  return apiFetch(
    `/api/v1/projects/${projectId}/screenshots/${screenshotId}/annotations`
  );
}

export async function createAnnotation(
  projectId,
  screenshotId,
  { x_percent, y_percent, width_percent, height_percent, comment }
) {
  return apiFetch(
    `/api/v1/projects/${projectId}/screenshots/${screenshotId}/annotations`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        x_percent,
        y_percent,
        width_percent,
        height_percent,
        comment,
      }),
    }
  );
}

export async function updateAnnotation(
  projectId,
  screenshotId,
  annotationId,
  fields
) {
  return apiFetch(
    `/api/v1/projects/${projectId}/screenshots/${screenshotId}/annotations/${annotationId}`,
    {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(fields),
    }
  );
}
