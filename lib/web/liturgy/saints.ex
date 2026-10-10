defmodule Web.Liturgy.Saints do
  @moduledoc """
  A short life and a picture for the saints and feasts of the calendar, kept
  on the site (`priv/liturgy/saints.json`, keyed by the calendar's identifier).

  The lives are the opening summaries of the English Wikipedia articles, which
  are licensed CC BY-SA 4.0: each is shown with its source, and a celebration
  of several saints (Saints Joachim and Anne) carries one for each. The
  pictures are the articles' lead images, taken only where Wikimedia Commons
  records them as public domain or under a Creative Commons licence, and
  shown with their author and licence. They live in
  `priv/static/images/saints/`, which is not in the repository, so a picture
  whose file is absent is simply left out.

  Eight entries of the Order's calendar have no article and so no life here.
  """

  @type life :: %{name: String.t(), text: String.t(), url: String.t()}

  @doc "`%{lives: [life], image: map | nil}` for a calendar identifier, or `nil`."
  def get(nil), do: nil

  def get(symbol) do
    with %{} = saint <- data()[symbol] do
      %{saint | image: present(saint.image)}
    end
  end

  @doc "Every entry that has a life, as `{identifier, [name]}`, for the site search."
  def names do
    for {symbol, %{lives: [_ | _] = lives}} <- data(), do: {symbol, Enum.map(lives, & &1.name)}
  end

  defp present(%{file: file} = image) do
    path = Application.app_dir(:web, Path.join("priv/static/images/saints", file))
    if File.exists?(path), do: image
  end

  defp present(nil), do: nil

  defp data do
    key = {__MODULE__, :data}

    case :persistent_term.get(key, nil) do
      nil ->
        data = load()
        :persistent_term.put(key, data)
        data

      data ->
        data
    end
  end

  defp load do
    Application.app_dir(:web, "priv/liturgy/saints.json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.new(fn {symbol, saint} ->
      lives = for l <- saint["lives"], do: %{name: l["name"], text: l["text"], url: l["url"]}

      image =
        with %{} = i <- saint["image"] do
          %{
            file: i["file"],
            width: i["width"],
            height: i["height"],
            artist: i["artist"],
            license: i["license"],
            license_url: i["license_url"],
            source: i["source"]
          }
        end

      {symbol, %{lives: lives, image: image}}
    end)
  end
end
