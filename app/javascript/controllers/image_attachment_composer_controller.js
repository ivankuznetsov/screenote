import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// One state machine for every native composer: the cloned Annotorious overlay
// form and each reply/reopen disclosure. The controller owns a single
// server-side draft batch, uploads each file immediately, and blocks the post
// until every persisted row is ready.
export default class extends Controller {
  static targets = ["fileInput", "items", "itemTemplate", "status", "errors"]
  static values = {
    projectId: Number,
    batchesUrl: String,
    maxFiles: Number,
    maxFileSize: Number,
    maxTotalSize: Number,
    acceptedTypes: Array
  }

  // A hung upload must not block the post forever, and 20MB has to fit over a
  // slow connection, so the ceiling is generous rather than tight.
  static UPLOAD_TIMEOUT = 180000

  connect() {
    this.disconnected = false
    this.items = new Map()
    this.batchId = null
    this.batchUrls = null
    this.pendingBatchRequest = null
    this.submitting = false
    this.form = this.element.closest("form")
    if (!this.form) return

    // Bind drop and paste to the composer form only. The screenshot canvas
    // keeps its Annotorious drag behavior, and a text-only paste stays text.
    this.onSubmit = this.onSubmit.bind(this)
    this.onDragOver = this.onDragOver.bind(this)
    this.onDragLeave = this.onDragLeave.bind(this)
    this.onDrop = this.onDrop.bind(this)
    this.onPaste = this.onPaste.bind(this)

    this.form.addEventListener("submit", this.onSubmit)
    this.form.addEventListener("dragover", this.onDragOver)
    this.form.addEventListener("dragleave", this.onDragLeave)
    this.form.addEventListener("drop", this.onDrop)
    this.form.addEventListener("paste", this.onPaste)

    this.batchField = document.createElement("input")
    this.batchField.type = "hidden"
    this.batchField.name = "image_attachment_batch_id"
    this.form.appendChild(this.batchField)

    this.refreshSubmitState()
  }

  disconnect() {
    this.disconnected = true
    if (!this.form) return

    this.form.removeEventListener("submit", this.onSubmit)
    this.form.removeEventListener("dragover", this.onDragOver)
    this.form.removeEventListener("dragleave", this.onDragLeave)
    this.form.removeEventListener("drop", this.onDrop)
    this.form.removeEventListener("paste", this.onPaste)
    this.batchField?.remove()
    this.items.forEach(item => item.request?.abort())
    this.items.clear()
    // A disconnect is only a client going away. Committed drafts stay on the
    // server until their 24 hour expiry.
    this.form = null
  }

  openPicker() {
    this.fileInputTarget.click()
  }

  pickFiles(event) {
    this.enqueue(Array.from(event.target.files || []))
    event.target.value = ""
  }

  onDragOver(event) {
    if (!this.hasImageFiles(event.dataTransfer)) return

    event.preventDefault()
    this.element.classList.add("image-attachment-composer--dropping")
  }

  onDragLeave() {
    this.element.classList.remove("image-attachment-composer--dropping")
  }

  onDrop(event) {
    if (!this.hasImageFiles(event.dataTransfer)) return

    event.preventDefault()
    this.element.classList.remove("image-attachment-composer--dropping")
    this.enqueue(this.imageFilesFrom(event.dataTransfer))
  }

  onPaste(event) {
    const images = this.imageFilesFrom(event.clipboardData)
    if (images.length === 0) return

    // Mixed clipboard content keeps its text: only the image half is consumed
    // here, so the browser still inserts whatever text came with it.
    const hasText = Array.from(event.clipboardData?.types || []).includes("text/plain")
    if (!hasText) event.preventDefault()
    this.enqueue(images)
  }

  hasImageFiles(transfer) {
    return Array.from(transfer?.types || []).includes("Files") && this.imageFilesFrom(transfer).length > 0
  }

  imageFilesFrom(transfer) {
    return Array.from(transfer?.files || []).filter(file => this.acceptedTypesValue.includes(file.type))
  }

  async enqueue(files) {
    if (files.length === 0) return
    // A file added while the post is in flight would reach the server after
    // the claim and leave the batch unready, so the composer is frozen until
    // the submission settles.
    if (this.submitting) {
      this.showError("Wait for the message to finish posting.")
      return
    }

    const room = this.maxFilesValue - this.items.size
    if (room <= 0) {
      this.showError(`You can attach up to ${this.maxFilesValue} images.`)
      return
    }

    const accepted = files.slice(0, room)
    if (accepted.length < files.length) {
      this.showError(`You can attach up to ${this.maxFilesValue} images.`)
    }

    let total = this.totalBytes()
    for (const file of accepted) {
      if (file.size > this.maxFileSizeValue) {
        this.showError(`Each image must be ${Math.round(this.maxFileSizeValue / 1048576)}MB or smaller.`)
        continue
      }

      // The server enforces the same per-message total on commit; refusing the
      // file here means nothing is uploaded only to be rejected afterwards.
      if (total + file.size > this.maxTotalSizeValue) {
        this.showError(
          `Attachments for one message can total at most ${Math.round(this.maxTotalSizeValue / 1048576)}MB.`
        )
        break
      }

      total += file.size
      const item = this.createItem(file)
      await this.upload(item)
    }
  }

  totalBytes() {
    return Array.from(this.items.values()).reduce((sum, item) => sum + (item.file?.size || 0), 0)
  }

  createItem(file) {
    const clientKey = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
    const element = this.itemTemplateTarget.content.firstElementChild.cloneNode(true)
    const item = {
      clientKey,
      file,
      element,
      state: "uploading",
      serverId: null,
      previewUrl: null,
      request: null
    }

    element.dataset.clientKey = clientKey
    element.querySelector("[data-attachment-remove]").addEventListener("click", () => this.remove(item))
    element.querySelector("[data-attachment-retry]").addEventListener("click", () => this.upload(item))
    element.querySelector("[data-attachment-alt]").addEventListener("change", event => {
      this.saveAltText(item, event.target.value)
    })

    this.itemsTarget.appendChild(element)
    this.items.set(clientKey, item)
    this.renderItem(item)
    this.refreshSubmitState()
    this.notifyLayoutChanged()

    return item
  }

  async upload(item) {
    if (this.disconnected) return

    // Retrying supersedes whatever is still in flight for this row: the older
    // attempt is aborted, and its rejection is then ignored so it cannot
    // overwrite the state the new attempt is about to write.
    item.request?.abort()
    const attempt = (item.attempt || 0) + 1
    item.attempt = attempt

    item.state = "uploading"
    item.failure = null
    item.progress = 0
    this.renderItem(item)
    this.refreshSubmitState()

    let batch
    try {
      batch = await this.ensureBatch()
    } catch (error) {
      if (this.superseded(item, attempt)) return

      this.failItem(item, error.message)
      return
    }
    if (this.superseded(item, attempt)) return

    const body = new FormData()
    body.append("client_key", item.clientKey)
    body.append("file", item.file)

    try {
      const payload = await this.uploadWithProgress(`${batch.attachmentsUrl}`, body, item)
      if (this.superseded(item, attempt)) return

      item.serverId = payload.attachment.id
      item.state = payload.attachment.state
      item.previewUrl = payload.attachment.preview_url
      item.failure = payload.attachment.failure
      this.renderItem(item)
      this.notifyLayoutChanged()
      this.announce(`${this.itemLabel(item)} uploaded.`)
    } catch (error) {
      if (this.superseded(item, attempt)) return

      this.failItem(item, error.message)
    } finally {
      if (item.attempt === attempt) {
        item.request = null
        this.refreshSubmitState()
      }
    }
  }

  superseded(item, attempt) {
    return this.disconnected || item.attempt !== attempt
  }

  uploadWithProgress(url, body, item) {
    return new Promise((resolve, reject) => {
      const request = new XMLHttpRequest()
      item.request = request
      request.open("POST", url)
      request.timeout = this.constructor.UPLOAD_TIMEOUT
      request.setRequestHeader("Accept", "application/json")
      request.setRequestHeader("X-CSRF-Token", this.csrfToken)
      request.upload.addEventListener("progress", event => {
        if (!event.lengthComputable) return

        item.progress = Math.round((event.loaded / event.total) * 100)
        this.renderItem(item)
      })
      request.addEventListener("load", () => {
        let payload = {}
        try {
          payload = JSON.parse(request.responseText || "{}")
        } catch {
          payload = {}
        }

        if (request.status >= 200 && request.status < 300) {
          resolve(payload)
        } else {
          reject(new Error(payload.error?.message || "The upload did not finish. Retry it."))
        }
      })
      request.addEventListener("error", () => reject(new Error("The upload did not finish. Retry it.")))
      request.addEventListener("timeout", () => reject(new Error("The upload timed out. Retry it.")))
      request.addEventListener("abort", () => reject(new Error("Upload cancelled.")))
      request.send(body)
    })
  }

  async ensureBatch() {
    if (this.batchUrls) return this.batchUrls
    if (this.disconnected) throw new Error("Uploads are unavailable right now.")

    this.pendingBatchRequest ||= this.requestBatch()
    try {
      return await this.pendingBatchRequest
    } finally {
      this.pendingBatchRequest = null
    }
  }

  async requestBatch() {
    const response = await this.request(this.batchesUrlValue, {
      method: "POST",
      body: JSON.stringify({ project_id: this.projectIdValue })
    })
    const payload = await response.json()
    if (!response.ok) throw new Error(payload.error?.message || "Uploads are unavailable right now.")

    this.batchId = payload.batch_id
    this.batchField.value = payload.batch_id
    this.batchUrls = {
      batchUrl: `${this.batchesUrlValue}/${payload.batch_id}`,
      attachmentsUrl: `${this.batchesUrlValue}/${payload.batch_id}/attachments`
    }

    return this.batchUrls
  }

  async remove(item) {
    item.request?.abort()
    item.attempt = (item.attempt || 0) + 1

    const serverId = item.serverId || await this.resolveServerId(item)
    if (serverId && this.batchUrls) {
      try {
        await this.request(`${this.batchUrls.attachmentsUrl}/${serverId}`, { method: "DELETE" })
      } catch {
        // Removal is idempotent server side; a lost response must not strand
        // the row in the composer.
      }
    }

    item.element.remove()
    this.items.delete(item.clientKey)
    this.announce("Image removed.")
    this.refreshSubmitState()
    this.notifyLayoutChanged()
  }

  // The server reserves a row before it reads a byte, so an upload that failed
  // or never answered still holds a slot the composer never learned the ID of.
  // Resolving it by client key is what lets Remove free that slot instead of
  // leaving the batch permanently unready.
  async resolveServerId(item) {
    if (!this.batchUrls) return null

    try {
      const response = await this.request(this.batchUrls.batchUrl)
      if (!response.ok) return null

      const payload = await response.json()
      return payload.attachments?.find(row => row.client_key === item.clientKey)?.id || null
    } catch {
      return null
    }
  }

  async saveAltText(item, value) {
    if (!item.serverId || !this.batchUrls) return

    try {
      await this.request(`${this.batchUrls.attachmentsUrl}/${item.serverId}`, {
        method: "PATCH",
        body: JSON.stringify({ image_attachment: { alt_text: value } })
      })
    } catch {
      this.showError("The description could not be saved. Try again.")
    }
  }

  async onSubmit(event) {
    event.preventDefault()
    if (this.submitting) return
    if (!this.readyToSubmit()) {
      this.showError("Wait for every image to finish uploading.")
      return
    }

    this.submitting = true
    this.refreshSubmitState()
    this.clearError()

    const body = new FormData(this.form)
    if (this.batchId) body.set("image_attachment_batch_id", this.batchId)
    // Cancelling the overlay mid-post tears the form out from under us, so the
    // navigation target is captured while it is still attached.
    const frame = this.form.closest("turbo-frame")

    try {
      const response = await fetch(this.form.action, {
        method: this.form.method || "POST",
        body,
        credentials: "same-origin",
        headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken }
      })
      const payload = await response.json().catch(() => ({}))

      if (response.ok) {
        this.batchId = null
        this.batchUrls = null
        this.navigateAfterSubmit(payload.redirect_url, frame)
        return
      }

      this.restoreFrom(payload)
    } catch {
      this.showError("The message could not be posted. Try again.")
    } finally {
      this.submitting = false
      this.refreshSubmitState()
    }
  }

  // Posting keeps the existing navigation contract. Both composers live inside
  // the workspace Turbo frame, so reloading that frame is what a plain Turbo
  // form submission used to do — and it leaves review state such as fullscreen
  // mode untouched.
  navigateAfterSubmit(url, frame) {
    if (frame && url) {
      frame.src = url
      frame.reload()
      return
    }

    Turbo.visit(url || window.location.href, { action: "replace" })
  }

  // A rejected post keeps the composer mounted: the body, the coordinates, the
  // batch, and every ready row stay exactly where the person left them.
  restoreFrom(payload) {
    const batchId = payload.form?.image_attachment_batch_id
    if (batchId) {
      this.batchId = batchId
      if (this.batchField) this.batchField.value = batchId
    }

    const readyIds = payload.form?.ready_attachment_ids || []
    this.items.forEach(item => {
      if (item.serverId && readyIds.includes(item.serverId)) {
        item.state = "ready"
        this.renderItem(item)
      }
    })

    this.showError((payload.errors || [payload.error?.message]).filter(Boolean).join(" "))
  }

  request(url, options = {}) {
    return fetch(url, {
      credentials: "same-origin",
      ...options,
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken,
        ...(options.headers || {})
      }
    })
  }

  failItem(item, message) {
    item.state = "failed"
    item.failure = { message }
    this.renderItem(item)
    this.announce(`${this.itemLabel(item)} failed. ${message}`)
    this.refreshSubmitState()
  }

  renderItem(item) {
    const element = item.element
    const state = element.querySelector("[data-attachment-state]")
    const progress = element.querySelector("[data-attachment-progress]")
    const retry = element.querySelector("[data-attachment-retry]")
    const thumb = element.querySelector("[data-attachment-thumb]")
    const placeholder = element.querySelector("[data-attachment-placeholder]")
    const alt = element.querySelector("[data-attachment-alt]")

    element.dataset.state = item.state
    element.classList.toggle("image-attachment-item--failed", item.state === "failed")
    progress.value = item.progress || 0
    progress.hidden = item.state !== "uploading"
    retry.hidden = item.state !== "failed"
    alt.disabled = item.state !== "ready"

    if (item.state === "uploading") {
      state.textContent = `Uploading ${item.progress || 0}%`
    } else if (item.state === "failed") {
      state.textContent = item.failure?.message || "Upload failed."
    } else {
      state.textContent = "Ready"
    }

    if (item.previewUrl) {
      thumb.src = item.previewUrl
      thumb.hidden = false
      placeholder.hidden = true
    } else {
      thumb.hidden = true
      placeholder.hidden = false
    }
  }

  readyToSubmit() {
    return Array.from(this.items.values()).every(item => item.state === "ready")
  }

  refreshSubmitState() {
    const blocked = this.submitting || !this.readyToSubmit()
    this.form?.querySelectorAll("input[type=submit], button[type=submit]").forEach(button => {
      button.disabled = blocked
    })
  }

  itemLabel(item) {
    const index = Array.from(this.items.keys()).indexOf(item.clientKey) + 1
    return `Image ${index}`
  }

  // The clamped overlay places itself relative to the selected region, so any
  // height change has to be announced to whoever owns that placement.
  notifyLayoutChanged() {
    this.dispatch("changed", { bubbles: true })
  }

  announce(message) {
    if (this.hasStatusTarget) this.statusTarget.textContent = message
  }

  showError(message) {
    if (!this.hasErrorsTarget || !message) return

    this.errorsTarget.textContent = message
    this.errorsTarget.hidden = false
    this.announce(message)
  }

  clearError() {
    if (!this.hasErrorsTarget) return

    this.errorsTarget.textContent = ""
    this.errorsTarget.hidden = true
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
