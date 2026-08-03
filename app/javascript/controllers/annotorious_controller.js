import { Controller } from "@hotwired/stimulus"
import { createImageAnnotator } from "@annotorious/annotorious"

export default class extends Controller {
  static targets = ["image", "canvas", "formTemplate", "form", "xPercent", "yPercent", "widthPercent", "heightPercent", "comment"]

  connect() {
    if (!this.hasImageTarget) return

    this.disposed = false
    this.handleWindowResize ||= () => this.requestAnnotationFormPosition()
    window.addEventListener("resize", this.handleWindowResize)
    this.handleImageLoad ||= () => {
      if (this.disposed) return

      this.initAnnotorious()
      this.renderExistingPins()
    }

    if (this.imageTarget.complete && this.imageTarget.naturalWidth > 0) {
      this.handleImageLoad()
    } else {
      this.imageTarget.addEventListener("load", this.handleImageLoad, { once: true })
    }
  }

  disconnect() {
    this.disposed = true
    if (this.hasImageTarget && this.handleImageLoad) {
      this.imageTarget.removeEventListener("load", this.handleImageLoad)
    }
    this.releaseBoundaryPointerCapture()
    this.removeBoundaryPointerTracking()
    window.removeEventListener("resize", this.handleWindowResize)
    this.cancelPointAnnotation()
    this.cancelAnnotationFormPosition()
    this.imageWrapperResizeObserver?.disconnect()
    this.imageWrapperResizeObserver = null

    if (this.anno) {
      this.anno.destroy()
      this.anno = null
    }
    this.removePins()
  }

  initAnnotorious() {
    if (this.disposed || this.anno) return

    this.pendingAnnotationId = null

    this.anno = createImageAnnotator(this.imageTarget, {
      drawingEnabled: true,
      drawingMode: "drag"
    })
    this.imageTarget.parentElement?.classList.add("screenshot-canvas__image-wrapper")
    this.observeImageWrapper()
    this.installBoundaryPointerTracking()

    this.anno.on("createAnnotation", (annotation) => {
      this.handleCreate(annotation)
    })

    // Show the form immediately after drawing completes (on selection)
    // rather than waiting for the user to click away to deselect
    this.anno.on("selectionChanged", (annotations) => {
      if (annotations.length === 1 && annotations[0].bodies.length === 0) {
        this.handleCreate(annotations[0])
      }
    })
  }

  handleCreate(annotation) {
    if (this.disposed) return
    if (this.pendingAnnotationId === annotation.id) return

    const selector = annotation.target?.selector
    if (!selector) return

    const coords = this.parseSelector(selector)
    if (!coords) {
      this.anno?.removeAnnotation(annotation.id)
      return
    }

    this.showAnnotationForm(coords, annotation.id)
  }

  parseSelector(selector) {
    // Annotorious v3 returns structured geometry, not W3C media fragment strings
    const geometry = selector.geometry
    if (!geometry) return null

    const naturalW = Number(this.imageTarget.naturalWidth)
    const naturalH = Number(this.imageTarget.naturalHeight)
    const x = Number(geometry.x)
    const y = Number(geometry.y)
    const w = Number(geometry.w)
    const h = Number(geometry.h)
    const values = [naturalW, naturalH, x, y, w, h]

    if (!values.every(Number.isFinite) || naturalW <= 0 || naturalH <= 0) return null

    const clamp = (value, maximum) => Math.min(Math.max(value, 0), maximum)
    const left = clamp(Math.min(x, x + w), naturalW)
    const right = clamp(Math.max(x, x + w), naturalW)
    const top = clamp(Math.min(y, y + h), naturalH)
    const bottom = clamp(Math.max(y, y + h), naturalH)

    if (right <= left || bottom <= top) return null

    const roundPercent = (value, total) => Math.round(((value / total) * 100) * 100) / 100
    const xPercent = roundPercent(left, naturalW)
    const yPercent = roundPercent(top, naturalH)
    const rightPercent = roundPercent(right, naturalW)
    const bottomPercent = roundPercent(bottom, naturalH)
    const wPercent = rightPercent - xPercent
    const hPercent = bottomPercent - yPercent
    const rawWPercent = ((right - left) / naturalW) * 100
    const rawHPercent = ((bottom - top) / naturalH) * 100
    const isPoint = rawWPercent < 1 && rawHPercent < 1

    if (!isPoint && (wPercent <= 0 || hPercent <= 0)) return null

    return {
      x_percent: xPercent,
      y_percent: yPercent,
      width_percent: isPoint ? null : wPercent,
      height_percent: isPoint ? null : hPercent
    }
  }

  installBoundaryPointerTracking() {
    if (!this.hasCanvasTarget || this.boundaryPointerTrackingInstalled) return

    this.handleBoundaryPointerDown ||= this.onBoundaryPointerDown.bind(this)
    this.handleBoundaryPointerEnd ||= this.onBoundaryPointerEnd.bind(this)
    this.handleLostPointerCapture ||= this.onLostPointerCapture.bind(this)

    this.canvasTarget.addEventListener("pointerdown", this.handleBoundaryPointerDown, true)
    this.canvasTarget.addEventListener("pointerup", this.handleBoundaryPointerEnd, true)
    this.canvasTarget.addEventListener("pointercancel", this.handleBoundaryPointerEnd, true)
    this.boundaryPointerTrackingInstalled = true
  }

  removeBoundaryPointerTracking() {
    if (!this.hasCanvasTarget || !this.boundaryPointerTrackingInstalled) return

    this.canvasTarget.removeEventListener("pointerdown", this.handleBoundaryPointerDown, true)
    this.canvasTarget.removeEventListener("pointerup", this.handleBoundaryPointerEnd, true)
    this.canvasTarget.removeEventListener("pointercancel", this.handleBoundaryPointerEnd, true)
    this.boundaryPointerTrackingInstalled = false
  }

  onBoundaryPointerDown(event) {
    if (this.disposed || event.button !== 0 || event.isPrimary === false) return

    const target = event.target
    if (!target || typeof target.setPointerCapture !== "function") return
    if (target.closest?.(".annotation-pin, .annotation-form, .screenshot-fullscreen-toggle, .screenshot-comments-toggle")) return

    this.drawingStart = {
      pointerId: event.pointerId,
      clientX: event.clientX,
      clientY: event.clientY
    }

    this.releaseBoundaryPointerCapture()

    try {
      target.setPointerCapture(event.pointerId)
    } catch {
      return
    }

    this.capturedPointerId = event.pointerId
    this.capturedPointerTarget = target
    target.addEventListener("lostpointercapture", this.handleLostPointerCapture, { once: true })
  }

  onBoundaryPointerEnd(event) {
    if (event.pointerId !== this.capturedPointerId) return

    const drawingStart = this.drawingStart
    this.drawingStart = null
    this.releaseBoundaryPointerCapture()

    if (event.type === "pointerup" && this.isPointGesture(drawingStart, event)) {
      this.schedulePointAnnotation(event.clientX, event.clientY)
    }
  }

  onLostPointerCapture(event) {
    if (event.pointerId !== this.capturedPointerId) return

    this.clearBoundaryPointerCapture()
  }

  releaseBoundaryPointerCapture() {
    const target = this.capturedPointerTarget
    const pointerId = this.capturedPointerId

    this.clearBoundaryPointerCapture()

    if (!target || pointerId == null || typeof target.releasePointerCapture !== "function") return

    try {
      if (typeof target.hasPointerCapture !== "function" || target.hasPointerCapture(pointerId)) {
        target.releasePointerCapture(pointerId)
      }
    } catch {
      // The browser may already have released capture after pointerup.
    }
  }

  clearBoundaryPointerCapture() {
    this.capturedPointerTarget?.removeEventListener("lostpointercapture", this.handleLostPointerCapture)
    this.capturedPointerTarget = null
    this.capturedPointerId = null
  }

  isPointGesture(start, event) {
    if (!start || start.pointerId !== event.pointerId) return false

    return Math.hypot(event.clientX - start.clientX, event.clientY - start.clientY) <= 4
  }

  schedulePointAnnotation(clientX, clientY) {
    const imageRect = this.imageTarget.getBoundingClientRect()
    if (
      clientX < imageRect.left || clientX > imageRect.right ||
      clientY < imageRect.top || clientY > imageRect.bottom
    ) return

    const clampPercent = value => Math.min(Math.max(Math.round(value * 100) / 100, 0), 100)
    const coords = {
      x_percent: clampPercent(((clientX - imageRect.left) / imageRect.width) * 100),
      y_percent: clampPercent(((clientY - imageRect.top) / imageRect.height) * 100),
      width_percent: null,
      height_percent: null
    }

    if (this.pointAnnotationFrame != null) return

    const pendingAnnotationId = this.pendingAnnotationId
    const hadPendingForm = this.hasFormTarget
    this.pointAnnotationFrame = requestAnimationFrame(() => {
      this.pointAnnotationFrame = null
      const pendingStateChanged = this.pendingAnnotationId !== pendingAnnotationId ||
        this.hasFormTarget !== hadPendingForm
      if (this.disposed || pendingStateChanged) return

      this.showAnnotationForm(coords, `point-${Date.now()}`, { local: true })
    })
  }

  cancelPointAnnotation() {
    if (this.pointAnnotationFrame == null) return

    cancelAnimationFrame(this.pointAnnotationFrame)
    this.pointAnnotationFrame = null
  }

  showAnnotationForm(coords, annotationId, { local = false } = {}) {
    if (this.hasFormTarget && this.commentTarget.value.trim() !== "") {
      if (!local) this.anno?.removeAnnotation(annotationId)
      return
    }

    this.cancelForm()
    this.pendingAnnotationId = annotationId
    this.pendingAnnotationLocal = local
    this.pendingCoords = coords

    const template = this.formTemplateTarget
    const clone = template.content.cloneNode(true)
    const pinContainer = this.imageTarget.parentElement || this.canvasTarget

    pinContainer.appendChild(clone)

    this.xPercentTarget.value = coords.x_percent
    this.yPercentTarget.value = coords.y_percent
    this.widthPercentTarget.value = coords.width_percent || ""
    this.heightPercentTarget.value = coords.height_percent || ""
    this.formTarget.style.visibility = "hidden"
    this.formTarget.dataset.needsFocus = "true"
    this.renderDraftPin(coords)
    this.requestAnnotationFormPosition()
  }

  cancelForm() {
    if (this.hasFormTarget) {
      this.formTarget.remove()
    }
    if (this.pendingAnnotationId && this.anno && !this.pendingAnnotationLocal) {
      this.anno.removeAnnotation(this.pendingAnnotationId)
    }
    this.removeDraftPin()
    this.cancelAnnotationFormPosition()
    this.pendingAnnotationId = null
    this.pendingAnnotationLocal = false
    this.pendingCoords = null
  }

  renderExistingPins() {
    this.removePins()

    if (!this.hasCanvasTarget) return

    const pinContainer = this.imageTarget.parentElement || this.canvasTarget
    const annotations = this.element.querySelectorAll(".annotation-item")
    annotations.forEach((item) => {
      const pin = this.createPin(item.dataset)
      if (pin) pinContainer.appendChild(pin)
    })
  }

  createPin(pinData, { draft = false } = {}) {
    const xPercent = pinData.xPercent
    const yPercent = pinData.yPercent
    const widthPercent = pinData.widthPercent
    const heightPercent = pinData.heightPercent

    if (xPercent == null || xPercent === "" || yPercent == null || yPercent === "") return null

    const isResolved = pinData.status === "resolved"
    const initials = pinData.authorInitials || "?"
    const authorColor = pinData.authorColor || "annotation-author-color--0"
    const annotationId = pinData.annotationId
    const type = widthPercent && heightPercent ? "region" : "point"
    const pin = document.createElement(draft ? "div" : "button")

    if (!draft) {
      pin.type = "button"
      pin.dataset.annotationId = annotationId
      pin.setAttribute("aria-label", `Show ${type} comment by ${initials}`)
      pin.setAttribute("aria-pressed", "false")
      pin.addEventListener("click", (event) => {
        event.stopPropagation()
        this.selectAnnotation(annotationId, { source: "canvas" })
      })
    }

    pin.className = [
      "annotation-pin",
      `annotation-pin--${type}`,
      authorColor,
      isResolved ? "annotation-pin--resolved" : "",
      draft ? "annotation-pin--draft" : ""
    ].filter(Boolean).join(" ")
    pin.style.left = `${xPercent}%`
    pin.style.top = `${yPercent}%`

    if (widthPercent && heightPercent) {
      pin.style.width = `${widthPercent}%`
      pin.style.height = `${heightPercent}%`

      const label = document.createElement("span")
      label.className = "annotation-pin__label"
      label.textContent = initials
      pin.appendChild(label)

      return pin
    }

    pin.textContent = initials

    return pin
  }

  renderDraftPin(coords) {
    this.removeDraftPin()

    const form = this.formTarget
    const pinData = {
      xPercent: coords.x_percent,
      yPercent: coords.y_percent,
      widthPercent: coords.width_percent || "",
      heightPercent: coords.height_percent || "",
      status: "open",
      authorInitials: form.dataset.authorInitials,
      authorColor: form.dataset.authorColor
    }
    const pin = this.createPin(pinData, { draft: true })
    if (!pin) return

    pin.dataset.testid = "draft-annotation-pin"
    const pinContainer = this.imageTarget.parentElement || this.canvasTarget
    pinContainer.appendChild(pin)
  }

  removeDraftPin() {
    if (!this.hasCanvasTarget) return

    this.canvasTarget.querySelectorAll(".annotation-pin--draft").forEach(pin => pin.remove())
  }

  selectSidebarAnnotation(event) {
    if (event.target.closest("a, form, input, textarea, summary, details")) return

    this.selectAnnotation(event.currentTarget.dataset.annotationId, { source: "sidebar" })
  }

  selectAnnotation(annotationId, { source } = {}) {
    if (!annotationId) return

    this.element.querySelectorAll(".annotation-item--selected").forEach(item => {
      item.classList.remove("annotation-item--selected")
    })
    this.element.querySelectorAll(".annotation-pin--selected").forEach(pin => {
      pin.classList.remove("annotation-pin--selected")
      pin.setAttribute("aria-pressed", "false")
    })

    const item = this.element.querySelector(`.annotation-item[data-annotation-id="${annotationId}"]`)
    const pin = this.element.querySelector(`.annotation-pin[data-annotation-id="${annotationId}"]`)
    if (!item || !pin) return

    item.classList.add("annotation-item--selected")
    pin.classList.add("annotation-pin--selected")
    pin.setAttribute("aria-pressed", "true")

    if (source === "canvas") {
      this.dispatch("saved-marker-selected", { detail: { annotationId } })
    }

    this.scrollSidebarItemIntoView(item)

    if (source === "sidebar") {
      pin.scrollIntoView({ behavior: "smooth", block: "center", inline: "center" })
    }
  }

  scrollSidebarItemIntoView(item) {
    const sidebar = item.closest(".annotation-sidebar")
    if (!sidebar) return

    const itemRect = item.getBoundingClientRect()
    const sidebarRect = sidebar.getBoundingClientRect()
    if (itemRect.top >= sidebarRect.top && itemRect.bottom <= sidebarRect.bottom) return

    sidebar.scrollTo({
      behavior: "smooth",
      top: sidebar.scrollTop + itemRect.top - sidebarRect.top - (sidebar.clientHeight - itemRect.height) / 2
    })
  }

  observeImageWrapper() {
    if (!window.ResizeObserver || !this.imageTarget.parentElement) return

    this.imageWrapperResizeObserver?.disconnect()
    this.imageWrapperResizeObserver = new ResizeObserver(() => this.requestAnnotationFormPosition())
    this.imageWrapperResizeObserver.observe(this.imageTarget.parentElement)
  }

  requestAnnotationFormPosition() {
    if (!this.hasFormTarget || !this.pendingCoords || this.annotationFormPositionFrame != null) return

    this.annotationFormPositionFrame = requestAnimationFrame(() => {
      this.annotationFormPositionFrame = null
      this.positionAnnotationForm()
    })
  }

  positionAnnotationForm() {
    if (!this.hasFormTarget || !this.pendingCoords) return

    const form = this.formTarget
    const wrapper = this.imageTarget.parentElement
    const width = wrapper.clientWidth
    const height = wrapper.clientHeight
    if (width <= 0 || height <= 0) return

    const formRect = form.getBoundingClientRect()
    const wrapperRect = wrapper.getBoundingClientRect()
    const coords = this.pendingCoords
    const regionWidth = Number(coords.width_percent) || 0
    const regionHeight = Number(coords.height_percent) || 0
    const region = {
      left: (Number(coords.x_percent) / 100) * width,
      top: (Number(coords.y_percent) / 100) * height
    }
    region.right = region.left + (regionWidth / 100) * width
    region.bottom = region.top + (regionHeight / 100) * height
    const isRegion = regionWidth > 0 && regionHeight > 0
    const pointMarker = isRegion ? null : wrapper.querySelector(".annotation-pin--draft.annotation-pin--point")
    const pointMarkerRect = pointMarker?.getBoundingClientRect()
    const selected = pointMarkerRect ? {
      left: pointMarkerRect.left - wrapperRect.left,
      right: pointMarkerRect.right - wrapperRect.left,
      top: pointMarkerRect.top - wrapperRect.top,
      bottom: pointMarkerRect.bottom - wrapperRect.top
    } : region
    const gap = isRegion ? 4 : 12
    const edge = isRegion ? 0 : 8
    const clamp = (value, minimum, maximum) => Math.min(Math.max(value, minimum), Math.max(maximum, minimum))
    const centerX = selected.left + (selected.right - selected.left) / 2
    const candidates = [
      { left: selected.right + gap, top: selected.top },
      { left: selected.left - formRect.width - gap, top: selected.top },
      { left: centerX - formRect.width / 2, top: selected.bottom + gap },
      { left: centerX - formRect.width / 2, top: selected.top - formRect.height - gap }
    ].map((candidate, priority) => {
      const left = clamp(candidate.left, edge, width - formRect.width - edge)
      const top = clamp(candidate.top, edge, height - formRect.height - edge)
      const overlapWidth = Math.max(
        Math.min(left + formRect.width, selected.right) - Math.max(left, selected.left),
        0
      )
      const overlapHeight = Math.max(
        Math.min(top + formRect.height, selected.bottom) - Math.max(top, selected.top),
        0
      )

      return { left, top, overlapArea: overlapWidth * overlapHeight, priority }
    })
    const position = candidates.sort((a, b) => a.overlapArea - b.overlapArea || a.priority - b.priority)[0]

    form.style.left = `${position.left}px`
    form.style.top = `${position.top}px`
    form.style.visibility = "visible"
    if (form.dataset.needsFocus === "true") {
      delete form.dataset.needsFocus
      this.commentTarget.focus({ preventScroll: true })
    }
  }

  cancelAnnotationFormPosition() {
    if (this.annotationFormPositionFrame == null) return

    cancelAnimationFrame(this.annotationFormPositionFrame)
    this.annotationFormPositionFrame = null
  }

  removePins() {
    if (!this.hasCanvasTarget) return

    this.canvasTarget.querySelectorAll(".annotation-pin").forEach(pin => pin.remove())
  }
}
