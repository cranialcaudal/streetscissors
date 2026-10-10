defmodule WebWeb.FaithHTML do
  @moduledoc """
  The prayer pages rendered by `WebWeb.FaithController`, and the components
  they share. Styled only by `assets/css/faith.css`.

  Each prayer is a component (`office/1`, `masses/1`, `midday/1`,
  `rosary_text/1`) because it is shown twice: opened in place on the day's
  page, and on a page of its own.
  """
  use WebWeb, :html

  alias Web.Liturgy.{Calendar, Prayers}

  embed_templates "faith_html/*"

  @months ~w(January February March April May June July August September October November December)

  @ranks %{
    solemnity: "Solemnity",
    feast: "Feast",
    memorial: "Memorial",
    commemoration: "Commemoration",
    sunday: "Sunday",
    weekday: "Weekday",
    triduum: "Paschal Triduum",
    optional: "Optional memorial"
  }

  @doc "\"Tuesday, October 6\"."
  def long_date(%Date{} = date), do: "#{Calendar.weekday_name(date)}, #{month_day(date)}"

  @doc "\"October 6\"."
  def month_day(%{month: month, day: day}), do: "#{month_name(month)} #{day}"

  def month_name(month), do: Enum.at(@months, month - 1)

  @doc "\"2026-10\", the calendar page's `?month=`."
  def month_param(%Date{} = date), do: date |> Date.to_iso8601() |> String.slice(0, 7)

  def rank_name(rank), do: Map.get(@ranks, rank, "")

  def roman(n), do: Enum.at(~w(I II III IV), n - 1)

  @doc "\"the Paschal Triduum\" as \"The Paschal Triduum\", leaving the rest alone."
  def upcase_first(<<first::utf8, rest::binary>>), do: String.upcase(<<first::utf8>>) <> rest

  def chapter_title(book, number), do: WebWeb.FaithController.chapter_title(book, number)

  @doc "The day's page for `date`: bare `/Christ` when that is today."
  def day_path(date, today) do
    if date == today, do: ~p"/Christ", else: ~p"/Christ?date=#{Date.to_iso8601(date)}"
  end

  @doc "The row of doors between the prayer pages."
  attr :current, :atom, default: nil

  def faith_nav(assigns) do
    assigns =
      assign(assigns, :links, [
        {:today, "Today", ~p"/Christ"},
        {:lauds, "Morning", ~p"/Christ/hours/lauds"},
        {:angelus, "Midday", ~p"/Christ/angelus"},
        {:readings, "Readings", ~p"/Christ/readings"},
        {:vespers, "Evening", ~p"/Christ/hours/vespers"},
        {:rosary, "Rosary", ~p"/Christ/rosary"},
        {:compline, "Night", ~p"/Christ/hours/compline"},
        {:calendar, "Calendar", ~p"/Christ/calendar"},
        {:bible, "Bible", ~p"/Christ/bible"}
      ])

    ~H"""
    <nav class="faith-nav" aria-label="Prayer">
      <a
        :for={{key, label, path} <- @links}
        href={path}
        class="faith-nav-link"
        aria-current={key == @current && "page"}
      >
        {label}
      </a>
    </nav>
    """
  end

  @doc """
  Yesterday, today, tomorrow. The arrow keys follow `rel="prev"` and
  `rel="next"` (app.js).
  """
  attr :previous, :string, required: true
  attr :previous_label, :string, required: true
  attr :next, :string, required: true
  attr :next_label, :string, required: true
  attr :today, :string, default: nil

  def turn(assigns) do
    ~H"""
    <nav class="faith-turn" aria-label="Other days">
      <a href={@previous} rel="prev">‹ {@previous_label}</a>
      <a :if={@today} href={@today}>Today</a>
      <a href={@next} rel="next">{@next_label} ›</a>
    </nav>
    """
  end

  @doc """
  A saint or feast of the day: the picture, the rank, and the life. `saint`
  is `Web.Liturgy.Saints.get/1`, and may be nil for a day with no life on file.
  """
  attr :entry, :map, required: true
  attr :saint, :map, default: nil

  attr :full, :boolean,
    default: false,
    doc: "the saint's own page: every paragraph, no link to itself"

  def saint_card(assigns) do
    ~H"""
    <article class={["faith-saint", @saint && @saint.image && "faith-saint--pictured"]}>
      <img
        :if={@saint && @saint.image}
        class="faith-saint-picture"
        src={"/images/saints/#{@saint.image.file}"}
        width={@saint.image.width}
        height={@saint.image.height}
        alt={@entry.title}
        loading="lazy"
      />
      <div class="faith-saint-body">
        <p class="faith-label">
          {rank_name(@entry.rank)}
          <span :if={@entry.proper && @entry.symbol && @full}>· proper calendar</span>
        </p>
        <h2 class="faith-saint-name">
          <%= if @full or is_nil(@entry.symbol) or is_nil(@saint) do %>
            {@entry.title}
          <% else %>
            <a href={~p"/Christ/saints/#{@entry.symbol}"}>{@entry.title}</a>
          <% end %>
        </h2>
        <div :for={life <- (@saint && @saint.lives) || []} class="faith-saint-life">
          <h3 :if={length(@saint.lives) > 1} class="faith-saint-who">{life.name}</h3>
          <p>{if @full, do: life.text, else: brief(life.text)}</p>
          <p class="faith-credit">
            From <a href={life.url} rel="noopener">Wikipedia, "{life.name}"</a>, CC BY-SA 4.0.
          </p>
        </div>
        <p :if={@saint && @saint.image} class="faith-credit">
          Picture: {credit(@saint.image)}
          <a href={@saint.image.source} rel="noopener">Wikimedia Commons</a>, {@saint.image.license}.
        </p>
      </div>
    </article>
    """
  end

  # The first two or three sentences, for a card.
  defp brief(text) do
    sentences = Regex.split(~r/(?<=[a-z\)\]]\.)\s+(?=[A-Z])/, text)

    {kept, _} =
      Enum.reduce_while(sentences, {[], 0}, fn sentence, {acc, size} ->
        if acc != [] and size + String.length(sentence) > 420,
          do: {:halt, {acc, size}},
          else: {:cont, {[sentence | acc], size + String.length(sentence)}}
      end)

    kept |> Enum.reverse() |> Enum.join(" ")
  end

  defp credit(%{artist: artist}) when artist not in [nil, ""], do: "#{artist}, via"
  defp credit(_image), do: "via"

  @doc """
  A passage from the hosted Bible, under its citation. With no passage (the
  citation could not be found in this translation) the citation stands alone.
  """
  attr :passage, :map, default: nil
  attr :citation, :string, required: true
  attr :label, :string, default: nil
  attr :lines, :boolean, default: false, doc: "one verse to a line, for psalms and canticles"

  def passage(assigns) do
    ~H"""
    <section class="faith-passage">
      <h3 class="faith-passage-head">
        <span :if={@label} class="faith-passage-label">{@label}</span>
        <span class="faith-passage-cite">{(@passage && @passage.citation) || @citation}</span>
      </h3>
      <%= if @passage do %>
        <p class={["faith-verses", @lines && "faith-verses--lines"]}>
          <span :for={{chapter, verse, text} <- @passage.verses} class="faith-verse">
            <sup class="faith-verse-n">{verse_label(@passage, chapter, verse)}</sup>{text}
          </span>
        </p>
        <p :if={@passage.approximate} class="faith-note">
          This book is numbered differently in the Vulgate, so the verses shown may not be exactly those cited ({@citation}).
        </p>
        <p class="faith-passage-more">
          <a href={chapter_path(@passage)}>Read the chapter</a>
        </p>
      <% else %>
        <p class="faith-note">
          This passage could not be found under that citation in the Bible hosted here.
          <a href={~p"/Christ/bible"}>Open the Bible</a>
        </p>
      <% end %>
    </section>
    """
  end

  @doc """
  A prayer most people have by heart, or a passage that is beside the point
  for someone who does: its name, with the words behind a `<details>` that
  is closed until asked for. Pass `text`, or put anything in the slot.
  """
  attr :title, :string, required: true
  attr :what, :string, default: nil, doc: "a quieter word after the name, such as a citation"
  attr :text, :string, default: nil
  slot :inner_block

  def known(assigns) do
    ~H"""
    <details class="faith-known">
      <summary>
        <span>{@title}<span :if={@what} class="faith-known-what">{@what}</span></span>
      </summary>
      <div class="faith-known-body faith-prayer">
        <p :if={@text}>{@text}</p>
        {render_slot(@inner_block)}
      </div>
    </details>
    """
  end

  @doc "Versicle and response, or a line said straight through."
  attr :lines, :list, required: true

  def versicles(assigns) do
    ~H"""
    <p class="faith-versicles">
      <span :for={{who, text} <- @lines} class="faith-versicle">
        <b :if={who} class="faith-versicle-who" aria-hidden="true">{who}.</b>
        {text}
      </span>
    </p>
    """
  end

  @doc "An hour of the Office, from `Web.Liturgy.Hours.office/2` with its passages looked up."
  attr :office, :map, required: true

  def office(assigns) do
    ~H"""
    <div class="faith-office">
      <p :if={@office.note} class="faith-note">{@office.note}</p>
      <%= for part <- @office.parts do %>
        <%= case part.type do %>
          <% :versicle -> %>
            <.versicles lines={part.lines} />
          <% :rubric -> %>
            <p class="faith-rubric">{part.text}</p>
          <% type when type in [:psalm, :canticle] -> %>
            <.passage
              passage={part.passage}
              citation={part.citation}
              label={if type == :psalm, do: "Psalm", else: "Canticle"}
              lines
            />
            <.known title="Glory Be" text={part.doxology} />
          <% :reading -> %>
            <.passage passage={part.passage} citation={part.citation} label="Reading" />
            <p class="faith-rubric">A pause in silence.</p>
          <% :gospel_canticle -> %>
            <.passage
              passage={part.passage}
              citation={part.citation}
              label={"#{part.title} (#{part.latin})"}
              lines
            />
            <.known title="Glory Be" text={part.doxology} />
          <% :prayer -> %>
            <.known title={part.title} text={part.text} />
        <% end %>
      <% end %>
      <p class="faith-colophon">
        The psalms and canticles are those of the four-week psalter for this day, prayed from the Bible hosted here. This is not the official text of the Liturgy of the Hours.
      </p>
    </div>
    """
  end

  @doc "The readings of the day's Masses, with the notes that qualify them."
  attr :masses, :list, required: true
  attr :from, :any, default: nil
  attr :day, :map, required: true
  attr :usa_day, :map, required: true

  def masses(assigns) do
    ~H"""
    <p :if={@day.celebration.title != @usa_day.celebration.title} class="faith-note">
      In the Carmelite calendar today is {@day.celebration.title}, which may have readings of its own in the Order's lectionary. Those are not held here; these are the readings of {@usa_day.celebration.title} in the dioceses of the United States.
    </p>
    <p :if={@from} class="faith-note">
      Taken from the same liturgical day as it fell on {long_date(@from)}, {@from.year}.
    </p>
    <p :if={@masses == []} class="faith-note">
      The readings for this day are not in the lectionary held here.
    </p>
    <div :for={mass <- @masses} class="faith-office">
      <h3 :if={mass.name} class="faith-mass-name">{mass.name}</h3>
      <.passage
        :for={reading <- mass.readings}
        passage={reading.passage}
        citation={reading.citation}
        label={reading.label}
        lines={reading.psalm}
      />
    </div>
    <p class="faith-colophon">
      The passages are those the lectionary appoints; the wording is that of the Bible hosted here, not the translation read in church. Where the lectionary cites part of a verse, the whole verse is given.
    </p>
    """
  end

  @doc "The Angelus, or the Regina Caeli in Easter Time."
  attr :midday, :map, required: true
  attr :season, :atom, required: true

  def midday(assigns) do
    ~H"""
    <div class="faith-office">
      <p :if={@season == :easter} class="faith-note">
        In Easter Time the Regina Caeli is said in place of the Angelus.
      </p>
      <.known title={@midday.title}>
        <.versicles lines={@midday.lines} />
      </.known>
    </div>
    """
  end

  @doc """
  The Rosary as an order of prayer: what is said on which bead, and the five
  mysteries by name. The words of each prayer and the scripture each mystery
  rests on are there for whoever wants them, behind `known/1`.
  """
  attr :set, :map, required: true

  def rosary_text(assigns) do
    assigns =
      assign(assigns,
        prayers:
          for key <- ~w(sign_of_the_cross apostles_creed our_father hail_mary glory_be
                        fatima salve_regina)a do
            {Prayers.title(key), Prayers.text(key)}
          end
      )

    ~H"""
    <div class="faith-office">
      <ol class="faith-order">
        <li>On the crucifix, the Sign of the Cross and the Apostles' Creed.</li>
        <li>One Our Father, three Hail Marys, one Glory Be.</li>
        <li>
          For each mystery: one Our Father, ten Hail Marys, one Glory Be and the Fatima Prayer.
        </li>
        <li>At the end, the Hail, Holy Queen.</li>
      </ol>

      <%= for {mystery, index} <- Enum.with_index(@set.mysteries, 1) do %>
        <h3 class="faith-mystery">
          <span class="faith-mystery-n">{index}</span> {mystery.title}
        </h3>
        <.mystery_scripture mystery={mystery} />
      <% end %>

      <h3 class="faith-mystery">The prayers</h3>
      <div>
        <.known :for={{title, text} <- @prayers} title={title} text={text} />
      </div>
    </div>
    """
  end

  @doc "The passage a mystery rests on, out of the way until it is wanted."
  attr :mystery, :map, required: true

  def mystery_scripture(assigns) do
    ~H"""
    <.known title="Scripture" what={@mystery.citation}>
      <.passage passage={@mystery.passage} citation={@mystery.citation} />
      <p :if={@mystery.note} class="faith-note">{@mystery.note}</p>
    </.known>
    """
  end

  # A passage that runs across chapters shows the chapter with each verse.
  defp verse_label(%{verses: verses}, chapter, verse) do
    {first, _, _} = hd(verses)
    {last, _, _} = List.last(verses)
    if first == last, do: verse, else: "#{chapter}:#{verse}"
  end

  defp chapter_path(%{book: book, verses: [{chapter, verse, _} | _]}) do
    ~p"/Christ/bible/#{book.slug}/#{chapter}" <> "#v#{verse}"
  end
end
