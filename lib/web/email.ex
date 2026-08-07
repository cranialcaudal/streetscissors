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

  @doc "The footer humans actually click, appended to the HTML body."
  def unsubscribe_html(recipient) do
    """
    <hr style="border: none; border-top: 1px solid #ddd; margin: 2.5rem 0 1rem;">
    <p style="font-size: 0.8rem; color: #777;">
      You're receiving this because you subscribed at streetscissors.com.
      <a href="#{Unsubscribe.url(recipient)}" style="color: #777;">Unsubscribe</a>.
    </p>
    """
  end

  def unsubscribe_text(recipient) do
    "\n\n---\nYou're receiving this because you subscribed at streetscissors.com.\nUnsubscribe: #{Unsubscribe.url(recipient)}\n"
  end

  def welcome(user_email) do
    new()
    |> to(user_email)
    |> from({"StreetScissors", "newsletter@streetscissors.com"})
    |> with_unsubscribe(user_email)
    |> subject("Welcome to streetscissors")
    |> html_body(
      """
      <p>Your social media feeds have been dead for some time now. A signal still permeates the air yet our digital antennas seem to be broken.</p>

      <p>If you're reading this, you have successfully made the first steps of exiting the "Meta economy." American technocrats insist on your use of their services by tricking one into thinking setting up multiple user accounts or arranging thematic highlights is good for you. But all it really makes you do is split your attention between their technological ecosystem. How can one be against capital with a personal Instagram, gym Instagram, food review Instagram, art Instagram, and, of course, your secret Finstagram? By juggling these accounts, one's digital "soul" has been attentionally split—like 4 horses tied to a medieval criminal.</p>

      <p>This is my exit.</p>

      <p>In rock and roll, the "27 Club" is a tragic list of artists who burned out and died at 27. Cobain, Winehouse, Johnson, Hendrix, Yelchin, Bell, Basquiat, Joplin, Morrison. How we romanticize these people but ignore the stresses and pressures they suffered through. On my upcoming 27th birthday, I am reclaiming this concept. I am initiating my own ontological death.</p>

      <p>Yet, I am not ending in the flesh. In the flesh, I persist. Rather, there will be a new means of how I live. iResurrect.</p>

      <p>streetscissors.com is the vessel in which I will return. A digital Odysseus. Here, I will return by installing my own will onto my own digital sovereignty. I am entirely self-published and self-hosted (via Linux xD) so that means no nefarious agents shadowbanning my truth, no AI slop, no clip-farming, no rage-baiting. If you're feeling some type of way, it may just be a projection of your unconscious onto my shared realities and perspectives.</p>

      <p>This site is a repository for the things that actually matter. It is where I will host:</p>

      <ul>
        <li>Manuscripts and long-form writing that demand an attention span.</li>
        <li>Audio files that cut through the silence.</li>
        <li>Images created by human intent, not prompted generation.</li>
        <li>Blogs that document the reality of living offline while building online.</li>
      </ul>

      <p>Thanks for subscribing and see you on the other side.</p>

      <p>Welcome to my new body.</p>

      <p>Love,<br>streetscissors dr4gontamer animaljesus cesar</p>
      """ <> unsubscribe_html(user_email)
    )
    |> text_body(
      """
      Your social media feeds have been dead for some time now. A signal still permeates the air yet our digital antennas seem to be broken.

      If you're reading this, you have successfully made the first steps of exiting the "Meta economy." American technocrats insist on your use of their services by tricking one into thinking setting up multiple user accounts or arranging thematic highlights is good for you. But all it really makes you do is split your attention between their technological ecosystem. How can one be against capital with a personal Instagram, gym Instagram, food review Instagram, art Instagram, and, of course, your secret Finstagram? By juggling these accounts, one's digital "soul" has been attentionally split—like 4 horses tied to a medieval criminal.

      This is my exit.

      In rock and roll, the "27 Club" is a tragic list of artists who burned out and died at 27. Cobain, Winehouse, Johnson, Hendrix, Yelchin, Bell, Basquiat, Joplin, Morrison. How we romanticize these people but ignore the stresses and pressures they suffered through. On my upcoming 27th birthday, I am reclaiming this concept. I am initiating my own ontological death.

      Yet, I am not ending in the flesh. In the flesh, I persist. Rather, there will be a new means of how I live. iResurrect.

      streetscissors.com is the vessel in which I will return. A digital Odysseus. Here, I will return by installing my own will onto my own digital sovereignty. I am entirely self-published and self-hosted (via Linux xD) so that means no nefarious agents shadowbanning my truth, no AI slop, no clip-farming, no rage-baiting. If you're feeling some type of way, it may just be a projection of your unconscious onto my shared realities and perspectives.

      This site is a repository for the things that actually matter. It is where I will host:

      - Manuscripts and long-form writing that demand an attention span.
      - Audio files that cut through the silence.
      - Images created by human intent, not prompted generation.
      - Blogs that document the reality of living offline while building online.

      Thanks for subscribing and see you on the other side.

      Welcome to my new body.

      Love,
      streetscissors dr4gontamer animaljesus cesar
      """ <> unsubscribe_text(user_email)
    )
  end

  def newsletter(subscriber_email, subject, content) do
    new()
    |> to(subscriber_email)
    |> from({"StreetScissors", "newsletter@streetscissors.com"})
    |> with_unsubscribe(subscriber_email)
    |> subject(subject)
    |> html_body(content <> unsubscribe_html(subscriber_email))
    |> text_body(strip_tags(content) <> unsubscribe_text(subscriber_email))
  end

  def strip_tags(html) do
    html
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace("&nbsp;", " ")
    |> String.trim()
  end
end
