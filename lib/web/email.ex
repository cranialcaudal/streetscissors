defmodule Web.Email do
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

    html =
      case Earmark.as_html(markdown) do
        {:ok, html, _} -> html
        {:error, html, _} -> html
      end

    {html, String.trim(markdown)}
  end

  defp emails_path, do: Application.get_env(:web, :emails_path) || Path.expand("content/emails")

  def newsletter(subscriber_email, subject, content) do
    new()
    |> to(subscriber_email)
    |> from({"StreetScissors", "newsletter@streetscissors.com"})
    |> with_unsubscribe(subscriber_email)
    |> subject(subject)
    |> html_body(shell(content, unsubscribe_html(subscriber_email)))
    |> text_body(strip_tags(content) <> unsubscribe_text(subscriber_email))
  end

  def strip_tags(html) do
    html
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace("&nbsp;", " ")
    |> String.trim()
  end
end
