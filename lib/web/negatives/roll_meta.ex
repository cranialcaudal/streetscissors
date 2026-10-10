defmodule Web.Negatives.RollMeta do
  @moduledoc """
  What the author knows about a roll that the film cannot say: when it was
  shot, in what camera, on what stock, where, and a note. Kept as `roll.json`
  in the roll's own folder, beside its strips, so it travels with the roll
  and is mirrored with it.

  **When it was shot is as precise as is known**: a year (`2023`), a month
  (`2023-06`) or a day (`2023-06-14`). A roll found in a drawer has a year at
  best, and a guessed day would be a false one. The roll is still *filed* by
  the day it was scanned (its folder's name, the almanac, the day pages);
  this is only said beside it.

  The file may hold other keys (the `negatives` command once wrote the
  catalog's row there); they are kept as they are.
  """

  @fields ~w(shot camera film place notes)
  @limits %{"camera" => 80, "film" => 80, "place" => 120, "notes" => 2000}

  @months ~w(January February March April May June July August September October November December)

  @doc "The roll's metadata as `%{shot:, camera:, film:, place:, notes:}`, nil where unset."
  def read(roll_dir) do
    doc = doc(roll_dir)
    Map.new(@fields, fn field -> {String.to_atom(field), text(doc[field])} end)
  end

  defp doc(roll_dir) do
    with {:ok, body} <- File.read(Path.join(roll_dir, "roll.json")),
         {:ok, %{} = doc} <- Jason.decode(body) do
      doc
    else
      _ -> %{}
    end
  end

  defp text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp text(value) when is_integer(value), do: Integer.to_string(value)
  defp text(_value), do: nil

  @doc "Whether nothing has been said about the roll."
  def empty?(meta), do: Enum.all?(Map.values(meta), &is_nil/1)

  @doc """
  Tidies what a form sent (string keys) into metadata: trimmed, cut to
  length, blanks as nil. `{:ok, meta}`, or `{:error, text}` when the shot
  date is not a year, a month or a day that exists.
  """
  def cast(params) when is_map(params) do
    shot = text(params["shot"])

    if shot == nil or valid_shot?(shot) do
      meta =
        Map.new(@fields, fn
          "shot" -> {:shot, shot}
          field -> {String.to_atom(field), text(params[field]) |> cut(@limits[field])}
        end)

      {:ok, meta}
    else
      {:error,
       "“#{shot}” is not a date. Write a year (2023), a month (2023-06) or a day (2023-06-14)."}
    end
  end

  defp cut(nil, _limit), do: nil
  defp cut(value, limit), do: String.slice(value, 0, limit)

  defp valid_shot?(shot) do
    case shot do
      <<year::binary-size(4)>> ->
        year =~ ~r/\A(18|19|20)\d\d\z/

      <<year::binary-size(4), "-", month::binary-size(2)>> ->
        match?({:ok, _}, Date.from_iso8601("#{year}-#{month}-01"))

      <<_::binary-size(10)>> ->
        match?({:ok, _}, Date.from_iso8601(shot))

      _ ->
        false
    end
  end

  @doc """
  Writes metadata into the roll's `roll.json`, leaving any other key there.
  A field set to nil is removed. The folder must exist: a roll not begun has
  nowhere to keep it yet.
  """
  def write(roll_dir, meta) do
    if File.dir?(roll_dir) do
      doc =
        Enum.reduce(@fields, doc(roll_dir), fn field, doc ->
          case Map.get(meta, String.to_atom(field)) do
            nil -> Map.delete(doc, field)
            value -> Map.put(doc, field, value)
          end
        end)

      path = Path.join(roll_dir, "roll.json")

      if doc == %{} do
        File.rm(path)
      else
        File.write!(path <> ".partial", Jason.encode_to_iodata!(doc, pretty: true))
        File.rename!(path <> ".partial", path)
      end

      :ok
    else
      {:error, :no_folder}
    end
  end

  @doc """
  When the roll was shot, as it reads: `"2023"`, `"June 2023"`, `"June 14,
  2023"`. nil when unset.
  """
  def shot_line(%{shot: shot}), do: shot_line(shot)
  def shot_line(nil), do: nil

  def shot_line(<<year::binary-size(4)>>), do: year

  def shot_line(<<year::binary-size(4), "-", month::binary-size(2)>>),
    do: "#{month_name(month)} #{year}"

  def shot_line(<<year::binary-size(4), "-", month::binary-size(2), "-", day::binary-size(2)>>),
    do: "#{month_name(month)} #{String.to_integer(day)}, #{year}"

  def shot_line(other) when is_binary(other), do: other

  defp month_name(month), do: Enum.at(@months, String.to_integer(month) - 1, month)

  @doc "Camera, stock and place, the ones there are, as one line. nil when none."
  def gear_line(meta) do
    case Enum.reject([meta.camera, meta.film, meta.place], &is_nil/1) do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end
end
