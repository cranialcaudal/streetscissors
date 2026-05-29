defmodule Web.Language.Grammar do
  @moduledoc """
  Interface for checking grammar and spelling via LanguageTool API.
  """

  def check(text) do
    url = "https://api.languagetool.org/v2/check"

    params = [
      text: text,
      language: "en-US",
      enabledOnly: "false"
    ]

    case Req.post(url, form: params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body["matches"]}

      _ ->
        {:error, :request_failed}
    end
  end
end
