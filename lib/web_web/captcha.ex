defmodule WebWeb.Captcha do
  def new do
    x = Enum.random(1..10)
    constant = Enum.random(1..10)
    total = x + constant

    question = "Solve for x: x + #{constant} = #{total}"

    %{
      question: question,
      answer: to_string(x)
    }
  end

  def validate(user_answer, actual_answer) when is_nil(user_answer) or is_nil(actual_answer),
    do: false

  def validate(user_answer, actual_answer) do
    String.trim(to_string(user_answer)) == to_string(actual_answer)
  end
end
