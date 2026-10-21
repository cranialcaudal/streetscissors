defmodule Web.Email do
  @moduledoc """
  Builds every email the site sends: the newsletter, the welcome letter a new
  subscriber gets, and the notices it sends its author (`notice/3`, used by
  `Web.Notify`). It builds messages; `Web.Mailer` sends them.

  Email clients ignore most modern CSS, so the colours here are written out as
  plain values copied from the site's tokens, and the layout is the one shared
  `shell/2`. `preview_page/2` renders the same thing as a web page for the
  admin's preview.
  """

  import Swoosh.Email

  alias WebWeb.Unsubscribe

  @doc """
  Attaches the unsubscribe affordances every bulk message needs.

  `List-Unsubscribe` plus `List-Unsubscribe-Post` is RFC 8058 one-click: Gmail
  and Outlook render their own unsubscribe control from these and POST to the
  URL directly. Without them, bulk senders get filtered — and a visible link
  alone is a CAN-SPAM minimum, not a complete answer.
  """
  def with_unsubscribe(email, recipient) do
    email
    |> header("List-Unsubscribe", "<#{Unsubscribe.one_click_url(recipient)}>")
    |> header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
  end

  # Email-safe stand-ins for the site's tokens (assets/css/app.css). Mail
  # clients don't read CSS custom properties — Outlook's Word engine drops
  # var() outright and several webmail sanitizers strip <style> blocks — so
  # every value below is the literal hex a token currently resolves to,
  # inlined by hand rather than read live.
  @paper "#f3eee4"
  @paper_raised "#fbf9f4"
  @ink "#17140f"
  @ink_3 "#7d7566"
  @rule "rgba(23, 20, 15, 0.22)"
  @accent "#c2451d"
  @font_serif "'Sorts Mill Goudy', 'Iowan Old Style', 'Palatino Linotype', Georgia, serif"
  @font_mono "'Courier New', Courier, monospace"

  @doc "Wraps message content in the site's paper/ink shell: wordmark header, then a footer slot."
  def shell(content, footer) do
    """
    <div style="background: #{@paper}; padding: 2rem 1rem;">
      <div style="max-width: 560px; margin: 0 auto; background: #{@paper_raised}; border: 1px solid #{@rule};">
        <div style="text-align: center; padding: 2rem 2rem 1.5rem; border-bottom: 1px solid #{@rule};">
          <span style="font-family: #{@font_serif}; font-size: 1.5rem; letter-spacing: 3px; color: #{@ink};">streetscissors</span>
        </div>
        <div style="padding: 2.5rem 2rem; font-family: #{@font_serif}; font-size: 1.05rem; line-height: 1.7; color: #{@ink};">
          #{content}
        </div>
        #{footer}
      </div>
    </div>
    """
  end

  @doc """
  A whole page around `shell/2`, for showing a message outside a mail client —
  the admin's preview frame — with the shell's paper filling the frame rather
  than stopping where the message does.
  """
  def preview_page(content, footer) do
    """
    <!doctype html>
    <html><body style="margin: 0; background: #{@paper};">#{shell(content, footer)}</body></html>
    """
  end

  @doc "The footer humans actually click, appended to the HTML body."
  def unsubscribe_html(recipient) do
    """
    <div style="padding: 1.5rem 2rem; border-top: 1px solid #{@rule};">
      <p style="font-family: #{@font_mono}; font-size: 0.8rem; line-height: 1.6; color: #{@ink_3}; margin: 0;">
        You're receiving this because you subscribed at streetscissors.com.
        <a href="#{Unsubscribe.url(recipient)}" style="color: #{@accent};">Unsubscribe</a>.
      </p>
    </div>
    """
  end

  def unsubscribe_text(recipient) do
    "\n\n---\nYou're receiving this because you subscribed at streetscissors.com.\nUnsubscribe: #{Unsubscribe.url(recipient)}\n"
  end

  def welcome(user_email) do
    {html, text} = welcome_letter()

    new()
    |> to(user_email)
    |> from({"StreetScissors", "newsletter@streetscissors.com"})
    |> with_unsubscribe(user_email)
    |> subject("Welcome to streetscissors")
    |> html_body(shell(html, unsubscribe_html(user_email)))
    |> text_body(text <> unsubscribe_text(user_email))
  end

  @default_letter "Thanks for subscribing to streetscissors. New work will arrive here as it is published."

  @doc """
  The welcome letter as `{html, text}`.

  Its words are the author's, so they live beside the rest of the writing in
  `content/emails/welcome.md` (`:emails_path`) rather than in code; without that
  file a short neutral note goes out instead. Markdown is its own plain-text
  form, so the text body is the source as written.
  """
  def welcome_letter do
    markdown =
      case File.read(Path.join(emails_path(), "welcome.md")) do
        {:ok, body} -> body
        {:error, _} -> @default_letter
      end

    html = Web.Markdown.to_html(markdown)

    {html, String.trim(markdown)}
  end

  defp emails_path, do: Application.get_env(:web, :emails_path) || Path.expand("content/emails")

  @doc """
  One reader's copy of a newsletter. `format` is how `content` is written:
  `"markdown"` is rendered as a post is (`newsletter_html/2`), and its own
  text is the plain part; `"html"` (older newsletters) goes in as it is.
  """
  def newsletter(subscriber_email, subject, content, format \\ "html") do
    new()
    |> to(subscriber_email)
    |> from({"StreetScissors", "newsletter@streetscissors.com"})
    |> with_unsubscribe(subscriber_email)
    |> subject(subject)
    |> html_body(shell(newsletter_html(content, format), unsubscribe_html(subscriber_email)))
    |> text_body(newsletter_text(content, format) <> unsubscribe_text(subscriber_email))
  end

  @doc """
  A newsletter's body as HTML. Markdown goes through the blog's renderer, so
  `![[roll012/3]]` and `![[ride:123]]` embed as they do in a post, and every
  address on the site is made absolute: in a mail client `/blog/x` leads
  nowhere.
  """
  def newsletter_html(content, "markdown"), do: content |> Web.Blog.to_html() |> absolute()
  def newsletter_html(content, _html), do: content

  defp newsletter_text(content, "markdown"), do: String.trim(content) <> "\n"
  defp newsletter_text(content, _html), do: strip_tags(content)

  defp absolute(html) do
    base = WebWeb.Endpoint.url()
    html = Regex.replace(~r/\b(href|src)="\/(?!\/)/, html, "\\1=\"#{base}/")

    # A srcset is a list of addresses, each made absolute in its place.
    Regex.replace(~r/\bsrcset="([^"]*)"/, html, fn _, set ->
      ~s(srcset="#{Regex.replace(~r/(^|,\s*)\/(?!\/)/, set, "\\1#{base}/")}")
    end)
  end

  @doc """
  A plain message from the site to its author: a held signature, a fault on
  the machine. No unsubscribe footer — it is not bulk mail, and the way to
  stop it is the address in Settings.
  """
  def notice(to, subject, body) do
    paragraphs =
      body
      |> String.trim()
      |> String.split(~r/\n{2,}/)
      |> Enum.map_join("\n", fn paragraph ->
        escaped = paragraph |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
        ~s(<p style="margin: 0 0 1.2em;">#{String.replace(escaped, "\n", "<br>")}</p>)
      end)

    footer = """
    <div style="padding: 1.5rem 2rem; border-top: 1px solid #{@rule};">
      <p style="font-family: #{@font_mono}; font-size: 0.8rem; line-height: 1.6; color: #{@ink_3}; margin: 0;">
        Sent by the site to the address in its settings.
      </p>
    </div>
    """

    new()
    |> to(to)
    |> from({"streetscissors", "machine@streetscissors.com"})
    |> subject(subject)
    |> html_body(shell(paragraphs, footer))
    |> text_body(String.trim(body))
  end

  def strip_tags(html) do
    html
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace("&nbsp;", " ")
    |> String.trim()
  end
end
