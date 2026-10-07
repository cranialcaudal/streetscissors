defmodule Web.Bible.Versification do
  @moduledoc """
  Carries a citation from the lectionary's numbering to the hosted text's.

  The lectionary and the psalter cite the Bible as the New American Bible
  numbers it, which follows the Hebrew. A Bible translated from the Vulgate
  (the CPDV, the Douay) numbers four books differently enough to land on the
  wrong passage:

    * **Psalms** run one behind from 10 to 147, because the Vulgate joins
      9 and 10, and 114 and 115, and splits 116 and 147.
    * **Joel** has three chapters, not four: the lectionary's chapter 3 is the
      end of the Vulgate's chapter 2.
    * **Malachi** has four chapters, not three: 3:19-24 is the Vulgate's 4:1-6.
    * **Zechariah** ends its first chapter four verses later, so chapter 2
      runs four behind.

  Those are mapped exactly. Two cases are not:

    * **Esther** is arranged differently in each Bible, and a citation into it
      is refused rather than guessed (`{:error, :versification}`).
    * **Tobit, Judith and Sirach** are a different recension in the Vulgate,
      with verse numbers that drift within a chapter. They are passed through
      and marked `approximate`, so the page can say so.

  A text that declares Hebrew numbering is passed through untouched.
  """

  @approximate ~w(tobit judith sirach)

  def map(parsed, :hebrew), do: {:ok, Map.put(parsed, :approximate, false)}

  def map(%{book: "esther"}, :vulgate), do: {:error, :versification}

  def map(%{book: book, ranges: ranges} = parsed, :vulgate) do
    ranges =
      case book do
        "psalms" -> Enum.flat_map(ranges, &psalm/1)
        "joel" -> Enum.map(ranges, &both(&1, fn point -> joel(point) end))
        "malachi" -> Enum.map(ranges, &both(&1, fn point -> malachi(point) end))
        "zechariah" -> Enum.map(ranges, &both(&1, fn point -> zechariah(point) end))
        _ -> ranges
      end

    {:ok, %{parsed | ranges: ranges} |> Map.put(:approximate, book in @approximate)}
  end

  defp both({from, to}, fun), do: {fun.(from), fun.(to)}

  defp joel({3, v}) when is_integer(v), do: {2, v + 27}
  defp joel({4, v}), do: {3, v}
  defp joel(point), do: point

  defp malachi({3, v}) when is_integer(v) and v >= 19, do: {4, v - 18}
  defp malachi(point), do: point

  defp zechariah({2, v}) when is_integer(v) and v <= 4, do: {1, v + 17}
  defp zechariah({2, v}) when is_integer(v), do: {2, v - 4}
  defp zechariah(point), do: point

  # A range that stays inside one psalm, which is every range a psalter or a
  # lectionary prints.
  defp psalm({{c, v1}, {c, v2}}) do
    case c do
      c when c <= 8 -> [{{c, v1}, {c, v2}}]
      9 -> [{{9, v1 || 1}, {9, v2 || 21}}]
      10 -> [{{9, (v1 || 1) + 21}, {9, (v2 || 18) + 21}}]
      c when c <= 113 -> [{{c - 1, v1}, {c - 1, v2}}]
      114 -> [{{113, v1 || 1}, {113, v2 || 8}}]
      115 -> [{{113, (v1 || 1) + 8}, {113, (v2 || 18) + 8}}]
      116 -> split(v1, v2, 9, 114, 115, 19)
      c when c <= 146 -> [{{c - 1, v1}, {c - 1, v2}}]
      147 -> split(v1, v2, 11, 146, 147, 20)
      c -> [{{c, v1}, {c, v2}}]
    end
  end

  defp psalm(range), do: [range]

  # The Hebrew psalm is two in the Vulgate: verses up to `cut` are the first,
  # and the rest are the second, numbered again from 1.
  defp split(nil, nil, _cut, first, second, _last) do
    [{{first, nil}, {first, nil}}, {{second, nil}, {second, nil}}]
  end

  defp split(v1, v2, cut, first, second, last) do
    v1 = v1 || 1
    v2 = v2 || last

    head = if v1 <= cut, do: [{{first, v1}, {first, min(v2, cut)}}], else: []
    tail = if v2 > cut, do: [{{second, max(v1, cut + 1) - cut}, {second, v2 - cut}}], else: []
    head ++ tail
  end
end
