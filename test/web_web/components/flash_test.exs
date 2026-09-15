defmodule WebWeb.FlashTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias WebWeb.CoreComponents

  # Tailwind runs with source(none), so the generator's daisyUI toast/alert
  # classes never existed here and the notice printed as bare text. Its
  # styles are hand-written in assets/css/flash.css.
  test "a notice carries only hand-written classes and announces politely" do
    html = render_component(&CoreComponents.flash/1, kind: :info, flash: %{"info" => "Saved."})

    assert html =~ ~s(class="flash-notice flash-notice--info")
    assert html =~ ~s(role="status")
    assert html =~ ~s(<p class="flash-notice-message">Saved.</p>)
    refute html =~ ~r/\b(toast|alert-info|text-wrap|shrink-0)\b/
  end

  test "an error is an alert" do
    html = render_component(&CoreComponents.flash/1, kind: :error, flash: %{"error" => "No."})

    assert html =~ ~s(class="flash-notice flash-notice--error")
    assert html =~ ~s(role="alert")
  end

  test "the close control is a named button" do
    html = render_component(&CoreComponents.flash/1, kind: :info, flash: %{"info" => "Saved."})

    assert html =~ ~s(class="flash-notice-close")
    assert html =~ ~s(aria-label="close")
  end

  test "nothing renders without a message" do
    html = render_component(&CoreComponents.flash/1, kind: :info, flash: %{})

    assert String.trim(html) == ""
  end
end
