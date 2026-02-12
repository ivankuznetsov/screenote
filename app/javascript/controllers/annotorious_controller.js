import { Controller } from "@hotwired/stimulus"
import { createImageAnnotator } from "@annotorious/annotorious"

export default class extends Controller {
  static targets = ["image", "canvas", "list", "formTemplate", "form", "xPercent", "yPercent", "widthPercent", "heightPercent", "comment"]

  connect() {
    if (!this.hasImageTarget) return

    this.initAnnotorious()
    this.renderExistingPins()
  }

  disconnect() {
    if (this.anno) {
      this.anno.destroy()
    }
    this.removePins()
  }

  initAnnotorious() {
    this.pendingAnnotationId = null

    this.anno = createImageAnnotator(this.imageTarget, {
      drawingEnabled: true,
      drawingMode: "click"
    })

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
    if (this.pendingAnnotationId === annotation.id) return
    this.pendingAnnotationId = annotation.id

    const selector = annotation.target?.selector
    if (!selector) return

    const coords = this.parseSelector(selector)
    if (!coords) return

    this.anno.removeAnnotation(annotation.id)

    this.showAnnotationForm(coords)
  }

  parseSelector(selector) {
    // Annotorious v3 returns structured geometry, not W3C media fragment strings
    const geometry = selector.geometry
    if (!geometry) return null

    const naturalW = this.imageTarget.naturalWidth
    const naturalH = this.imageTarget.naturalHeight

    const x = geometry.x
    const y = geometry.y
    const w = geometry.w
    const h = geometry.h

    const xPercent = (x / naturalW) * 100
    const yPercent = (y / naturalH) * 100
    const wPercent = (w / naturalW) * 100
    const hPercent = (h / naturalH) * 100

    const isPoint = wPercent < 1 && hPercent < 1

    return {
      x_percent: Math.round(xPercent * 100) / 100,
      y_percent: Math.round(yPercent * 100) / 100,
      width_percent: isPoint ? null : Math.round(wPercent * 100) / 100,
      height_percent: isPoint ? null : Math.round(hPercent * 100) / 100
    }
  }

  showAnnotationForm(coords) {
    this.cancelForm()

    const template = this.formTemplateTarget
    const clone = template.content.cloneNode(true)

    this.listTarget.prepend(clone)

    this.xPercentTarget.value = coords.x_percent
    this.yPercentTarget.value = coords.y_percent
    this.widthPercentTarget.value = coords.width_percent || ""
    this.heightPercentTarget.value = coords.height_percent || ""
    this.commentTarget.focus()
  }

  cancelForm() {
    if (this.hasFormTarget) {
      this.formTarget.remove()
    }
  }

  renderExistingPins() {
    this.removePins()

    if (!this.hasCanvasTarget) return

    const annotations = this.element.querySelectorAll(".annotation-item")
    annotations.forEach((item, index) => {
      const pin = this.createPin(item, index + 1)
      if (pin) this.canvasTarget.appendChild(pin)
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
