import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  navigate(event) {
    const destination = event.currentTarget.value
    if (destination) Turbo.visit(destination)
  }
}
