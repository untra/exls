defmodule ExLS.IOHandler do
  @moduledoc """
  Reads and writes packets using the Language Server Protocol's wire protocol
  """
  alias ExLS.IOHandler.PacketStream

  def child_spec(args) do
    %{
      name: args[:name],
      id: __MODULE__,
      start: { __MODULE__, :start_link, args},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  def start_link(handler, opts \\ []) do
    pid = Process.spawn(__MODULE__, :read_stdin, [handler], [:link])
    if opts[:name], do: Process.register(pid, opts[:name])
    {:ok, pid}
  end

  def read_stdin(handler) do
    PacketStream.stream(Process.group_leader)
    |> Stream.each(fn packet -> handler.receive_packet(packet) end)
    |> Stream.run
  end

  def send(packet) do
    body = Poison.encode!(packet) <> "\r\n\r\n"
    IO.binwrite("Content-Length: #{byte_size(body)}\r\n\r\n" <> body)
  end

end
