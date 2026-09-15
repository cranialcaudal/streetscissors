/**
 * AudioDuration Hook — attached to the captain's log admin form.
 *
 * Reads the picked file's duration out of its own metadata in the browser and
 * writes it into the form's hidden duration input, so a log carries a real
 * length without the server needing ffmpeg. Also fills a blank title from the
 * filename, since that is nearly always the right first guess.
 *
 * Dispatches an input event afterwards so LiveView's phx-change picks the
 * values up and they survive the next re-render.
 */
export const AudioDuration = {
  mounted() {
    this.el.addEventListener("change", (event) => {
      const input = event.target;
      if (input.type !== "file" || !input.files || input.files.length === 0) return;

      const file = input.files[0];
      this.fillTitle(file);
      this.fillDuration(file);
    });
  },

  fillTitle(file) {
    const titleEl = this.el.querySelector("[data-audio-title]");
    if (!titleEl || titleEl.value.trim() !== "") return;

    titleEl.value = file.name
      .replace(/\.[^.]+$/, "")
      .replace(/[-_]+/g, " ")
      .trim();
  },

  fillDuration(file) {
    const durationEl = this.el.querySelector("[data-audio-duration]");
    if (!durationEl) {
      this.sync();
      return;
    }

    const url = URL.createObjectURL(file);
    const probe = new Audio();
    probe.preload = "metadata";

    const done = () => {
      URL.revokeObjectURL(url);
      this.sync();
    };

    probe.addEventListener("loadedmetadata", () => {
      if (Number.isFinite(probe.duration)) {
        durationEl.value = Math.round(probe.duration);
      }
      done();
    });

    // A format the browser cannot decode still uploads fine — it just keeps
    // whatever duration is already in the field.
    probe.addEventListener("error", done);
    probe.src = url;
  },

  sync() {
    this.el.dispatchEvent(new Event("input", { bubbles: true }));
  },
};
