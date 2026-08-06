import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["error", "input", "status", "submit"]
  static values = { url: String }

  connect() {
    this.pendingCredential = window.location.hash.slice(1) || null
    this.scrubAddressBar()

    if (this.pendingCredential) this.exchange()
  }

  disconnect() {
    this.pendingCredential = null
  }

  submit(event) {
    event.preventDefault()
    const credential = this.inputTarget.value
    this.inputTarget.value = ""
    if (credential) this.pendingCredential = credential
    this.exchange()
  }

  async exchange() {
    if (!this.pendingCredential) return this.showInvalidError("Enter the manual code to continue.")

    this.submitTarget.disabled = true
    this.statusTarget.textContent = "Verifying…"
    this.hideError()

    try {
      const body = new URLSearchParams({ token: this.pendingCredential })
      const response = await fetch(this.urlValue, {
        method: "POST",
        body,
        credentials: "same-origin",
        redirect: "follow",
        headers: {
          "Accept": "text/html",
          "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']")?.content || ""
        }
      })

      if (response.redirected) {
        this.discardCredential()
        window.location.replace(response.url)
      } else if (response.status === 503) {
        this.showRetryableError("Screenote is temporarily unable to verify this link. Select Retry to try again.")
      } else if (response.status === 429) {
        this.showRetryableError("Too many verification attempts. Wait a moment, then select Retry.")
      } else {
        this.showInvalidError("This authentication link is invalid or has expired.")
      }
    } catch (_error) {
      this.showRetryableError("Screenote could not verify the link. Check your connection, then select Retry.")
    } finally {
      this.submitTarget.disabled = false
    }
  }

  scrubAddressBar() {
    window.history.replaceState(null, "", window.location.pathname)
  }

  hideError() {
    this.errorTarget.hidden = true
    this.errorTarget.textContent = ""
  }

  showInvalidError(message) {
    this.discardCredential()
    this.statusTarget.textContent = ""
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
    this.inputTarget.focus()
  }

  showRetryableError(message) {
    this.statusTarget.textContent = ""
    this.errorTarget.textContent = message
    this.errorTarget.hidden = false
    this.inputTarget.required = false
    this.submitTarget.value = "Retry"
    this.submitTarget.focus()
  }

  discardCredential() {
    this.pendingCredential = null
    this.inputTarget.required = true
    this.submitTarget.value = "Continue"
  }
}
