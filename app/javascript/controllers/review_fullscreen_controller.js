import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image", "toggle"]

  connect() {
    this.handleKeydown = this.handleKeydown.bind(this)
    this.handleResize = this.handleResize.bind(this)
    this.resizeFrame = null

    const restoreFullscreen = this.fullscreen || document.body.classList.contains("review-fullscreen-open")
    this.element.classList.remove("screenshot-workspace--fullscreen")
    if (restoreFullscreen) this.enter()
  }

  disconnect() {
    this.leaveFullscreen({ preserveBodyState: true, restoreFocus: false })
  }

  toggle() {
    if (this.fullscreen) {
      this.exit()
    } else {
      this.enter()
    }
  }

  enter() {
    if (this.fullscreen) return

    this.element.classList.add("screenshot-workspace--fullscreen")
    document.body.classList.add("review-fullscreen-open")
    document.addEventListener("keydown", this.handleKeydown)
    window.addEventListener("resize", this.handleResize)
    this.fitImage()
    this.updateToggle(true)
    this.toggleTarget.focus({ preventScroll: true })
  }

  exit() {
    if (!this.fullscreen) return

    this.leaveFullscreen()
  }

  leaveFullscreen({ preserveBodyState = false, restoreFocus = true } = {}) {
    this.element.classList.remove("screenshot-workspace--fullscreen")
    if (!preserveBodyState) document.body.classList.remove("review-fullscreen-open")
    document.removeEventListener("keydown", this.handleKeydown)
    window.removeEventListener("resize", this.handleResize)
    this.cancelPendingResize()
    this.clearImageFit()
    this.updateToggle(false)
    if (restoreFocus) this.toggleTarget.focus({ preventScroll: true })
  }

  handleKeydown(event) {
    if (event.key !== "Escape") return

    event.preventDefault()
    this.exit()
  }

  handleResize() {
    if (this.resizeFrame !== null) return

    this.resizeFrame = requestAnimationFrame(() => {
      this.resizeFrame = null
      this.fitImage()
    })
  }

  fitImage() {
    if (!this.hasImageTarget) return

    const image = this.imageTarget
    if (!image.complete || image.naturalWidth <= 0 || image.naturalHeight <= 0) {
      image.addEventListener("load", this.handleResize, { once: true })
      return
    }

    const aspectRatio = image.naturalWidth / image.naturalHeight
    const viewportRatio = window.innerWidth / window.innerHeight
    const widthBound = aspectRatio > viewportRatio
    const wrapper = image.parentElement

    wrapper.classList.toggle("screenshot-canvas__image-wrapper--width-bound", widthBound)
    wrapper.classList.toggle("screenshot-canvas__image-wrapper--height-bound", !widthBound)
  }

  clearImageFit() {
    if (!this.hasImageTarget) return

    const image = this.imageTarget
    image.removeEventListener("load", this.handleResize)
    image.parentElement.classList.remove(
      "screenshot-canvas__image-wrapper--width-bound",
      "screenshot-canvas__image-wrapper--height-bound"
    )
  }

  cancelPendingResize() {
    if (this.resizeFrame === null) return

    cancelAnimationFrame(this.resizeFrame)
    this.resizeFrame = null
  }

  updateToggle(fullscreen) {
    const label = fullscreen ? "Exit fullscreen" : "Enter fullscreen"

    this.toggleTarget.setAttribute("aria-label", label)
    this.toggleTarget.setAttribute("aria-pressed", fullscreen.toString())
    this.toggleTarget.title = label
  }

  get fullscreen() {
    return this.element.classList.contains("screenshot-workspace--fullscreen")
  }
}
