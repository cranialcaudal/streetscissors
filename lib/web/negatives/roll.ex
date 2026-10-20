defmodule Web.Negatives.Roll do
  @moduledoc "A roll's number as the archive writes it."

  @doc """
  Zero-pads a roll token to three digits, the archive's own convention
  (`roll013_2026-08-03_120_bw`): `13`, `"13"` and `"roll013"` are all `"013"`.
  Anything unrecognisable is passed through rather than mangled, so the
  route's own parser decides what is valid.
  """
  def pad(roll) do
    case Regex.run(~r/\A(?:roll)?0*(\d{1,4})\z/i, to_string(roll)) do
      [_, digits] -> String.pad_leading(digits, 3, "0")
      _ -> to_string(roll)
    end
  end
end
