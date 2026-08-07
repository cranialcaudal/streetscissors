defmodule WebWeb.Captcha do
  @moduledoc """
  A small human check for the public write forms (guestbook, contact,
  newsletter subscribe).

  It asks a question whose answer is not present in the question. The previous
  version rendered `"Solve for x: x + 3 = 8"` — both operands were on the page,
  so `/x \\+ (\\d+) = (\\d+)/` plus a subtraction solved it every time, which
  is no check at all.

  The answer never leaves the server: it lives in socket assigns and is
  regenerated on every attempt, so an answer cannot be replayed. This is a
  speed bump for commodity spam, not a defence against a targeted attacker —
  rate limiting (`Web.RateLimit`) is what bounds that.
  """

  @words ~w(paper ink shutter darkroom bicycle valley film grain silver poppy)
  @numbers %{
    1 => "one",
    2 => "two",
    3 => "three",
    4 => "four",
    5 => "five",
    6 => "six",
    7 => "seven",
    8 => "eight",
    9 => "nine"
  }

  @doc """
  Builds a fresh challenge as `%{question: String.t(), answer: String.t()}`.

  Every challenge type holds one invariant, asserted in the tests: **the answer
  never appears anywhere in the question text**. That rules out otherwise
  appealing forms — "which of these does not belong: otter, crimson, badger"
  and "what is letter three of \\"shutter\\"" both print their own answer, so a
  solver that simply tries each substring of the question beats them.
  """
  def new do
    case Enum.random([:sum, :letter_count]) do
      :sum -> sum_challenge()
      :letter_count -> letter_count_challenge()
    end
  end

  # Operands spelled out, answer a numeral: nothing for a \d+ scrape to grab.
  defp sum_challenge do
    a = Enum.random(1..9)
    b = Enum.random(1..9)

    %{
      question: "What is #{@numbers[a]} plus #{@numbers[b]}? (answer with a number)",
      answer: to_string(a + b)
    }
  end

  # The word is shown but its length is not, so the answer is absent from the
  # question while still being obvious to a person.
  defp letter_count_challenge do
    word = Enum.random(@words)

    %{
      question: "How many letters are in the word \"#{word}\"? (answer with a number)",
      answer: word |> String.length() |> to_string()
    }
  end

  @doc """
  True when the submitted answer matches. Comparison is trimmed and
  case-insensitive so a correct human answer is never rejected on formatting.
  """
  def validate(user_answer, actual_answer)
      when is_nil(user_answer) or is_nil(actual_answer),
      do: false

  def validate(user_answer, actual_answer) do
    normalize(user_answer) == normalize(actual_answer) and normalize(actual_answer) != ""
  end

  defp normalize(value), do: value |> to_string() |> String.trim() |> String.downcase()
end
