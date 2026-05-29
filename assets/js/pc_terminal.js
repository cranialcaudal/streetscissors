export const PcTerminal = {
  mounted() {
    // Keep focus on input if clicking anywhere in the container
    document.getElementById("pc-terminal").addEventListener("click", () => {
      this.el.focus();
    });

    this.el.addEventListener("keydown", (e) => {
      if (e.key === "Tab") {
        e.preventDefault(); // Prevent focus cycling
        this.pushEvent("tab_complete", { value: this.el.value });
      }
    });

    this.handleEvent("update_terminal_input", (payload) => {
      this.el.value = payload.value;
      // Cursor to the end
      this.el.selectionStart = this.el.selectionEnd = this.el.value.length;
    });
  }
};

export const AutoScroll = {
  mounted() {
    this.scrollToBottom();
  },
  updated() {
    this.scrollToBottom();
  },
  scrollToBottom() {
    if (this.el) {
      this.el.scrollTop = this.el.scrollHeight;
    }
  }
};
