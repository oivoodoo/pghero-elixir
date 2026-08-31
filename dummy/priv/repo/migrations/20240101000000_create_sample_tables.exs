defmodule Dummy.Repo.Migrations.CreateSampleTables do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :name, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create index(:users, [:email, :name], name: :users_email_name_idx)
    create index(:users, [:id], name: :users_id_idx)

    create table(:posts) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :body, :text
      timestamps(type: :utc_datetime)
    end

    create index(:posts, [:user_id])
    create index(:posts, [:body], name: :posts_body_unused_idx)
  end
end
