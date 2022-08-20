defmodule Delta.Change do
  @moduledoc """
  Internal API for working with changes
  """

  @typedoc """
  Represents a change made by user to a document.

  ## Fields
    - `:id` – UUIDv4 in default form. **Required**
    - `:previous_change_id` – UUIDv4 in default form. Used to order changes of particular document to form a history. **Required**
    - `:document_id` – UUIDv4 in default from. **Required**
    - `:order` – Order of change in document's history. *Autogenerated*
    - `:autosquash?` – Should the change be squashed with the last change with `:delta` with same paths
    - `:delta` – Changes to document in RFC 6092 Json delta format. **Required**
    - `:reverse_delta` – Json delta to revert document to previous state. Autogenerated
    - `:meta` – any metadata, e. g. user who made it
    - `:updated_at` – when the change was updated.
  """
  @type t :: %__MODULE__{
          id: Delta.uuid4(),
          previous_change_id: Delta.uuid4(),
          document_id: Delta.uuid4(),
          order: non_neg_integer,
          autosquash?: boolean,
          delta: rfc_6092 :: any,
          reverse_delta: rfc_6092 :: any,
          meta: any,
          updated_at: DateTime.t()
        }

  defstruct [
    :id,
    :previous_change_id,
    :document_id,
    :order,
    :autosquash?,
    :delta,
    :reverse_delta,
    :meta,
    :updated_at
  ]

  @doc """
  Validates change according to the following rules:

  - `:id` – must be UUIDv4 in default form
  - `:previous_change_id` – must be UUIDv4 in default form of previous change or `nil`
  - `:delta` – must be valid RFC 6092 Json delta
  - `:document_id` – must be valid UUIDv4 of document in default form.
  """
  @spec validate(t() | any()) :: {:ok, t()} | {:error, Delta.Errors.Validation.t()}
  def validate(change), do: nil

  @doc """
  Lists changes of `Delta.Documnent` with `id = document_id`. Expensive operation.
  If document does not exists, returns empty list

  Aborts if document with `id = document_id` does not exist.
  """
  @spec list(Delta.Document.t() | Delta.uuid4()) ::
          {:atomic, [t]} | {:aborted, Delta.Errors.DoesNotExist.t()}

  def list(document_id), do: nil

  @doc """
  Lists changes from newest – `from_change_id` to oldest – `to_change_id`.

  Aborts with `%Delta.Errors.DoesNotExist{}` if change with `id = from_change_id` or `id = to_change_id` does not exist.
  """
  @spec list(t() | Delta.uuid4(), t() | Delta.uuid4()) ::
          {:atomic, [t]} | {:aborted, Delta.Errors.DoesNotExist.t()}

  def list(from_change_id, to_change_id), do: nil

  @spec get(t() | Delta.uuid4()) :: {:atomic, t} | {:aborted, Delta.Errors.DoesNotExist.t()}
  def get(change_id), do: nil

  @doc """
  Creates change.

  Aborts with `%Delta.Errors.DoesNotExist{}` if
  change with `id = change.previous_change_id`
  or document with `id = change.document_id` does not exist.

  Aborts with `%Delta.Errors.AlreadyExists{}` if change with `id = change.id` already exists.
  """
  @spec create(t() | Delta.uuid4()) ::
          {:atomic, t} | {:aborted, Delta.Errors.DoesNotExist.t() | Delta.Errors.AlreadyExist.t()}

  def create(change), do: nil

  @doc """
  Updates change.

  Aborts with `%Delta.Errors.DoesNotExist{}` if
  change with `id = change.previous_change_id`
  or document with `id = change.document_id`
  or change with `id = change.id` does not exist.
  """
  @spec update(t() | Delta.uuid4()) :: {:atomic, t} | {:aborted, Delta.Errors.DoesNotExist.t()}
  def update(change, attrs \\ []), do: nil

  @doc """
  Squashes Delta.Change with `id = change_id_2` into one with `id = change_id_1`.
  Resulting change will have metadata of the second change.

  Aborts with `%Delta.Errors.DoesNotExist{}` if change with `id = change_id_1` or `id = change_id_2` does not exist.
  """
  @spec squash(t() | Delta.uuid4(), t | Delta.uuid4()) ::
          {:atomic, t} | {:aborted, Delta.Errors.DoesNotExist.t()}
  def squash(change_id_1, change_id_2), do: nil

  @doc """
  Deletes change with `id = change_id`.
  Returns {:atomic, :ok} even if change with `id = change_id` does not exist.
  """
  @spec delete(t() | Delta.uuid4()) :: {:atomic, :ok}
  def delete(change_id), do: nil
end
