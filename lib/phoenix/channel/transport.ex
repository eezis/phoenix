defmodule Phoenix.Channel.Transport do
  use Behaviour

  @moduledoc """
  """

  defcallback start_link(options :: list) :: {:ok, pid} | {:error, term}

  defmodule InvalidReturn do
    defexception [:message]
    def exception(msg) do
      %InvalidReturn{message: "Invalid Handler return: #{inspect msg}"}
    end
  end


  def dispatch(msg, socket) do
    socket
    |> Socket.set_current_channel(msg.channel, msg.topic)
    |> dispatch(msg.channel, msg.event, msg.message)
  end

  defp dispatch(socket, "phoenix", "heartbeat", _msg) do
    msg = %Message{channel: "phoenix", topic: "conn", event: "heartbeat", message: %{}}
    send socket.pid, msg
  end
  defp dispatch(socket, channel, "join", msg) do
    socket
    |> socket.router.match(:websocket, channel, "join", msg)
    |> handle_result("join")
  end
  defp dispatch(socket, channel, event, msg) do
    if Socket.authenticated?(socket, channel, socket.topic) do
      socket
      |> socket.router.match(:websocket, channel, event, msg)
      |> handle_result(event)
    else
      handle_result({:error, socket, :unauthenticated}, event)
    end
  end

  defp handle_result({:ok, socket}, "join") do
    Channel.subscribe(socket, socket.channel, socket.topic)
  end
  defp handle_result(socket = %Socket{}, "leave") do
    Channel.unsubscribe(socket, socket.channel, socket.topic)
  end
  defp handle_result(socket = %Socket{}, _event) do
    socket
  end
  defp handle_result({:error, socket, _reason}, _event) do
    socket
  end
  defp handle_result(bad_return, event) when event in ["join", "leave"] do
    raise InvalidReturn, message: """
      expected {:ok, %Socket{}} | {:error, %Socket{}, reason} got #{inspect bad_return}
    """
  end
  defp handle_result(bad_return, _event) do
    raise InvalidReturn, message: """
      expected %Socket{} got #{inspect bad_return}
    """
  end

  def dispatch_info(socket = %Socket{},  data) do
    Enum.reduce socket.channels, socket, fn {channel, topic}, socket ->
      dispatch_info(socket, channel, topic, data)
    end
  end
  def dispatch_info(socket, channel, topic, data) do
    socket
    |> Socket.set_current_channel(channel, topic)
    |> socket.router.match(:websocket, channel, "info", data)
    |> handle_result("info")
  end

  def dispatch_leave(socket, reason) do
    Enum.each socket.channels, fn {channel, topic} ->
      socket
      |> Socket.set_current_channel(channel, topic)
      |> socket.router.match(:websocket, channel, "leave", reason: reason)
      |> handle_result("leave")
    end
    :ok
  end
end
