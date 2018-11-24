require Logger

defmodule ExSync.Config do
  def reload_timeout do
    Application.get_env(application(), :reload_timeout, 150)
  end

  def reload_callback do
    Application.get_env(application(), :reload_callback)
  end

  def beam_dirs do
    if Mix.Project.umbrella?() do
      for %Mix.Dep{app: app, opts: opts} <- Mix.Dep.Umbrella.loaded() do
        config = [
          umbrella?: true,
          app_path: opts[:build]
        ]

        Mix.Project.in_project(app, opts[:path], config, fn _ -> beam_dirs() end)
      end
    else
      dep_paths =
        Mix.Dep.cached()
        |> Enum.filter(fn dep -> dep.opts[:path] != nil end)
        |> Enum.map(fn %Mix.Dep{app: app, opts: opts} ->
          config = [
            umbrella?: opts[:in_umbrella],
            app_path: opts[:build]
          ]

          Mix.Project.in_project(app, opts[:path], config, fn _ -> beam_dirs() end)
        end)

      [Mix.Project.compile_path() | dep_paths]
    end
    |> List.flatten()
    |> Enum.uniq()
  end

  def src_monitor_enabled do
    case Application.fetch_env(application(), :src_monitor) do
      :error ->
        Logger.debug(
          "Defaulting to enable source monitor, set config :exsync, src_monitor: false to disable"
        )

        true

      {:ok, value} when value in [true, false] ->
        value

      {:ok, invalid} ->
        Logger.error(
          "Value #{inspect(invalid)} not valid for setting :src_monitor, expected true or false.  Enabling source monitor."
        )

        true
    end
  end

  def src_dirs do
    src_default_dirs() ++ src_addition_dirs()
  end

  defp src_default_dirs(deps_project \\ false) do
    if Mix.Project.umbrella?() do
      for %Mix.Dep{app: app, opts: opts} <- Mix.Dep.Umbrella.loaded() do
        Mix.Project.in_project(app, opts[:path], fn _ -> src_default_dirs() end)
      end
    else

      dep_paths =
        Mix.Dep.cached()
        |> Enum.filter(fn dep -> dep.opts[:path] != nil end)
        |> Enum.map(fn %Mix.Dep{app: app, opts: opts} ->
          Mix.Project.in_project(app, opts[:path], fn _ -> src_default_dirs(true) end)
        end)

      self_paths =
        if !deps_project && exclude_default_src_paths?() do
          project_name = Keyword.get(Mix.Project.config(), :app, :unknown)
          Logger.info("exsync excluding default src paths in project '#{project_name}'")
          []
        else
          Mix.Project.config()
          |> Keyword.take([:elixirc_paths, :erlc_paths, :erlc_include_path])
          |> Keyword.values()
          |> List.flatten()
          |> Enum.map(&Path.join(app_source_dir(), &1))
          |> Enum.filter(&File.exists?/1)
        end

      [self_paths | dep_paths]
    end
    |> List.flatten()
    |> Enum.uniq()
  end

  defp src_addition_dirs do
    dirs = Application.get_env(:exsync, :addition_dirs, [])

    non_relative_dirs = Enum.filter(dirs, fn path -> Path.type(path) != :relative end)

    case non_relative_dirs do
      [] ->
        :ok
      [_ | _] ->
        Logger.error("exsync's addition_dirs need to be relative paths, got #{inspect non_relative_dirs}")
    end

    dirs = Enum.map(dirs, &Path.join(app_source_dir(), &1))

    # NOTE, could use &File.dir?/1, but it seems like normal files are alright too
    case Enum.split_with(dirs, &File.exists?/1) do
      {dirs, []} ->
        dirs
      {dirs, invalid_paths = [_ | _]} ->
        Logger.error("exsync's addition_dirs need to exist, #{inspect invalid_paths} don't exist")
        dirs
    end
  end

  def src_extensions do
    Application.get_env(
      :exsync,
      :extensions,
      [".erl", ".hrl", ".ex", ".eex"] ++ Application.get_env(:exsync, :extra_extensions, [])
    )
  end

  def exclude_default_src_paths? do
    Application.get_env(:exsync, :exclude_default_src_paths?, false)
  end

  def application do
    :exsync
  end

  def app_source_dir do
    Path.dirname(Mix.ProjectStack.peek().file)
  end
end
