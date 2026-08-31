alias Dummy.Repo

_ = Repo.query("CREATE EXTENSION IF NOT EXISTS pg_stat_statements")

{:ok, now} = DateTime.now("Etc/UTC")
now = DateTime.truncate(now, :second)

users =
  for i <- 1..25 do
    %{
      email: "user#{i}@example.com",
      name: "User #{i}",
      inserted_at: now,
      updated_at: now
    }
  end

{25, _} = Repo.insert_all("users", users)

user_ids = Repo.query!("SELECT id FROM users ORDER BY id").rows |> List.flatten()

posts =
  for i <- 1..80 do
    %{
      user_id: Enum.at(user_ids, rem(i, length(user_ids))),
      title: "Post #{i}",
      body: "Body for post #{i}. " <> String.duplicate("lorem ipsum ", 20),
      inserted_at: now,
      updated_at: now
    }
  end

{80, _} = Repo.insert_all("posts", posts)

# Generate a bit of query-stat traffic if pg_stat_statements is available.
Enum.each(1..15, fn _ ->
  Repo.query!("SELECT count(*) FROM users WHERE email LIKE 'user%'")
  Repo.query!("SELECT title FROM posts ORDER BY id DESC LIMIT 5")
end)

IO.puts("Seeded 25 users and 80 posts")
