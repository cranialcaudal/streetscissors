defmodule Web.Contact do
  import Ecto.Query, warn: false
  alias Web.Repo
  alias Web.Contact.Message

  def create_message(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  def list_messages do
    from(m in Message, order_by: [desc: m.inserted_at])
    |> Repo.all()
  end

  def list_messages(status) when is_binary(status) do
    from(m in Message, where: m.status == ^status, order_by: [desc: m.inserted_at])
    |> Repo.all()
  end

  @doc "Messages per status (`inbox`, `attention`, `archive`); empty statuses are absent."
  def count_by_status do
    from(m in Message, group_by: m.status, select: {m.status, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  def mark_as_read(id) do
    case Repo.get(Message, id) do
      nil ->
        {:error, :not_found}

      message ->
        Ecto.Changeset.change(message, read: true)
        |> Repo.update()
    end
  end

  def get_message(id), do: Repo.get(Message, id)

  def update_status(id, status) do
    case Repo.get(Message, id) do
      nil ->
        {:error, :not_found}

      message ->
        # auto-mark as read if moving out of inbox?
        read = if status != "inbox", do: true, else: message.read

        Ecto.Changeset.change(message, status: status, read: read)
        |> Repo.update()
    end
  end

  def delete_message(id) do
    case Repo.get(Message, id) do
      nil -> {:error, :not_found}
      message -> Repo.delete(message)
    end
  end

  def change_message(%Message{} = message, attrs \\ %{}) do
    Message.changeset(message, attrs)
  end
end
