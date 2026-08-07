defmodule Web.Newsletter.Generator do
  alias Web.Newsletter.Draft
  alias Web.Repo

  # For Gemini API
  @api_base "https://generativelanguage.googleapis.com/v1beta/models"
  @model "gemini-1.5-flash-latest"

  def generate_weekly_draft do
    # 1. Gather content
    content = gather_weekly_content()

    # 2. Call AI
    {subject, body} = generate_ai_draft(content)

    # 3. Save Draft
    %Draft{}
    |> Draft.changeset(%{
      subject: subject,
      body: body,
      status: "draft"
    })
    |> Repo.insert()
  end

  defp gather_weekly_content do
    one_week_ago = NaiveDateTime.utc_now() |> NaiveDateTime.add(-7 * 24 * 60 * 60)

    blog_posts =
      Web.Blog.list_posts()
      |> Enum.filter(&(NaiveDateTime.compare(&1.mtime, one_week_ago) == :gt))
      |> Enum.map(&"- Blog: #{&1.title}")
      |> Enum.join("\n")

    "Here is the content published this week:\n\n" <> blog_posts
  end

  defp generate_ai_draft(content) do
    api_key = System.get_env("GEMINI_API_KEY")

    if is_nil(api_key), do: raise("GEMINI_API_KEY is missing")

    prompt = """
    You are writing a weekly newsletter for 'streetscissors', a personal website about writing, photography, and fitness.

    Please write a newsletter summarising the following content published this week.
    The tone should be reflective, slightly philosophical, but welcoming.

    #{content}

    If there is NO content, write a short generic reflection on the passage of time and the value of silence.

    Output the response in JSON format (do not use markdown code blocks) with two keys: "subject" and "body".
    The "body" should be HTML.
    """

    case Req.post("#{@api_base}/#{@model}:generateContent?key=#{api_key}",
           json: %{
             contents: [%{parts: [%{text: prompt}]}]
           }
         ) do
      {:ok,
       %{body: %{"candidates" => [%{"content" => %{"parts" => [%{"text" => raw_json} | _]}} | _]}}} ->
        # Clean up markdown if Gemini wraps it
        clean_json =
          raw_json |> String.replace("```json", "") |> String.replace("```", "") |> String.trim()

        case Jason.decode(clean_json) do
          {:ok, %{"subject" => s, "body" => b}} -> {s, b}
          # Fallback
          _ -> {"Weekly Update", raw_json}
        end

      error ->
        IO.inspect(error, label: "AI Gen Error")
        {"Draft Generation Failed", "Could not generate draft. Error details in logs."}
    end
  end
end
