defmodule Mix.Tasks.Fitness.Film do
  @shortdoc "Films the exercise wiki's figures that have changed"

  @moduledoc """
  Films the figures of the exercise wiki (`Web.Fitness.Clip`): each one's loop
  drawn as a body in 3D, kept as a short video the exercise's page plays.

      mix fitness.film                    # every figure with no current film
      mix fitness.film plank push-ups     # only these
      mix fitness.film --all              # everything again (a new look)
      mix fitness.film --to DIR           # into DIR instead of this
                                          # environment's uploads/figures
      mix fitness.film --stills DIR plank # a picture of each pose, to look
                                          # at before filming

  The live site keeps its uploads outside the checkout, so its films are made
  with `--to`, or with `UPLOADS_PATH` set as the service has it:

      UPLOADS_PATH=/path/to/uploads mix fitness.film

  It needs `node`, `google-chrome` (or `CHROME_BIN`) and `ffmpeg` on the PATH,
  and takes about 45 seconds a figure. The app is not started. Films are
  content, not code: nothing has to be deployed for the pages to play them.
  """
  use Mix.Task

  @impl true
  def run(args) do
    {opts, slugs} =
      OptionParser.parse!(args, strict: [all: :boolean, to: :string, stills: :string])

    Mix.Task.run("app.config")
    if opts[:stills], do: stills(slugs, opts[:stills]), else: film(slugs, opts)
  end

  defp stills([], _to),
    do: Mix.raise("--stills wants the figures to draw: mix fitness.film --stills DIR plank")

  defp stills(slugs, to) do
    case Web.Fitness.Clip.stills(slugs, to) do
      {:ok, files} -> Enum.each(files, fn file -> Mix.shell().info(file) end)
      {:error, why} -> Mix.raise(why)
    end
  end

  defp film(slugs, opts) do
    to =
      cond do
        opts[:to] -> opts[:to]
        path = System.get_env("UPLOADS_PATH") -> Path.join(path, "figures")
        true -> Web.Fitness.Clip.dir()
      end

    Mix.shell().info("Filming into #{to}")

    film =
      [to: to, all: opts[:all] || false, say: fn line -> Mix.shell().info(line) end]
      |> then(&if(slugs == [], do: &1, else: Keyword.put(&1, :only, slugs)))
      |> Web.Fitness.Clip.film()

    for {slug, why} <- film.refused, do: Mix.shell().error("#{slug}: not filmed: #{why}")

    Mix.shell().info(
      "#{length(film.filmed)} filmed, #{length(film.current)} already current, " <>
        "#{length(film.refused)} not filmed."
    )

    if film.refused != [], do: exit({:shutdown, 1})
  end
end
