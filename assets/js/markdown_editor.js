export const MarkdownEditor = {
    mounted() {
        this.textarea = this.el.querySelector("textarea");
        if (!this.textarea) return;

        // Delegate click events from the toolbar buttons
        this.el.addEventListener("click", (e) => {
            const btn = e.target.closest("button[data-action]");
            if (!btn) return;

            e.preventDefault();
            const action = btn.dataset.action;
            this.execute(action);
        });
    },

    execute(action) {
        const start = this.textarea.selectionStart;
        const end = this.textarea.selectionEnd;
        const text = this.textarea.value;
        const selected = text.substring(start, end);
        let replacement = "";

        // We want to select the "content" part of the replacement so the user can type immediately
        // or if they selected text, it remains selected but wrapped.

        switch (action) {
            case "bold":
                replacement = `**${selected || "bold text"}**`;
                break;
            case "italic":
                replacement = `*${selected || "italic text"}*`;
                break;
            case "underline":
                replacement = `<u>${selected || "underlined text"}</u>`;
                break;
            case "strikethrough":
                replacement = `~~${selected || "strikethrough text"}~~`;
                break;
            case "h1":
                replacement = `\n# ${selected || "Heading 1"}\n`;
                break;
            case "h2":
                replacement = `\n## ${selected || "Heading 2"}\n`;
                break;
            case "h3":
                replacement = `\n### ${selected || "Heading 3"}\n`;
                break;
            case "quote":
                replacement = `> ${selected || "block quote"}`;
                break;
            case "code":
                replacement = `\`${selected || "code"}\``;
                break;
            case "link":
                replacement = `[${selected || "link text"}](url)`;
                break;
            case "image":
                replacement = `![${selected || "alt text"}](image_url)`;
                break;
            default:
                return;
        }

        // Insert text
        this.textarea.setRangeText(replacement, start, end, 'select');

        // Trigger input event for LiveView
        this.textarea.dispatchEvent(new Event('input', { bubbles: true }));
        this.textarea.focus();
    }
}
