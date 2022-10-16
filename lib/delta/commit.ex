defmodule Delta.Commit do
  @moduledoc """
  Internal commits API

  An interface to work on top of `Delta.DataLayer` which should also implement `Delta.Commit`
  """

  alias Delta.DataLayer
  alias Delta.Validators
  alias Delta.Errors.{Validation, DoesNotExist, AlreadyExist, Conflict}

  @typedoc """
  Represents a commit made by user to a document.

  ## Fields
    - `:id` – UUIDv4 in default form. **Required**
    - `:previous_commit_id` – UUIDv4 in default form. Used to order commits of particular document to form a history. **Required**
    - `:document_id` – UUIDv4 in default from. **Required**
    - `:order` – Order of commit in document's history. *Autogenerated*
    - `:autosquash?` – Should the commits be squashed with the last commit with `:patch` with same paths
    - `:patch` – Changes to document in RFC 6902 json patch format. **Required**
    - `:reverse_patch` – RFC 6902 json patch to revert document to previous state. Autogenerated
    - `:meta` – any metadata, e. g. user who made it
    - `:updated_at` – when the commit was updated.

  ## Autosquashing
  Autosquashing is delta's feature for continuous and frequent document updates. It reduces the number of commits by squashing (see `Delta.Commit.squash/2`).
  If there will be a commit with `autosquahs?: false` and its delta will have any path which is being autosquahed at the moment, the commit will not be squashed.
  In order for two commits to be autosquashed, they must be marked `autosquash?: true` and have `delta` with same paths.
  For autosquash commit no checks of `previous_commit_id` are performed.
  """
  @type t() :: %__MODULE__{
          id: Delta.uuid4(),
          previous_commit_id: Delta.uuid4() | nil,
          document_id: Delta.uuid4(),
          order: non_neg_integer | nil,
          autosquash?: boolean | nil,
          patch: Delta.Json.Patch.t(),
          reverse_patch: Delta.Json.Patch.t() | nil,
          meta: any,
          updated_at: DateTime.t() | nil
        }

  @type id() :: Delta.uuid4() | t()

  defstruct [
    :id,
    :previous_commit_id,
    :document_id,
    :order,
    :autosquash?,
    :patch,
    :reverse_patch,
    :meta,
    :updated_at
  ]

  @doc """
  Same as `Delta.Commit.list/1`, but returns data with continuation
  """
  @callback list(DataLayer.layer_id(), continuation? :: boolean()) ::
              {:atomic, [t()], DataLayer.continuation()}

  @doc """
  Same as `Delta.Commit.list/2`, but returns data with continuation
  """
  @callback list(DataLayer.layer_id(), id() | nil, id() | nil, continuation? :: boolean()) ::
              {:atomic, [t()], DataLayer.continuation()}

  @doc """
  Same as `Delta.Commit.get/1`, but returns data with continuation
  """
  @callback get(DataLayer.layer_id(), id(), continuation? :: boolean()) ::
              {:atomic, t(), DataLayer.continuation()}
              | {:aborted, DoesNotExist.t(), DataLayer.continuation()}

  @doc """
  Same as Delta.Commit.write/1, but returns data with continuation
  """
  @callback write(DataLayer.layer_id(), t(), continuation? :: boolean()) ::
              {:atomic, t(), DataLayer.continuation()}
              | {:aborted, DoesNotExist.t() | AlreadyExist.t(), DataLayer.continuation()}

  @doc """
  Same as Delta.Commit.write_many/1, but returns data with continuation
  """
  @callback write_many(DataLayer.layer_id(), [t()], continuation? :: boolean()) ::
              {:atomic, [t()], DataLayer.continuation()}
              | {:aborted, DoesNotExist.t() | AlreadyExist.t(), DataLayer.continuation()}
  @doc """
  Same as `Delta.Commit.squash/2`, but returns data with continuation
  """
  @callback squash(DataLayer.layer_id(), id(), id(), continuation? :: boolean()) ::
              {:atomic, t(), DataLayer.continuation()}
              | {:aborted, DoesNotExist.t(), DataLayer.continuation()}
  @doc """
  Same as `Delta.Commit.delete/1`, but returns data with continuation
  """
  @callback delete(DataLayer.layer_id(), id(), continuation? :: boolean()) ::
              {:atomic, :ok, DataLayer.continuation()}

  @doc """
  Validates commit according to the following rules:

  - `:id` – must be UUIDv4 in default form
  - `:previous_commit_id` – must be UUIDv4 in default form of previous commit or `nil`
  - `:patch` – must be valid RFC 6092 Json delta
  - `:document_id` – must be valid UUIDv4 of document in default form.

  Note: other functions expect valid input, therefor before passing data to them it should be validated.
  """

  @spec validate(t() | any()) :: {:ok, t()} | {:error, Validation.t()}
  def validate(
        %__MODULE__{
          id: id,
          previous_commit_id: previous_commit_id,
          document_id: document_id,
          patch: delta
        } = c
      ) do
    with :ok <-
           Validators.uuid4(id, %Validation{struct: __MODULE__, field: :id}),
         :ok <-
           Validators.maybe_uuid4(
             previous_commit_id,
             %Validation{struct: __MODULE__, field: :previous_commit_id}
           ),
         :ok <-
           Validators.uuid4(document_id, %Validation{struct: __MODULE__, field: :document_id}),
         :ok <-
           Validators.json_patch(delta, %Validation{struct: __MODULE__, field: :patch}),
         :ok <- cyclic_reference(c) do
      {:ok, c}
    end
  end

  def validate(x) do
    {:error, %Validation{struct: __MODULE__, expected: "Value to be %#{__MODULE__}{}", got: x}}
  end

  defp cyclic_reference(%__MODULE__{id: id, previous_commit_id: id}) do
    {
      :error,
      %Validation{
        struct: __MODULE__,
        field: :previous_commit_id,
        got: "cyclic reference",
        expected: ":id to be not equal to :previous_commit_id"
      }
    }
  end

  defp cyclic_reference(_), do: :ok

  @doc """
  Validates commits according to the following rules:

  - Commits must be sequential, i. e. `commit[i].id = commit[i + 1].previous_id`
  - All commits must have same `:document_id`
  - Each commit must be valid (See `validate/1`)
  """
  @spec validate_many([t() | any()]) :: {:ok, [t()]} | {:error, Validation.t()}
  def validate_many([]), do: {:ok, []}

  def validate_many([first | commits]) do
    order =
      Enum.reduce(commits, validate(first), fn
        %__MODULE__{previous_commit_id: id, document_id: d} = c,
        {:ok, %__MODULE__{id: id, document_id: d}} ->
          validate(c)

        %__MODULE__{document_id: d}, {:ok, %__MODULE__{document_id: d}} ->
          {
            :error,
            %Validation{
              struct: __MODULE__,
              field: :previous_commit_id,
              expected: "list of commits ordered from old to new"
            }
          }

        %__MODULE__{document_id: d}, {:ok, %__MODULE__{}} ->
          {
            :error,
            %Validation{
              struct: __MODULE__,
              field: :document_id,
              expected: ":document_id to be same for all commits",
              got: d
            }
          }

        _, {:error, _} = e ->
          e
      end)

    first_previous =
      if Enum.all?(commits, &(&1.id != first.previous_commit_id)),
        do: :ok,
        else: {
          :error,
          %Validation{
            struct: __MODULE__,
            field: :previous_commit_id,
            expected: "first commit not to be the next commit of any in list"
          }
        }

    with {:ok, _} <- order,
         :ok <- first_previous do
      {:ok, [first | commits]}
    end
  end

  @doc """
  Lists commits of `Delta.Document` with `id = document_id`.

  Expensive operation.
  If document does not exists, returns empty list
  """
  @spec list(Delta.Document.id()) :: {:atomic, [t()]}
  def list(document_id), do: nil

  @doc """
  Lists commit from newest – `from_commit_id` to oldest – `to_commit_id`.

  If commit with `id = from_commit_id` does not exist, assumes it to be the latest commit.
  If commit with `id = to_commit_id` does not exist, assumes it to be the first commit.
  """
  @spec list(Delta.Document.id(), id(), id()) :: {:atomic, [t()]}
  def list(document_id, from_commit_id, to_commit_id), do: nil

  @spec get(Delta.Document.id(), id()) :: {:atomic, t()} | {:aborted, DoesNotExist.t()}
  def get(document_id, commit_id), do: nil

  @doc """
  Writes commit.
  """
  @spec write(t()) :: {:atomic, t()} | {:aborted, any()}
  def write(commit), do: nil

  @doc """
  Writes commits.
  """
  @spec write([t()]) :: {:atomic, [t()]} | {:aborted, any()}
  def write_many(commits), do: nil

  @doc """
  Adds commits to a document's history and checks for history consistency.

  Checks for conflicts of the first commit.

  If the commit has resolvable conflict (commits's delta does not overlaps with deltas of all conflicting commits), resolves the conflict and writes the commit.
  If the commit has no conflicts, writes the commit.

  If the commit has unresolvable conflict, aborts with `Delta.Errors.Conflict.t()`.
  """
  @spec add_commits([t()]) :: {:atomic, [t()]} | {:aborted, Conflict.t()} | {:aborted, any()}
  def add_commits(commits), do: nil

  @doc """
  Squashes Delta.Commit with `id = commit_id_2` into one with `id = commit_id_1`.

  Resulting commit will have metadata of the second commit.

  The second commit may not exist.

  Aborts with `%Delta.Errors.DoesNotExist{}` if commit with `id = commit_id_1` or `id = commit_id_2` does not exist.
  """
  @spec squash(id(), id()) :: {:atomic, t()} | {:aborted, DoesNotExist.t()}
  def squash(commit_id_1, commit_id_2), do: nil

  @doc """
  Deletes commit with `id = commit_id`.

  Returns `{:atomic, :ok}` even if commit with `id = commit_id` does not exist.
  """
  @spec delete(id()) :: {:atomic, :ok}
  def delete(change_id), do: nil

  @doc """
  Checks if commits have conflict(s) with history and resolves them if possible.

  Commits must be sorted by theirs (would be) ascending order – first commit is the first element of the list.
  History must be sorted by descending order – last commit is the first element of the list.
  """
  @spec resolve_conflicts(commits :: [t()], history :: [t()]) ::
          {:ok, [t()]} | {:error, Conflict.t()}
  def resolve_conflicts([], _), do: {:ok, []}
  def resolve_conflicts(c, []), do: {:ok, c}

  def resolve_conflicts(
        [%__MODULE__{previous_commit_id: id} | _] = commits,
        [%__MODULE__{id: id} | _]
      ),
      do: {:ok, commits}

  def resolve_conflicts(
        [%__MODULE__{id: id1} = first | rest],
        [%__MODULE__{id: id2} | _] = history
      ) do
    case Enum.find(history, nil, &overlap?(first, &1)) do
      nil -> {:ok, [struct(first, previous_commit_id: id2) | rest]}
      %__MODULE__{id: id3} -> {:error, %Conflict{commit_id: id1, conflicts_with: id3}}
    end
  end

  @doc """
  Squashing implementation. See `squash/2`.
  """
  @spec do_squash(t(), t()) :: t()
  def do_squash(
        %__MODULE__{
          id: id,
          previous_commit_id: previous_commit_id,
          document_id: document_id,
          order: order,
          patch: patch1,
          reverse_patch: reverse_patch1
        },
        %__MODULE__{
          document_id: document_id,
          autosquash?: autosquash?,
          patch: patch2,
          reverse_patch: reverse_patch2,
          meta: meta,
          updated_at: updated_at
        }
      ) do
    %__MODULE__{
      id: id,
      previous_commit_id: previous_commit_id,
      document_id: document_id,
      order: order,
      autosquash?: autosquash?,
      patch: Delta.Json.Patch.squash(patch1, patch2),
      reverse_patch: Delta.Json.Patch.squash(reverse_patch2, reverse_patch1),
      meta: meta,
      updated_at: updated_at
    }
  end

  @doc """
  Checks if two commits overlap

  Commits are overlapping if their patches overlap
  """
  @spec overlap?(t(), t()) :: boolean()
  def overlap?(%__MODULE__{patch: p1}, %__MODULE__{patch: p2}),
    do: Delta.Json.Patch.overlap?(p1, p2)

  @doc """
  Gets id from id()
  """
  @spec id(id() | nil) :: Delta.uuid4() | any()
  def id(%__MODULE__{id: id}), do: id
  def id(id), do: id
end
