import { Controller } from "@hotwired/stimulus"

// One labelled modal dialog per gallery. The native <dialog> element supplies
// the contained tab sequence, the Escape dismissal, and focus restoration;
// this controller adds arrow navigation, bounded zoom, and the download and
// open-original links.
export default class extends Controller {
  static targets = ["dialog", "image", "previous", "next", "download", "openOriginal", "trigger"]

  static MIN_ZOOM = 1
  static MAX_ZOOM = 4
  static ZOOM_STEP = 0.5

  connect() {
    this.index = 0
    this.zoom = 1
    this.onKeydown = this.onKeydown.bind(this)
    this.dialogTarget.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    this.dialogTarget.removeEventListener("keydown", this.onKeydown)
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  open(event) {
    this.index = Number(event.currentTarget.dataset.index || 0)
    this.zoom = 1
    this.render()
    this.dialogTarget.showModal()
    this.imageTarget.focus({ preventScroll: true })
  }

  close() {
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  next() {
    this.index = (this.index + 1) % this.triggerTargets.length
    this.zoom = 1
    this.render()
  }

  previous() {
    this.index = (this.index - 1 + this.triggerTargets.length) % this.triggerTargets.length
    this.zoom = 1
    this.render()
  }

  zoomIn() {
    this.zoom = Math.min(this.constructor.MAX_ZOOM, this.zoom + this.constructor.ZOOM_STEP)
    this.applyZoom()
  }

  zoomOut() {
    this.zoom = Math.max(this.constructor.MIN_ZOOM, this.zoom - this.constructor.ZOOM_STEP)
    this.applyZoom()
  }

  onKeydown(event) {
    if (event.key === "ArrowRight") {
      event.preventDefault()
      this.next()
    } else if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.previous()
    }
  }

  render() {
    const trigger = this.triggerTargets[this.index]
    if (!trigger) return

    this.imageTarget.src = trigger.dataset.originalUrl
    this.imageTarget.alt = trigger.dataset.alt
    this.downloadTarget.href = trigger.dataset.downloadUrl
    this.openOriginalTarget.href = trigger.dataset.originalUrl

    // A one-image gallery has nowhere to navigate.
    const single = this.triggerTargets.length < 2
    this.previousTarget.hidden = single
    this.nextTarget.hidden = single
    this.applyZoom()
  }

  applyZoom() {
    this.imageTarget.style.scale = String(this.zoom)
  }
}
