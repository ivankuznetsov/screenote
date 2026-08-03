import { Controller } from "@hotwired/stimulus"
import { createImageAnnotator } from "@annotorious/annotorious"

export default class extends Controller {
  static targets = ["image", "canvas", "list", "formTemplate", "form", "xPercent", "yPercent", "widthPercent", "heightPercent", "comment"]

  connect() {
    if (!this.hasImageTarget) return

    this.disposed = false
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

    this.releaseBoundaryPointerCapture()
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

  showAnnotationForm(coords, annotationId) {
    if (this.hasFormTarget && this.commentTarget.value.trim() !== "") {
      this.anno?.removeAnnotation(annotationId)
      return
    }

    this.dispatch("annotation-form-show")
    this.cancelForm()
    this.pendingAnnotationId = annotationId

    const template = this.formTemplateTarget
    const clone = template.content.cloneNode(true)

    this.listTarget.prepend(clone)

    this.xPercentTarget.value = coords.x_percent
    this.yPercentTarget.value = coords.y_percent
    this.widthPercentTarget.value = coords.width_percent || ""
    this.heightPercentTarget.value = coords.height_percent || ""
    const sidebar = this.formTarget.closest(".annotation-sidebar")
    if (sidebar) sidebar.scrollTop = 0
    this.commentTarget.focus({ preventScroll: true })
  }

  cancelForm() {
    if (this.hasFormTarget) {
      this.formTarget.remove()
    }
    if (this.pendingAnnotationId && this.anno) {
      this.anno.removeAnnotation(this.pendingAnnotationId)
    }
    this.pendingAnnotationId = null
  }

  renderExistingPins() {
    this.removePins()

    if (!this.hasCanvasTarget) return

    const pinContainer = this.imageTarget.parentElement || this.canvasTarget
    const annotations = this.element.querySelectorAll(".annotation-item")
    annotations.forEach((item, index) => {
      const pin = this.createPin(item, index + 1)
      if (pin) pinContainer.appendChild(pin)
    })
  }

  createPin(annotationEl, number) {
    const xPercent = annotationEl.dataset.xPercent
    const yPercent = annotationEl.dataset.yPercent
    const widthPercent = annotationEl.dataset.widthPercent
    const heightPercent = annotationEl.dataset.heightPercent

    if (!xPercent || !yPercent) return null

    const isResolved = annotationEl.dataset.status === "resolved"

    if (widthPercent && heightPercent) {
      const region = document.createElement("div")
      region.className = `annotation-pin annotation-pin--region ${isResolved ? "annotation-pin--resolved" : ""}`
      region.style.left = `${xPercent}%`
      region.style.top = `${yPercent}%`
      region.style.width = `${widthPercent}%`
      region.style.height = `${heightPercent}%`

      const label = document.createElement("span")
      label.className = "annotation-pin__label"
      label.textContent = number
      region.appendChild(label)

      return region
    }

    const pin = document.createElement("div")
    pin.className = `annotation-pin annotation-pin--point ${isResolved ? "annotation-pin--resolved" : ""}`
    pin.style.left = `${xPercent}%`
    pin.style.top = `${yPercent}%`
    pin.textContent = number

    return pin
  }

  removePins() {
    if (!this.hasCanvasTarget) return

    this.canvasTarget.querySelectorAll(".annotation-pin").forEach(pin => pin.remove())
  }
}
