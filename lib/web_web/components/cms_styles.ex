defmodule WebWeb.CmsStyles do
  @moduledoc """
  Page-scoped styling shared by the two content managers (`/admin/blog` and
  `/admin/logs`).

  Admin pages in this app carry their own `<style>` block rather than adding
  to `app.css` — the admin layout is a deliberate dark exception to the paper
  design system. This one is factored out because both managers need the same
  vocabulary; render `<.cms_styles />` once per page.
  """

  use Phoenix.Component

  def cms_styles(assigns) do
    ~H"""
    <style>
      .cms { max-width: 900px; color: #ddd; }
      .cms-title { font-size: 1.8rem; font-weight: 800; color: #fff; margin-bottom: 0.35rem; }
      .cms-lede { color: #777; font-size: 0.9rem; margin-bottom: 2rem; }
      .cms-panel { background: rgba(255,255,255,0.03); border: 1px solid #2a2a2a; border-radius: 10px; padding: 1.5rem; margin-bottom: 1.5rem; }
      .cms-panel h2 { font-size: 1rem; text-transform: uppercase; letter-spacing: 2px; color: #999; margin-bottom: 1rem; }
      .cms-hint { color: #777; font-size: 0.85rem; margin: 0.5rem 0; }

      /* Forms. CoreComponents.input/1 wraps each field in .fieldset with the
         caption in .label, so style those rather than re-rolling the markup. */
      .cms .fieldset, .cms-field { margin-bottom: 1rem; }
      .cms .label, .cms-field .label {
        display: block; font-size: 0.75rem; text-transform: uppercase;
        letter-spacing: 1px; color: #888; margin-bottom: 0.4rem;
      }
      .cms-input {
        width: 100%; background: #000; border: 1px solid #333; color: #eee; border-radius: 6px;
        padding: 0.6rem 0.75rem; font-family: monospace; font-size: 0.9rem;
      }
      .cms-input:focus { outline: none; border-color: #ff6600; }
      textarea.cms-input { min-height: 5rem; resize: vertical; }
      /* The checkbox variant puts its caption inline, so undo the block label. */
      .cms input[type="checkbox"] { width: 1rem; height: 1rem; margin-right: 0.5rem; vertical-align: middle; }
      .cms input[type="checkbox"] + .label,
      .cms .label:has(input[type="checkbox"]) {
        display: inline; text-transform: none; letter-spacing: 0; color: #ccc; font-size: 0.9rem;
      }
      .cms-actions { display: flex; gap: 0.75rem; align-items: center; margin-top: 1.25rem; }
      .cms-error, .cms .text-error { color: #f87171; font-size: 0.8rem; margin-top: 0.3rem; display: flex; align-items: center; gap: 0.4rem; }

      /* Drop zone */
      .cms-drop { border: 2px dashed #333; border-radius: 10px; padding: 2.5rem 1.5rem; text-align: center; transition: border-color 0.2s, background 0.2s; }
      .cms-drop:hover { border-color: #ff6600; background: rgba(255,102,0,0.03); }
      .cms-drop-title { color: #fff; font-weight: 700; letter-spacing: 1px; margin-bottom: 0.4rem; }
      .cms-browse { display: inline-block; cursor: pointer; background: #fff; color: #000; border-radius: 6px; padding: 0.6rem 1.5rem; font-weight: 800; font-size: 0.75rem; letter-spacing: 1.5px; margin-top: 1rem; }
      .cms-file-input { display: none; }
      .cms-progress { height: 3px; background: #111; border-radius: 2px; overflow: hidden; margin-top: 0.5rem; }
      .cms-progress-bar { height: 100%; background: #ff6600; transition: width 0.3s; }
      .cms-entry { text-align: left; font-family: monospace; font-size: 0.8rem; color: #aaa; margin-top: 1rem; }
      .cms-results { margin-top: 1rem; font-size: 0.85rem; color: #9f9; list-style: none; padding: 0; }
      .cms-results li { padding: 0.2rem 0; }
      .cms-results .failed { color: #f87171; }

      /* Item lists */
      .cms-list { display: flex; flex-direction: column; gap: 0.75rem; }
      .cms-item { background: #080808; border: 1px solid rgba(255,255,255,0.08); border-radius: 8px; padding: 1rem 1.25rem; }
      .cms-item-head { display: flex; justify-content: space-between; align-items: baseline; gap: 1rem; }
      .cms-item-title { font-size: 1rem; color: #fff; font-weight: 600; margin: 0; }
      .cms-item-meta { display: flex; flex-wrap: wrap; gap: 1rem; font-family: monospace; font-size: 0.7rem; color: #666; margin-top: 0.35rem; }
      .cms-item-actions { display: flex; gap: 0.75rem; flex-shrink: 0; }
      .cms-link { background: none; border: none; padding: 0; cursor: pointer; font-size: 0.75rem; color: #9db8f0; text-decoration: none; }
      .cms-link:hover { text-decoration: underline; }
      .cms-link.danger { color: #c66; }
      .cms-link.danger:hover { color: #f88; }
      .cms-live { color: #4ade80; }
      .cms-hidden-state { color: #f87171; }

      /* Keywords */
      .cms-keywords { display: flex; flex-wrap: wrap; gap: 0.35rem; margin-top: 0.6rem; }
      .cms-keyword { font-family: monospace; font-size: 0.7rem; color: #aaa; border: 1px solid #333; border-radius: 999px; padding: 0.1rem 0.55rem; }
      .cms-keyword-missing { color: #fbbf24; font-family: monospace; font-size: 0.7rem; }
      .cms-keyword-form { display: flex; gap: 0.5rem; margin-top: 0.6rem; }
      .cms-keyword-form input { flex: 1; }

      /* Image library */
      .cms-images { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 1rem; }
      .cms-image { background: #080808; border: 1px solid rgba(255,255,255,0.08); border-radius: 8px; padding: 0.75rem; }
      .cms-image img { width: 100%; height: 90px; object-fit: cover; border-radius: 4px; background: #222; }
      .cms-image input { width: 100%; margin-top: 0.5rem; background: #000; border: 1px solid #333; color: #888; font-size: 0.65rem; padding: 0.2rem 0.4rem; border-radius: 4px; font-family: monospace; }
      .cms-empty { color: #555; font-size: 0.85rem; padding: 1.5rem 0; text-align: center; }
    </style>
    """
  end
end
