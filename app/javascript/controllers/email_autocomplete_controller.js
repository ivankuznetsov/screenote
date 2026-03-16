import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results"]
  static values = { url: String }

  connect() {
    this.selectedIndex = -1
    this.abortController = null

    this.outsideClickHandler = (e) => {
      if (!this.element.contains(e.target)) this.close()
    }
    document.addEventListener("click", this.outsideClickHandler)
  }

  search() {
    clearTimeout(this.timeout)
    const query = this.inputTarget.value.trim()

    if (query.length < 2) {
      this.close()
      return
    }

    this.timeout = setTimeout(() => this.fetchSuggestions(query), 300)
  }

  async fetchSuggestions(query) {
    if (this.abortController) this.abortController.abort()
    this.abortController = new AbortController()

    try {
      const url = `${this.urlValue}?q=${encodeURIComponent(query)}`
      const response = await fetch(url, {
        signal: this.abortController.signal,
        headers: { "Accept": "text/html" }
      })
      if (!response.ok) return this.close()

      const html = await response.text()
      this.resultsTarget.replaceChildren()
      const template = document.createElement("template")
      template.innerHTML = html
      this.resultsTarget.append(...template.content.childNodes)
      this.selectedIndex = -1

      if (this.resultsTarget.children.length > 0) {
        this.resultsTarget.hidden = false
        this.resultsTarget.querySelectorAll("li").forEach(li => {
          li.addEventListener("click", (e) => this.select(e.currentTarget))
        })
      } else {
        this.close()
      }
    } catch (e) {
      if (e.name !== "AbortError") this.close()
    }
  }

  navigate(event) {
    const items = this.resultsTarget.querySelectorAll("li")
    if (!items.length || this.resultsTarget.hidden) return

    switch (event.key) {
      case "ArrowDown":
        event.preventDefault()
        this.selectedIndex = Math.min(this.selectedIndex + 1, items.length - 1)
        this.highlight(items)
        break
      case "ArrowUp":
        event.preventDefault()
        this.selectedIndex = Math.max(this.selectedIndex - 1, 0)
        this.highlight(items)
        break
      case "Enter":
        event.preventDefault()
        if (this.selectedIndex >= 0) this.select(items[this.selectedIndex])
        break
      case "Escape":
        this.close()
        break
    }
  }

  highlight(items) {
    items.forEach((li, i) => li.setAttribute("aria-selected", i === this.selectedIndex))
  }

  select(item) {
    this.inputTarget.value = item.dataset.email
    this.close()
    this.inputTarget.focus()
  }

  close() {
    this.resultsTarget.hidden = true
    this.resultsTarget.replaceChildren()
    this.selectedIndex = -1
  }

  disconnect() {
    if (this.abortController) this.abortController.abort()
    clearTimeout(this.timeout)
    document.removeEventListener("click", this.outsideClickHandler)
  }
}
