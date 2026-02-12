import { Controller } from "@hotwired/stimulus"
import { createImageAnnotator } from "@annotorious/annotorious"

export default class extends Controller {
  static values = {
    screenshotId: Number,
    projectId: Number
  }

  connect() {
    this.imageEl = document.getElementById("screenshot-image")
    if (!this.imageEl) return

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
    this.anno = createImageAnnotator(this.imageEl, {
      drawingEnabled: true,
      drawingMode: "click"
    })

    this.anno.on("createAnnotation", (annotation) => {
      this.handleCreate(annotation)
    })
  }

  handleCreate(annotation) {
    const selector = annotation.target?.selector
    if (!selector) return

    const coords = this.parseSelector(selector)
    if (!coords) return

    this.anno.removeAnnotation(annotation.id)

    this.showAnnotationForm(coords)
  }

  parseSelector(selector) {
    const value = selector.value || ""
    const match = value.match(/xywh=pixel:(\d+(?:\.\d+)?),(\d+(?:\.\d+)?),(\d+(?:\.\d+)?),(\d+(?:\.\d+)?)/)
    if (!match) return null

    const naturalW = this.imageEl.naturalWidth
    const naturalH = this.imageEl.naturalHeight

    const x = parseFloat(match[1])
    const y = parseFloat(match[2])
    const w = parseFloat(match[3])
    const h = parseFloat(match[4])

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
    const existingForm = document.getElementById("annotation-form")
    if (existingForm) existingForm.remove()

    this.createAnnotationForm(coords)
  }

  createAnnotationForm(coords) {
    const url = `/projects/${this.projectIdValue}/screenshots/${this.screenshotIdValue}/annotations`
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content || ""

    const form = document.createElement("form")
    form.id = "annotation-form"
    form.className = "annotation-form"
    form.method = "post"
    form.action = url
    form.setAttribute("data-turbo", "true")

    const addHidden = (name, value) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      form.appendChild(input)
    }

    addHidden("authenticity_token", csrfToken)
    addHidden("annotation[x_percent]", coords.x_percent)
    addHidden("annotation[y_percent]", coords.y_percent)
    addHidden("annotation[width_percent]", coords.width_percent || "")
    addHidden("annotation[height_percent]", coords.height_percent || "")

    const body = document.createElement("div")
    body.className = "annotation-form__body"

    const textarea = document.createElement("textarea")
    textarea.name = "annotation[comment]"
    textarea.className = "annotation-form__textarea"
    textarea.placeholder = "Add a comment..."
    textarea.rows = 3
    body.appendChild(textarea)

    const actions = document.createElement("div")
    actions.className = "annotation-form__actions"

    const submitBtn = document.createElement("button")
    submitBtn.type = "submit"
    submitBtn.className = "btn btn--primary btn--small"
    submitBtn.textContent = "Save"
    actions.appendChild(submitBtn)

    const cancelBtn = document.createElement("button")
    cancelBtn.type = "button"
    cancelBtn.className = "btn btn--secondary btn--small"
    cancelBtn.textContent = "Cancel"
    cancelBtn.setAttribute("data-action", "click->annotorious#cancelForm")
    actions.appendChild(cancelBtn)

    body.appendChild(actions)
    form.appendChild(body)

    const sidebar = document.getElementById("annotations-list")
    if (sidebar) {
      sidebar.prepend(form)
      textarea.focus()
    }
  }

  cancelForm() {
    const form = document.getElementById("annotation-form")
    if (form) form.remove()
  }

  renderExistingPins() {
    this.removePins()

    const canvas = this.element.querySelector(".screenshot-canvas")
    if (!canvas) return

    const annotations = document.querySelectorAll(".annotation-item")
    annotations.forEach((item, index) => {
      const pin = this.createPin(item, index + 1)
      if (pin) canvas.appendChild(pin)
    })
  }

  createPin(annotationEl, number) {
    const xPercent = annotationEl.dataset.xPercent
    const yPercent = annotationEl.dataset.yPercent
    const widthPercent = annotationEl.dataset.widthPercent
    const heightPercent = annotationEl.dataset.heightPercent

    if (!xPercent || !yPercent) return null

    const isResolved = annotationEl.classList.contains("annotation-item--resolved")

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
    const canvas = this.element.querySelector(".screenshot-canvas")
    if (!canvas) return

    canvas.querySelectorAll(".annotation-pin").forEach(pin => pin.remove())
  }
}
