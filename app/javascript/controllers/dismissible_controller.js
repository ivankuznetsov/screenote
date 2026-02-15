import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { key: String }

  connect() {
    if (this.#isDismissed()) {
      this.element.remove()
    } else {
      this.element.removeAttribute("hidden")
    }
  }

  dismiss() {
    this.#setDismissed()
    this.element.remove()
  }

  #isDismissed() {
    try {
      return !!localStorage.getItem(this.keyValue)
    } catch {
      return false
    }
  }

  #setDismissed() {
    try {
      localStorage.setItem(this.keyValue, "1")
    } catch {
      // Storage unavailable
    }
  }
}
