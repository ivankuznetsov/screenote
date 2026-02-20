import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["formWrapper"]

  toggleForm() {
    const wrapper = this.formWrapperTarget
    wrapper.style.display = wrapper.style.display === "none" ? "block" : "none"
  }
}
