import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["reply", "replyField", "reopen", "reopenField"]

  toggleReply(event) {
    this.toggle(this.replyTarget, this.replyFieldTarget, event.currentTarget)
  }

  toggleReopen(event) {
    this.toggle(this.reopenTarget, this.reopenFieldTarget, event.currentTarget)
  }

  toggle(content, field, button) {
    const opening = content.hidden
    content.hidden = !opening
    button.setAttribute("aria-expanded", opening.toString())

    if (opening) requestAnimationFrame(() => field.focus({ preventScroll: true }))
  }
}
