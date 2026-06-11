export const PcTerminal = {
  mounted() {
    // Keep focus on input if clicking anywhere in the container
    document.getElementById("pc-terminal").addEventListener("click", () => {
      if (this.el) this.el.focus();
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

    this.handleEvent("start_boot", () => {
      const log = document.getElementById("boot-log");
      if (!log) return;

      const lines = [
        "CÉSAR BIOS v4.20.26",
        "(C) 1994-2026 STREET SCISSORS CORP.",
        "",
        "CPU: EL CARNAL v1.0 @ 3.4GHz",
        "MEMORY TEST: 640KB OK",
        "",
        "DETECTING IDE DRIVES...",
        "  PRIMARY MASTER: CÉSAR_HD_1 (4.2GB)",
        "  PRIMARY SLAVE:  NONE",
        "",
        "LOADING LA ANIMA... DONE",
        "INITIALIZING VIRTUAL MOUNT...",
        "READY.",
        ""
      ];

      let i = 0;
      const printLine = () => {
        const currentLog = document.getElementById("boot-log");
        if (!currentLog) return;

        if (i < lines.length) {
          const div = document.createElement("div");
          div.textContent = lines[i];
          currentLog.appendChild(div);
          i++;
          const delay = Math.random() * 200 + 50;
          setTimeout(printLine, delay);
        } else {
          setTimeout(() => {
            this.pushEvent("boot_complete", {});
          }, 500);
        }
      };

      printLine();
    });
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
