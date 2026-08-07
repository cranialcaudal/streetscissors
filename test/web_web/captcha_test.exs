defmodule WebWeb.CaptchaTest do
  use ExUnit.Case, async: true

  alias WebWeb.Captcha

  test "the question never contains its own answer" do
    # The previous captcha rendered "Solve for x: x + 3 = 8" — both operands
    # were on the page, so a regex plus a subtraction solved it every time.
    for _ <- 1..300 do
      %{question: question, answer: answer} = Captcha.new()
      refute String.contains?(String.downcase(question), String.downcase(answer))
    end
  end

  test "no arabic numerals appear in any question" do
    # Every answer is a numeral, so a question containing one at all would give
    # a \\d+ scrape something to try.
    for _ <- 1..300 do
      refute Regex.match?(~r/\d/, Captcha.new().question)
    end
  end

  test "both challenge types appear" do
    questions = for _ <- 1..300, do: Captcha.new().question

    assert Enum.any?(questions, &String.contains?(&1, "plus"))
    assert Enum.any?(questions, &String.contains?(&1, "How many letters"))
  end

  test "validate/2 accepts the right answer regardless of case and padding" do
    %{answer: answer} = challenge = Captcha.new()

    assert Captcha.validate(answer, challenge.answer)
    assert Captcha.validate("  #{String.upcase(answer)}  ", challenge.answer)
  end

  test "validate/2 rejects wrong, blank and nil answers" do
    refute Captcha.validate("definitely-wrong", "seven")
    refute Captcha.validate(nil, "seven")
    refute Captcha.validate("seven", nil)
    refute Captcha.validate("", "")
    refute Captcha.validate("   ", "")
  end

  test "successive challenges vary" do
    questions = for _ <- 1..50, do: Captcha.new().question
    assert length(Enum.uniq(questions)) > 1
  end
end
