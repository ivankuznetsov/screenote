import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [ "source", "button", "status" ]

  async copy() {
    try {
      await navigator.clipboard.writeText(this.sourceTarget.value)
      this.buttonTarget.textContent = "Copied"
      this.statusTarget.textContent = "Recovery link copied."
    } catch (_error) {
      this.sourceTarget.focus()
      this.sourceTarget.select()
      this.statusTarget.textContent = "Copy is unavailable. Press Ctrl+C or Command+C."
    }
  }
}
