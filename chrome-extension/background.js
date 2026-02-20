import { SCREENOTE_ORIGIN, OAUTH_SCOPES, OAUTH_CLIENT_NAME } from "./shared/config.js";

// ── OAuth helpers ──

function generateCodeVerifier() {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return base64url(array);
}

async function generateCodeChallenge(verifier) {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return base64url(new Uint8Array(digest));
}

function base64url(bytes) {
  let str = "";
  for (const b of bytes) str += String.fromCharCode(b);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function ensureClientRegistered() {
  const stored = await chrome.storage.local.get("client_id");
  if (stored.client_id) return stored.client_id;

  const redirectUri = chrome.identity.getRedirectURL();

  const response = await fetch(`${SCREENOTE_ORIGIN}/oauth/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      client_name: OAUTH_CLIENT_NAME,
      redirect_uris: [redirectUri],
      grant_types: ["authorization_code"],
      token_endpoint_auth_method: "none",
    }),
  });

  if (!response.ok) {
    const err = await response.json();
    throw new Error(err.error_description || "Client registration failed");
  }

  const data = await response.json();
  await chrome.storage.local.set({ client_id: data.client_id });
  return data.client_id;
}

async function startOAuthFlow() {
  const clientId = await ensureClientRegistered();
  const redirectUri = chrome.identity.getRedirectURL();
  const codeVerifier = generateCodeVerifier();
  const codeChallenge = await generateCodeChallenge(codeVerifier);
  const state = base64url(crypto.getRandomValues(new Uint8Array(16)));

  const params = new URLSearchParams({
    response_type: "code",
    client_id: clientId,
    redirect_uri: redirectUri,
    scope: OAUTH_SCOPES,
    code_challenge: codeChallenge,
    code_challenge_method: "S256",
    state,
  });

  const authUrl = `${SCREENOTE_ORIGIN}/oauth/authorize?${params}`;

  const responseUrl = await chrome.identity.launchWebAuthFlow({
    url: authUrl,
    interactive: true,
  });

  const url = new URL(responseUrl);
  const code = url.searchParams.get("code");
  const returnedState = url.searchParams.get("state");

  if (returnedState !== state) {
    throw new Error("OAuth state mismatch");
  }

  if (!code) {
    throw new Error("No authorization code received");
  }

  // Exchange code for token
  const tokenBody = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri,
    client_id: clientId,
    code_verifier: codeVerifier,
  });

  const tokenResponse = await fetch(`${SCREENOTE_ORIGIN}/oauth/token`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: tokenBody,
  });

  if (!tokenResponse.ok) {
    throw new Error("Token exchange failed");
  }

  const tokenData = await tokenResponse.json();

  await chrome.storage.local.set({
    access_token: tokenData.access_token,
    refresh_token: tokenData.refresh_token,
    client_id: clientId,
  });

  return tokenData;
}

async function logout() {
  // Revoke token if possible
  const { access_token, client_id } = await chrome.storage.local.get([
    "access_token",
    "client_id",
  ]);

  if (access_token && client_id) {
    try {
      await fetch(`${SCREENOTE_ORIGIN}/oauth/revoke`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ token: access_token, client_id }),
      });
    } catch {
      // Best-effort revocation
    }
  }

  await chrome.storage.local.remove([
    "access_token",
    "refresh_token",
    "client_id",
  ]);
}

// ── Screenshot capture ──

async function captureScreenshot() {
  const dataUrl = await chrome.tabs.captureVisibleTab(null, {
    format: "png",
  });
  return dataUrl;
}

function dataUrlToBlob(dataUrl) {
  const parts = dataUrl.split(",");
  const mime = parts[0].match(/:(.*?);/)[1];
  const bytes = atob(parts[1]);
  const arr = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    arr[i] = bytes.charCodeAt(i);
  }
  return new Blob([arr], { type: mime });
}

// ── Message handling ──

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  handleMessage(message, sender).then(sendResponse).catch((err) => {
    sendResponse({ error: err.message });
  });
  return true; // keep channel open for async response
});

async function handleMessage(message) {
  switch (message.action) {
    case "login":
      await startOAuthFlow();
      return { success: true };

    case "logout":
      await logout();
      return { success: true };

    case "getAuthStatus": {
      const { access_token } = await chrome.storage.local.get("access_token");
      return { authenticated: !!access_token };
    }

    case "captureScreenshot": {
      const dataUrl = await captureScreenshot();
      return { dataUrl };
    }

    case "captureAndUpload": {
      const dataUrl = await captureScreenshot();
      const blob = dataUrlToBlob(dataUrl);

      // Use the API client via fetch directly (service worker can't import from content context)
      const { access_token } = await chrome.storage.local.get("access_token");
      if (!access_token) throw new Error("Not authenticated");

      const formData = new FormData();
      formData.append("title", message.title || "Untitled");
      formData.append("image", blob, "screenshot.png");

      const response = await fetch(
        `${SCREENOTE_ORIGIN}/api/v1/projects/${message.projectId}/screenshots`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${access_token}` },
          body: formData,
        }
      );

      if (!response.ok) {
        const err = await response.text();
        throw new Error(`Upload failed: ${err}`);
      }

      return await response.json();
    }

    case "startAnnotating": {
      // Send message to content script to activate annotation mode
      const [tab] = await chrome.tabs.query({
        active: true,
        currentWindow: true,
      });
      if (tab) {
        await chrome.tabs.sendMessage(tab.id, {
          action: "activateAnnotation",
          projectId: message.projectId,
          screenshotId: message.screenshotId,
          screenshotDataUrl: message.screenshotDataUrl,
        });
      }
      return { success: true };
    }

    default:
      throw new Error(`Unknown action: ${message.action}`);
  }
}
