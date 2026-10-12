defmodule Espalier.Accounts.UserNotifierTest do
  @moduledoc """
  The account mails of task 0004 (ASVS 1.3.7): each mail is a fixed
  plain-text string, and a value enters it only by interpolation at run
  time. A display name or a provider label in the syntax of an Elixir
  interpolation or of an EEx tag therefore reaches the text body literally
  and is not evaluated.
  """
  use ExUnit.Case, async: true

  alias Espalier.Accounts.UserNotifier

  @template ~S(#{1+1} <%= 1 %>)

  defp user, do: %{email: "ada@example.org", display_name: @template}

  test "the invitation holds a display name with template syntax as text" do
    email = UserNotifier.invitation_email(user(), "token")

    assert email.text_body =~ "Hi #{@template},"
    assert email.text_body =~ ~S(#{1+1})
    assert email.text_body =~ "<%= 1 %>"
    refute email.text_body =~ "Hi 2"
  end

  test "a delivered notice holds the display name and the provider label as text" do
    label = ~S(<%= :provider %> #{:label})

    assert {:ok, email} = UserNotifier.deliver_identity_linked(user(), label)
    assert_received {:email, %Swoosh.Email{}}

    assert email.text_body =~ "Hi #{@template},"
    assert email.text_body =~ "#{label} was linked to your Espalier account"
    assert email.text_body =~ "You now sign in\nthrough #{label}."
    refute email.text_body =~ "Hi 2"
  end
end
