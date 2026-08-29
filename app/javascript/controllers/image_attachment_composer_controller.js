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

  // Every other draft call — batch create, alt text, remove, and the post
  // itself — carries the same kind of ceiling. A hung claim must not leave the
  // composer frozen with its submit button disabled.
  static REQUEST_TIMEOUT = 60000

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
    this.onCancelled = this.onCancelled.bind(this)

    this.form.addEventListener("submit", this.onSubmit)
    this.form.addEventListener("dragover", this.onDragOver)
    this.form.addEventListener("dragleave", this.onDragLeave)
    this.form.addEventListener("drop", this.onDrop)
    this.form.addEventListener("paste", this.onPaste)
    this.form.addEventListener("annotorious:form-cancelled", this.onCancelled)

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
    this.form.removeEventListener("annotorious:form-cancelled", this.onCancelled)
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
    if (!this.transfersFiles(event.dataTransfer)) return

    // A real OS drag exposes only `types` until the drop itself: `files` stays
    // empty, so dragover can ask whether files are coming and nothing more.
    // Without preventDefault here the browser handles the drop and navigates
    // away to the file.
    event.preventDefault()
    this.element.classList.add("image-attachment-composer--dropping")
  }

  onDragLeave() {
    this.element.classList.remove("image-attachment-composer--dropping")
  }

  onDrop(event) {
    if (!this.transfersFiles(event.dataTransfer)) return

    // The composer claimed this drag on dragover, so it owns the drop even
    // when the dropped files turn out to be unusable.
    event.preventDefault()
    this.element.classList.remove("image-attachment-composer--dropping")

    const images = this.imageFilesFrom(event.dataTransfer)
    if (images.length === 0) {
      this.showError("Attachments must be PNG, JPEG, or WebP images.")
      return
    }

    this.enqueue(images)
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

  transfersFiles(transfer) {
    return Array.from(transfer?.types || []).includes("Files")
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

    // Slots are reserved synchronously, before the first upload is awaited, so
    // an overlapping paste, drop, or picker sees the rows this call already
    // took and the five-file limit holds across all of them.
    let total = this.totalBytes()
    const queued = []
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
      queued.push(this.createItem(file))
    }

    for (const item of queued) await this.upload(item)
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
      request: null,
      removed: false,
      altInput: element.querySelector("[data-attachment-alt]"),
      savedAltText: "",
      altRequest: null
    }

    element.dataset.clientKey = clientKey
    element.querySelector("[data-attachment-remove]").addEventListener("click", () => this.remove(item))
    element.querySelector("[data-attachment-retry]").addEventListener("click", () => this.upload(item))
    item.altInput.addEventListener("change", event => {
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
      if (this.superseded(item, attempt)) {
        // Remove reserves nothing: the server row this attempt created may not
        // have existed when Remove looked for it. A superseded success from a
        // removed item therefore discards its own row rather than leaving a
        // ready draft the claim would silently attach.
        if (item.removed) this.discardServerAttachment(payload.attachment.id)
        return
      }

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
    item.removed = true
    item.request?.abort()
    item.attempt = (item.attempt || 0) + 1

    const serverId = item.serverId || await this.resolveServerId(item)
    if (serverId) await this.discardServerAttachment(serverId)

    item.element.remove()
    this.items.delete(item.clientKey)
    this.announce("Image removed.")
    this.refreshSubmitState()
    this.notifyLayoutChanged()
  }

  // Removal is idempotent server side, and a commit racing it is rejected
  // under the batch lock, so a lost response must not strand the row here.
  async discardServerAttachment(serverId) {
    if (!serverId || !this.batchUrls) return

    try {
      await this.request(`${this.batchUrls.attachmentsUrl}/${serverId}`, { method: "DELETE" })
    } catch {
      // Nothing to recover: the row is already gone from the composer.
    }
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

  // The typed description is part of the message, so a write is a tracked
  // promise the post waits on — and a rejected response is a failure, which a
  // bare `fetch` would otherwise report as success.
  saveAltText(item, value) {
    if (!item.serverId || !this.batchUrls) return Promise.resolve(true)
    if (value === item.savedAltText) return item.altRequest || Promise.resolve(true)

    const write = (async () => {
      try {
        const response = await this.request(`${this.batchUrls.attachmentsUrl}/${item.serverId}`, {
          method: "PATCH",
          body: JSON.stringify({ image_attachment: { alt_text: value } })
        })
        if (!response.ok) throw new Error("the description was rejected")

        item.savedAltText = value
        return true
      } catch {
        this.showError("The description could not be saved. Try again.")
        return false
      }
    })()

    item.altRequest = write
    return write
  }

  // Saving without leaving the description field never fires `change`, and a
  // write started on blur races the claim that moves the row off the batch. The
  // post therefore flushes what is typed and waits for every write to land.
  async flushAltText() {
    const writes = Array.from(this.items.values()).map(item => this.saveAltText(item, item.altInput?.value ?? ""))
    const results = await Promise.all(writes)

    return results.every(Boolean)
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
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), this.constructor.REQUEST_TIMEOUT)

    try {
      // Descriptions are flushed before the claim, because a claim moves the
      // rows off the batch and every later write is a 404 against them.
      if (!(await this.flushAltText())) return

      const response = await fetch(this.form.action, {
        method: this.form.method || "POST",
        body,
        credentials: "same-origin",
        signal: controller.signal,
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
      clearTimeout(timer)
      this.submitting = false
      this.refreshSubmitState()
    }
  }

  // An explicit Annotorious cancel throws the draft away so the per-account
  // open-batch ceiling stays truthful. Ordinary disconnect, navigation, and
  // reconnect still leave the batch for its 24 hour recovery window.
  onCancelled() {
    const batchUrl = this.batchUrls?.batchUrl
    this.items.forEach(item => { item.removed = true })
    this.batchId = null
    this.batchUrls = null
    if (this.batchField) this.batchField.value = ""
    if (!batchUrl) return

    // The composer is torn down in the same tick, so this outlives it.
    fetch(batchUrl, {
      method: "DELETE",
      credentials: "same-origin",
      keepalive: true,
      headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken }
    }).catch(() => {})
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

    // A 500, an HTML error page, or a rejected CSRF token carries no usable
    // message. Falling back keeps a rejected post from looking like nothing
    // happened at all.
    const message = (payload.errors || [payload.error?.message]).filter(Boolean).join(" ")
    this.showError(message || "The message could not be posted. Try again.")
  }

  request(url, options = {}) {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), this.constructor.REQUEST_TIMEOUT)

    return fetch(url, {
      credentials: "same-origin",
      signal: controller.signal,
      ...options,
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-CSRF-Token": this.csrfToken,
        ...(options.headers || {})
      }
    }).finally(() => clearTimeout(timer))
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
