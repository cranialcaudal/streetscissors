defmodule Web.WebmentionsTestResolver do
  @moduledoc """
  Stands in for DNS when the suite verifies webmentions: hosts under
  `.internal` resolve to a private address (to exercise the SSRF guard), and
  everything else to one public address. Nothing reaches a real resolver.
  """

  def resolve("localhost"), do: [{127, 0, 0, 1}]

  def resolve(host) do
    if String.ends_with?(host, ".internal"), do: [{10, 0, 0, 5}], else: [{93, 184, 216, 34}]
  end
end
