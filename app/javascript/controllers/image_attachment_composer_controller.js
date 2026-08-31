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
    acceptedTypes: Array,
    unsupportedTypeMessage: String
  }

  // A hung upload must not block the post forever, and 20MB has to fit over a
  // slow connection, so the ceiling is generous rather than tight.
  static UPLOAD_TIMEOUT = 180000

  // Every other draft call — batch create, alt text, remove, and the post
  // itself — carries the same kind of ceiling. A hung claim must not leave the
  // composer frozen with its submit button disabled.
  static REQUEST_TIMEOUT = 60000
  static RESUME_POLL_INTERVAL = 500
  static RESUME_POLL_LIMIT = 20

  connect() {
    this.connectionToken = (this.connectionToken || 0) + 1
    const connectionToken = this.connectionToken
    this.disconnected = false
    this.items = new Map()
    this.pendingBatchRequest = null
    // One key per mounted composer, stable across retries of the create call.
    this.batchClientKey ||= `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 12)}`
    this.submitting = false
    this.navigating = false
    this.resuming = false
    this.resumeFailed = false
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

    this.batchField = this.form.querySelector("[data-image-attachment-batch-field]") ||
      this.form.querySelector('input[name="image_attachment_batch_id"]')
    if (!this.batchField) {
      this.batchField = document.createElement("input")
      this.batchField.type = "hidden"
      this.batchField.name = "image_attachment_batch_id"
      this.batchField.dataset.imageAttachmentBatchField = "true"
      this.form.appendChild(this.batchField)
    }

    this.batchId = this.batchField.value || null
    this.batchUrls = this.batchId ? this.urlsForBatch(this.batchId) : null
    this.itemsTarget.replaceChildren()
    if (this.batchId) {
      this.resuming = true
      this.resumeBatch(connectionToken)
    }

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
    this.items.forEach(item => {
      item.request?.abort()
      this.releasePreview(item)
    })
    clearTimeout(this.resumeTimer)
    // Anything still in flight belongs to the connection being torn down.
    this.pendingBatchRequest = null
    this.connectionToken += 1
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
      this.showError(this.unsupportedTypeMessage)
      return
    }
    if (images.length < Array.from(event.dataTransfer?.files || []).length) {
      this.showError(`Some files were skipped. ${this.unsupportedTypeMessage}`)
    }

    this.enqueue(images)
  }

  onPaste(event) {
    const images = this.imageFilesFrom(event.clipboardData)
    const files = Array.from(event.clipboardData?.files || [])
    if (images.length === 0) {
      if (files.length > 0) this.showError(this.unsupportedTypeMessage)
      return
    }
    if (images.length < files.length) {
      this.showError(`Some files were skipped. ${this.unsupportedTypeMessage}`)
    }

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
    return Array.from(transfer?.files || []).filter(file => this.acceptedFile(file))
  }

  // An extensionless PNG, JPEG, or WebP reaches the page with an empty
  // `File.type`: the browser derives that string from the name, not the bytes.
  // Refusing it here would reject a file the server accepts, so an undeclared
  // type is passed through and the byte sniffing on the other end decides.
  acceptedFile(file) {
    return !file.type || this.acceptedTypesValue.includes(file.type)
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
    // Resume rebuilds the rail from the server on every poll tick, so a file
    // added mid-settle would be dropped from `this.items` and orphaned.
    if (this.resuming) {
      this.showError("Wait for the interrupted upload to finish settling.")
      return
    }

    const images = files.filter(file => this.acceptedFile(file))
    if (images.length < files.length) {
      this.showError(this.unsupportedTypeMessage)
    }
    if (images.length === 0) return

    const room = this.maxFilesValue - this.items.size
    if (room <= 0) {
      this.showError(`You can attach up to ${this.maxFilesValue} images.`)
      return
    }

    const accepted = images.slice(0, room)
    if (accepted.length < images.length) {
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
    return Array.from(this.items.values()).reduce((sum, item) => sum + (item.size || 0), 0)
  }

  createItem(file) {
    const clientKey = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`
    // The picked bytes are already in memory, so the rail thumbnail is painted
    // from them. Asking the server for the original would pull the whole
    // upload — up to 50MB per message — back through the app, uncached, only
    // to draw a thumbnail, and drafts are never allowed to warm a variant.
    const objectUrl = URL.createObjectURL(file)
    return this.appendItem({
      clientKey,
      file,
      size: file.size,
      state: "uploading",
      serverId: null,
      objectUrl,
      previewUrl: objectUrl,
      savedAltText: "",
      failure: null
    })
  }

  restoreItem(row) {
    return this.appendItem({
      clientKey: row.client_key,
      file: null,
      size: row.size || 0,
      state: row.state,
      serverId: row.id,
      // A resumed row has no local File, so its preview is the protected
      // server path.
      objectUrl: null,
      previewUrl: row.preview_url,
      savedAltText: row.alt_text || "",
      failure: row.failure
    })
  }

  appendItem(attributes) {
    const element = this.itemTemplateTarget.content.firstElementChild.cloneNode(true)
    const item = {
      ...attributes,
      element,
      request: null,
      removed: false,
      altInput: element.querySelector("[data-attachment-alt]"),
      altRequest: null,
      removalFailed: false
    }

    element.dataset.clientKey = item.clientKey
    element.querySelector("[data-attachment-remove]").addEventListener("click", () => this.remove(item))
    element.querySelector("[data-attachment-retry]").addEventListener("click", () => this.upload(item))
    item.altInput.addEventListener("change", event => {
      this.saveAltText(item, event.target.value)
    })

    this.itemsTarget.appendChild(element)
    item.altInput.value = item.savedAltText
    this.items.set(item.clientKey, item)
    this.renderItem(item)
    this.refreshSubmitState()
    this.notifyLayoutChanged()

    return item
  }

  async resumeBatch(connectionToken, attempt = 0) {
    try {
      const response = await this.request(this.batchUrls.batchUrl)
      const payload = await response.json().catch(() => ({}))
      if (!this.connectedFor(connectionToken)) return
      // The server refuses to resume a batch it has expired or already claimed.
      // Those drafts are gone, not broken: the composer drops the stale handle
      // and carries on with an empty rail rather than blocking the post.
      if (response.status === 404 || payload.error?.code === "batch_unusable") {
        this.discardStaleBatch()
        return
      }
      if (!response.ok) throw new Error(payload.error?.message || "The upload session could not be restored.")

      this.items.forEach(item => this.releasePreview(item))
      this.items.clear()
      this.itemsTarget.replaceChildren()
      for (const row of payload.attachments || []) this.restoreItem(row)

      const pending = Array.from(this.items.values()).some(item => item.state === "uploading")
      if (pending && attempt < this.constructor.RESUME_POLL_LIMIT) {
        this.resumeTimer = setTimeout(
          () => this.resumeBatch(connectionToken, attempt + 1),
          this.constructor.RESUME_POLL_INTERVAL
        )
        return
      }

      this.resuming = false
      this.resumeFailed = pending
      if (pending) this.showError("An interrupted upload is still settling. Reload and try again.")
      this.items.forEach(item => this.renderItem(item))
      this.refreshSubmitState()
      this.notifyLayoutChanged()
    } catch (error) {
      if (!this.connectedFor(connectionToken)) return

      this.resuming = false
      this.resumeFailed = true
      this.showError(error.message || "The upload session could not be restored.")
      this.refreshSubmitState()
    }
  }

  discardStaleBatch() {
    this.items.forEach(item => this.releasePreview(item))
    this.items.clear()
    this.itemsTarget.replaceChildren()
    this.batchId = null
    this.batchUrls = null
    if (this.batchField) this.batchField.value = ""
    this.resuming = false
    this.resumeFailed = false
    this.refreshSubmitState()
    this.notifyLayoutChanged()
  }

  connectedFor(connectionToken) {
    return !this.disconnected && this.connectionToken === connectionToken
  }

  async upload(item) {
    if (this.disconnected) return
    if (this.submitting) {
      this.showError("Wait for the message to finish posting.")
      return
    }

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

      this.failItem(item, error.message, error.retryable !== false)
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
      if (!item.objectUrl) item.previewUrl = payload.attachment.preview_url
      item.failure = payload.attachment.failure
      this.renderItem(item)
      this.notifyLayoutChanged()
      this.announce(`${this.itemLabel(item)} uploaded.`)
    } catch (error) {
      if (this.superseded(item, attempt)) return

      this.failItem(item, error.message, error.retryable !== false)
    } finally {
      if (item.attempt === attempt) {
        item.request = null
        this.refreshSubmitState()
      }
    }
  }

  releasePreview(item) {
    if (!item.objectUrl) return

    URL.revokeObjectURL(item.objectUrl)
    item.objectUrl = null
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
          reject(this.requestError(
            payload.error?.message || "The upload did not finish. Retry it.",
            typeof payload.error?.retryable === "boolean" ? payload.error.retryable : request.status >= 500
          ))
        }
      })
      request.addEventListener("error", () => reject(this.requestError("The upload did not finish. Retry it.")))
      request.addEventListener("timeout", () => reject(this.requestError("The upload timed out. Retry it.")))
      request.addEventListener("abort", () => reject(this.requestError("Upload cancelled.")))
      request.send(body)
    })
  }

  async ensureBatch() {
    if (this.batchUrls) return this.batchUrls
    if (this.disconnected) throw new Error("Uploads are unavailable right now.")

    this.pendingBatchRequest ||= this.requestBatch(this.connectionToken)
    try {
      return await this.pendingBatchRequest
    } finally {
      this.pendingBatchRequest = null
    }
  }

  // The batch this controller opens belongs to this connection. A response that
  // arrives after a disconnect and reconnect describes a controller that no
  // longer exists, so it must not overwrite the reconnected one's batch and
  // send its uploads somewhere the rail cannot show them.
  async requestBatch(connectionToken) {
    const response = await this.request(this.batchesUrlValue, {
      method: "POST",
      // The composer's own idempotency key. A create whose response is lost is
      // retried with the same key and resumes the batch it already opened
      // rather than spending another of the account's open-batch allowance.
      body: JSON.stringify({ project_id: this.projectIdValue, client_key: this.batchClientKey })
    })
    if (!this.connectedFor(connectionToken)) throw new Error("Uploads are unavailable right now.")
    const payload = await response.json().catch(() => ({}))
    if (!response.ok) {
      throw this.requestError(
        payload.error?.message || "Uploads are unavailable right now.",
        typeof payload.error?.retryable === "boolean" ? payload.error.retryable : response.status >= 500
      )
    }

    if (!this.connectedFor(connectionToken)) throw new Error("Uploads are unavailable right now.")

    this.batchId = payload.batch_id
    this.batchField.value = payload.batch_id
    this.batchUrls = this.urlsForBatch(payload.batch_id)

    return this.batchUrls
  }

  async remove(item) {
    if (this.submitting) {
      this.showError("Wait for the message to finish posting.")
      return
    }
    // The next resume tick would rebuild this row from the server anyway, so a
    // removal accepted mid-settle could leave an untracked ghost behind.
    if (this.resuming) {
      this.showError("Wait for the interrupted upload to finish settling.")
      return
    }

    item.removed = true
    item.request?.abort()
    item.attempt = (item.attempt || 0) + 1
    item.state = "removing"
    item.failure = null
    item.removalFailed = false
    this.renderItem(item)
    this.refreshSubmitState()

    try {
      await this.ensureBatch()
      await this.discardServerAttachment(item)

      item.element.remove()
      this.items.delete(item.clientKey)
      this.releasePreview(item)
      this.announce("Image removed.")
      this.refreshSubmitState()
      this.notifyLayoutChanged()
    } catch {
      item.removed = false
      item.removalFailed = true
      item.state = "failed"
      item.failure = { message: "The image could not be removed. Try Remove again.", retryable: false }
      this.renderItem(item)
      this.showError(item.failure.message)
      this.refreshSubmitState()
    }
  }

  // The client key exists before the numeric row ID. DELETE reserves it as a
  // tombstone, so it is safe whether the upload is pending, ready, failed, or
  // has not created its row yet. The item stays visible if delivery fails; a
  // silent local removal could otherwise let a ghost row reach claim.
  async discardServerAttachment(item) {
    if (!this.batchUrls) throw new Error("The upload session is unavailable.")

    const response = await this.request(`${this.batchUrls.attachmentsUrl}/discard`, {
      method: "DELETE",
      body: JSON.stringify({ client_key: item.clientKey })
    })
    if (!response.ok) throw new Error("The image could not be removed.")
  }

  // The typed description is part of the message, so a write is a tracked
  // promise the post waits on — and a rejected response is a failure, which a
  // bare `fetch` would otherwise report as success.
  saveAltText(item, value) {
    if (!item.serverId || !this.batchUrls) return Promise.resolve(true)
    if (value === item.savedAltText && !item.altRequest) return Promise.resolve(true)

    // Chain writes per item. A blur PATCH for value A must not finish after the
    // submit-time flush for value B and overwrite B on the server.
    const prior = item.altRequest || Promise.resolve(true)
    const write = prior.catch(() => false).then(async () => {
      if (value === item.savedAltText) return true

      try {
        const response = await this.request(`${this.batchUrls.attachmentsUrl}/${item.serverId}`, {
          method: "PATCH",
          body: JSON.stringify({ image_attachment: { alt_text: value } })
        })
        if (!response.ok) throw new Error("the description was rejected")

        item.savedAltText = value
        return true
      } catch {
        if (!item.removed) this.showError("The description could not be saved. Try again.")
        return false
      }
    })

    const tracked = write.finally(() => {
      if (item.altRequest === tracked) item.altRequest = null
    })
    item.altRequest = tracked
    return tracked
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
    if (this.submitting || this.navigating) return
    if (!this.readyToSubmit()) {
      this.showError("Wait for every image to finish uploading.")
      return
    }

    this.submitting = true
    this.refreshSubmitState()
    this.clearError()

    // Cancelling the overlay mid-post tears the form out from under us, so the
    // navigation target is captured while it is still attached.
    const frame = this.form.closest("turbo-frame")
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), this.constructor.REQUEST_TIMEOUT)

    try {
      // Descriptions are flushed before the claim, because a claim moves the
      // rows off the batch and every later write is a 404 against them.
      if (!(await this.flushAltText())) return

      // The fields are read after that wait, not before it. A description write
      // can take a while, the textarea and the coordinate inputs stay editable
      // throughout, and a snapshot taken first would post an older message than
      // the one still visible on screen.
      const body = new FormData(this.form)
      if (this.batchId) body.set("image_attachment_batch_id", this.batchId)

      const response = await fetch(this.form.action, {
        method: this.form.method || "POST",
        body,
        credentials: "same-origin",
        signal: controller.signal,
        headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken }
      })
      const payload = await response.json().catch(() => ({}))

      if (response.ok) {
        // Turbo navigation is asynchronous and this form is still mounted while
        // it runs. Clearing the batch and re-enabling submit here would let a
        // second click post the same message again — this time with no batch at
        // all, so the duplicate would carry no images. The composer therefore
        // stays locked until the page it is on has been replaced.
        this.navigating = true
        this.navigateAfterSubmit(payload.redirect_url, frame)
        return
      }

      this.restoreFrom(payload)
    } catch {
      this.showError("The message could not be posted. Try again.")
    } finally {
      clearTimeout(timer)
      if (!this.navigating) {
        this.submitting = false
        this.refreshSubmitState()
      }
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
    const form = payload.form || {}
    const batchId = form.image_attachment_batch_id
    if (batchId) {
      this.batchId = batchId
      this.batchUrls ||= this.urlsForBatch(batchId)
      if (this.batchField) this.batchField.value = batchId
    }

    // The server echoes the editable half of what it rejected, so a composer
    // that was remounted between the post and its answer still comes back with
    // the message and, for the overlay, the region that was selected.
    this.restoreField("textarea", form.body)
    this.restoreField('[name="annotation[x_percent]"]', form.x_percent)
    this.restoreField('[name="annotation[y_percent]"]', form.y_percent)
    this.restoreField('[name="annotation[width_percent]"]', form.width_percent)
    this.restoreField('[name="annotation[height_percent]"]', form.height_percent)
    this.restoreField('[name="annotation[viewport]"]', form.viewport)

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

  restoreField(selector, value) {
    if (value === undefined || value === null) return

    const field = this.form?.querySelector(selector)
    if (field && !field.value) field.value = value
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

  urlsForBatch(batchId) {
    return {
      batchUrl: `${this.batchesUrlValue}/${batchId}`,
      attachmentsUrl: `${this.batchesUrlValue}/${batchId}/attachments`
    }
  }

  requestError(message, retryable = true) {
    const error = new Error(message)
    error.retryable = retryable
    return error
  }

  failItem(item, message, retryable = true) {
    item.state = "failed"
    item.failure = { message, retryable }
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
    retry.hidden = item.state !== "failed" || !item.file || item.failure?.retryable !== true || item.removalFailed
    alt.disabled = this.resuming || item.state !== "ready"

    if (item.state === "uploading") {
      state.textContent = `Uploading ${item.progress || 0}%`
    } else if (item.state === "failed") {
      state.textContent = item.failure?.message || "Upload failed."
    } else if (item.state === "removing") {
      state.textContent = "Removing…"
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
    return !this.resuming && !this.resumeFailed &&
      Array.from(this.items.values()).every(item => item.state === "ready")
  }

  refreshSubmitState() {
    const blocked = this.submitting || this.navigating || !this.readyToSubmit()
    this.form?.querySelectorAll("input[type=submit], button[type=submit]").forEach(button => {
      button.disabled = blocked
    })
    this.items.forEach(item => {
      item.altInput.disabled = this.submitting || this.resuming || item.state !== "ready"
      item.element.querySelector("[data-attachment-remove]").disabled =
        this.submitting || this.resuming || item.state === "removing"
      item.element.querySelector("[data-attachment-retry]").disabled = this.submitting
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

  // The server owns this copy: it is handed down from the same constant the
  // upload endpoint raises with, so the two can never drift.
  get unsupportedTypeMessage() {
    return this.unsupportedTypeMessageValue || "That file type cannot be attached."
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content || ""
  }
}
