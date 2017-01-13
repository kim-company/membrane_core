defmodule Membrane.Element do
  @moduledoc """
  Module containing functions spawning, shutting down, inspecting and controlling
  playback of elements.
  """

  use Membrane.Mixins.Log
  alias Membrane.ElementState

  # Type that defines an element name within a pipeline
  @type name_t :: atom | String.t

  # Type that defines what options can be passed while starting an element.
  @type options_t :: struct | nil

  # Type that defines what may be sent from one element to another.
  @type sendable_t :: %Membrane.Buffer{} | %Membrane.Event{}

  # Type that defines a single command that may be returned from handle_*
  # callbacks.
  #
  # If it is `{:send, {pad_name, buffer_or_event}` it will cause sending
  # given buffers and/or events downstream to the linked elements via pad of
  # given name.
  #
  # If it is `{:caps, {pad_name, caps}` it will set current caps for given
  # pad and inform downstream element (if linked) about the change.
  #
  # If it is `{:message, message}` it will send message to the message bus
  # if any is defined.
  @type callback_return_command_t ::
    {:send, {Membrane.Pad.name_t, sendable_t}} |
    {:message, Membrane.Message.t} |
    {:caps, {Membrane.Pad.name_t, Membrane.Caps.t}}

  # Type that defines list of commands that may be returned from handle_*
  # callbacks.
  @type callback_return_commands_t :: [] | [callback_return_command_t]



  @doc """
  Starts process for element of given module, initialized with given options and
  links it to the current process in the supervision tree.

  Works similarily to `GenServer.start_link/3` and has the same return values.
  """
  @spec start_link(module, options_t, GenServer.options) :: GenServer.on_start
  def start_link(module, element_options \\ nil, process_options \\ []) do
    debug("Start Link: module = #{inspect(module)}, element_options = #{inspect(element_options)}, process_options = #{inspect(process_options)}")
    GenServer.start_link(__MODULE__, {module, element_options}, process_options)
  end


  @doc """
  Starts process for element of given module, initialized with given
  element_options outside of the supervision tree.

  Works similarily to `GenServer.start/3` and has the same return values.
  """
  @spec start(module, options_t, GenServer.options) :: GenServer.on_start
  def start(module, element_options \\ nil, process_options \\ []) do
    debug("Start: module = #{inspect(module)}, element_options = #{inspect(element_options)}, process_options = #{inspect(process_options)}")
    GenServer.start(__MODULE__, {module, element_options}, process_options)
  end


  @doc """
  Stops given element process.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  Will trigger calling `handle_shutdown/2` element callback.

  Returns `:ok`.
  """
  @spec shutdown(pid, timeout) :: :ok
  def shutdown(server, timeout \\ 5000) do
    debug("Shutdown -> #{inspect(server)}")
    GenServer.stop(server, :normal, timeout)
    :ok
  end


  @doc """
  Determines module for given process identifier.

  Returns `{:ok, module}` in case of success.

  Returns `{:error, :invalid}` if given pid does not denote element.
  """
  @spec get_module(pid) :: {:ok, module} | {:error, any}
  def get_module(server) when is_pid(server) do
    {:dictionary, items} = :erlang.process_info(server, :dictionary)

    case items |> List.keyfind(:membrane_element_module, 0) do
      nil ->
        # Seems that given pid is not an element
        {:error, :invalid}

      {_key, module} ->
        {:ok, module}
    end
  end


  @doc """
  The same as `get_module/1` but throws error in case of failure.
  """
  @spec get_module!(pid) :: module
  def get_module!(server) when is_pid(server) do
    case get_module(server) do
      {:ok, module} ->
        module
      {:error, reason} ->
        throw reason
    end
  end


  @doc """
  Returns `true` if given module can act as a source element, `false` otherwise.
  """
  @spec is_source?(module) :: boolean
  def is_source?(module) do
    module.is_source?
  end


  @doc """
  Returns `true` if given module can act as a sink element, `false` otherwise.
  """
  @spec is_sink?(module) :: boolean
  def is_sink?(module) do
    module.is_sink?
  end


  @doc """
  Sends synchronous call to the given element requesting it to set message bus.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If case of failure, returns `{:error, reason}`
  """
  @spec set_message_bus(pid, pid, timeout) :: :ok | {:error, any}
  def set_message_bus(server, message_bus, timeout \\ 5000) when is_pid(server) do
    debug("Set Message Bus to #{inspect(message_bus)} -> #{inspect(server)}")
    GenServer.call(server, {:membrane_set_message_bus, message_bus}, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to get message bus.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `{:ok, pid}`.

  If case of failure, returns `{:error, reason}`
  """
  @spec get_message_bus(pid, timeout) :: :ok | {:error, any}
  def get_message_bus(server, timeout \\ 5000) when is_pid(server) do
    debug("Get Message Bus -> #{inspect(server)}")
    GenServer.call(server, :membrane_get_message_bus, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to clear message bus.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If case of failure, returns `{:error, reason}`
  """
  @spec clear_message_bus(pid, timeout) :: :ok | {:error, any}
  def clear_message_bus(server, timeout \\ 5000) when is_pid(server) do
    debug("Clear Message Bus -> #{inspect(server)}")
    GenServer.call(server, :membrane_clear_message_bus, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to prepare.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is already playing, returns `:noop`.

  If element has failed to reach desired state it returns `{:error, reason}`.
  """
  @spec prepare(pid, timeout) :: :ok | :noop | {:error, any}
  def prepare(server, timeout \\ 5000) when is_pid(server) do
    debug("Prepare -> #{inspect(server)}")
    GenServer.call(server, :membrane_prepare, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to start playing.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is already playing, returns `:noop`.

  If element has failed to reach desired state it returns `{:error, reason}`.
  """
  @spec play(pid, timeout) :: :ok | :noop | {:error, any}
  def play(server, timeout \\ 5000) when is_pid(server) do
    debug("Play -> #{inspect(server)}")
    GenServer.call(server, :membrane_play, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to stop playing.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If element is not playing, returns `:noop`.

  If element has failed to reach desired state it returns `{:error, reason}`.
  """
  @spec stop(pid, timeout) :: :ok | :noop | {:error, any}
  def stop(server, timeout \\ 5000) when is_pid(server) do
    debug("Stop -> #{inspect(server)}")
    GenServer.call(server, :membrane_stop, timeout)
  end


  @doc """
  Sends synchronous call to the given element requesting it to add given
  element to the list of destinations for buffers that are sent from the
  element.

  It will wait for reply for amount of time passed as second argument
  (in milliseconds).

  In case of success, returns `:ok`.

  If destination is already present, returns `:noop`.

  In case of any of server and destination are the same element,
  returns `{:error, :loop}`.

  In case of any of server or destination is not a pid of an element,
  returns `{:error, :invalid_element}`.

  In case of server is not a source element, returns
  `{:error, :invalid_direction}`.

  In case of destination is not a sink element, returns
  `{:error, {:invalid_direction, pid}}`.
  """
  @spec link({pid, Membrane.Pad.name_t}, {pid, Membrane.Pad.name_t}, timeout) ::
    :ok |
    :noop |
    {:error, :invalid_element} |
    {:error, :invalid_direction} |
    {:error, :loop}
  def link(server, destination, timeout \\ 5000)


  def link({server, server_pad}, {destination, destination_pad}, _timeout)
  when is_pid(server) and is_pid(destination) and server == destination do
    warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: Link source and target are the same")
    {:error, :loop}
  end


  def link({server, server_pad}, {destination, destination_pad}, timeout)
  when is_pid(server) and is_pid(destination) do
    debug("Linking #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}")

    case get_module(server) do
      {:ok, server_module} ->
        case get_module(destination) do
          {:ok, destination_module} ->
            cond do
              is_source?(server_module) && is_sink?(destination_module) ->
                # TODO check if pads are present
                # TODO check if pads match at all
                # TODO check if pads are not already linked
                # FIXME send membrane_link with particular pad combination
                GenServer.call(server, {:membrane_link, destination}, timeout)

              !is_source?(server_module) ->
                warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: #{inspect(server)} (#{server_module}) is not a source element")
                {:error, :invalid_direction}

              !is_sink?(destination_module) ->
                warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: #{inspect(destination)} (#{destination_module}) is not a sink element")
                {:error, :invalid_direction}
            end

          {:error, :invalid} ->
            warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: #{inspect(destination)} is not a PID of an element")
            {:error, :invalid_element}
        end

      {:error, :invalid} ->
        warn("Failed to link #{inspect(server)}/#{inspect(server_pad)} -> #{inspect(destination)}/#{inspect(destination_pad)}: #{inspect(server)} is not a PID of an element")
        {:error, :invalid_element}
    end
  end



  # Private API

  @doc false
  def init({module, options}) do
    # Call element's initialization callback
    case module.handle_init(options) do
      {:ok, internal_state} ->
        debug("Initialized: internal_state = #{inspect(internal_state)}")

        # Store module name in the process dictionary so it can be used
        # to retreive module from PID in `Membrane.Element.get_module/1`.
        Process.put(:membrane_element_module, module)

        # Determine initial list of source pads
        source_pads = if is_source?(module) do
          module.known_source_pads() |> known_pads_to_pads_state
        else
          %{}
        end

        # Determine initial list of sink pads
        sink_pads = if is_sink?(module) do
          module.known_sink_pads() |> known_pads_to_pads_state
        else
          %{}
        end

        # Return initial state of the process, including element state.
        {:ok, %ElementState{
          module: module,
          playback_state: :stopped,
          source_pads: source_pads,
          sink_pads: sink_pads,
          internal_state: internal_state,
        }}

      {:error, reason} ->
        warn("Failed to initialize element: reason = #{inspect(reason)}")
        {:stop, reason}
    end
  end


  @doc false
  def terminate(reason, %ElementState{module: module, playback_state: playback_state, internal_state: internal_state} = state) do
    if playback_state != :stopped do
      warn("Terminating: Attempt to terminate element when it is not stopped, state = #{inspect(state)}")
    end

    debug("Terminating: reason = #{inspect(reason)}, state = #{inspect(state)}")
    module.handle_shutdown(internal_state)
  end


  # Callback invoked on incoming prepare command if playback state is stopped.
  @doc false
  def handle_call(:membrane_prepare, _from, %ElementState{module: module, playback_state: :stopped, internal_state: internal_state} = state) do
    module.handle_prepare(:stopped, internal_state)
      |> handle_callback(state, fn(state) -> %{state | playback_state: :prepared} end)
      |> format_callback_response(:reply)
  end


  # Callback invoked on incoming prepare command if playback state is prepared.
  @doc false
  def handle_call(:membrane_prepare, _from, %ElementState{playback_state: :prepared} = state) do
    {:reply, :noop, state}
  end


  # Callback invoked on incoming prepare command if playback state is playing.
  @doc false
  def handle_call(:membrane_prepare, _from, %ElementState{module: module, playback_state: :playing, internal_state: internal_state} = state) do
    module.handle_prepare(:playing, internal_state)
      |> handle_callback(state, fn(state) -> %{state | playback_state: :prepared} end)
      |> format_callback_response(:reply)
  end


  # Callback invoked on incoming play command if playback state is stopped.
  @doc false
  def handle_call(:membrane_play, _from, %ElementState{module: module, playback_state: :stopped, internal_state: internal_state} = state) do
    case module.handle_prepare(:stopped, internal_state)
      |> handle_callback(state, fn(state) -> %{state | playback_state: :prepared} end) do
      {:ok, %ElementState{internal_state: internal_state} = state} ->
        module.handle_play(internal_state)
        |> handle_callback(state, fn(state) -> %{state | playback_state: :playing} end)
        |> format_callback_response(:reply)

      {:error, reason, state} ->
        {:error, reason, state}
        |> format_callback_response(:reply)
    end
  end


  # Callback invoked on incoming play command if playback state is prepared.
  @doc false
  def handle_call(:membrane_play, _from, %ElementState{module: module, playback_state: :prepared, internal_state: internal_state} = state) do
    module.handle_play(internal_state)
      |> handle_callback(state, fn(state) -> %{state | playback_state: :playing} end)
      |> format_callback_response(:reply)
  end


  # Callback invoked on incoming play command if playback state is playing.
  @doc false
  def handle_call(:membrane_play, _from, %ElementState{playback_state: :playing} = state) do
    {:reply, :noop, state}
  end


  # Callback invoked on incoming stop command if playback state is stopped.
  @doc false
  def handle_call(:membrane_stop, _from, %ElementState{playback_state: :stopped} = state) do
    {:reply, :noop, state}
  end


  # Callback invoked on incoming stop command if playback state is prepared.
  @doc false
  def handle_call(:membrane_stop, _from, %ElementState{module: module, playback_state: :prepared, internal_state: internal_state} = state) do
    module.handle_stop(internal_state)
      |> handle_callback(state, fn(state) -> %{state | playback_state: :stopped} end)
      |> format_callback_response(:reply)
  end


  # Callback invoked on incoming stop command if playback state is playing.
  @doc false
  def handle_call(:membrane_stop, _from, %ElementState{module: module, playback_state: :playing, internal_state: internal_state} = state) do
    case module.handle_prepare(:playing, internal_state)
      |> handle_callback(state, fn(state) -> %{state | playback_state: :prepared} end) do
      {:ok, state} ->
        module.handle_stop(internal_state)
        |> handle_callback(state, fn(state) -> %{state | playback_state: :stopped} end)
        |> format_callback_response(:reply)

      # FIXME handle errors
    end
  end


  # Callback invoked on incoming set_message_bus command.
  @doc false
  def handle_call({:membrane_set_message_bus, message_bus}, _from, state) do
    {:reply, :ok, %{state | message_bus: message_bus}}
  end


  # Callback invoked on incoming get_message_bus command.
  @doc false
  def handle_call(:membrane_get_message_bus, _from, %ElementState{message_bus: message_bus} = state) do
    {:reply, {:ok, message_bus}, state}
  end


  # Callback invoked on incoming clear_message_bus command.
  @doc false
  def handle_call(:membrane_clear_message_bus, _from, state) do
    {:reply, :ok, %{state | message_bus: nil}}
  end


  # Callback invoked on incoming link request.
  @doc false
  def handle_call({:membrane_link, destination}, _from, state) do
    {:reply, :ok, state} # TODO
  end


  # Callback invoked on incoming buffer.
  #
  # If element is playing it will delegate actual processing to handle_buffer/3.
  #
  # Otherwise it will silently drop the buffer.
  # FIXME message should contain target pad
  @doc false
  def handle_info({:membrane_buffer, buffer}, %ElementState{module: module, internal_state: internal_state, playback_state: playback_state} = state) do
    if is_sink?(module) do # FIXME check if target pad exists
      case playback_state do
        :stopped ->
          warn("Incoming buffer: Error, not started (buffer = #{inspect(buffer)})")
          {:noreply, state}

        :prepared ->
          warn("Incoming buffer: Error, not started (buffer = #{inspect(buffer)})")
          {:noreply, state}

        :playing ->
          module.handle_buffer(buffer, internal_state)
            |> handle_callback(state, fn(state) -> state end)
            |> format_callback_response(:noreply)
      end

    else
      throw :buffer_on_non_sink
    end
  end


  # Callback invoked on other incoming message
  @doc false
  def handle_info(message, %ElementState{module: module, internal_state: internal_state} = state) do
    module.handle_other(message, internal_state)
      |> handle_callback(state, fn(state) -> state end)
      |> format_callback_response(:noreply)
  end


  # Converts list of known pads into map of pad states
  # FIXME move to separate module?
  defp known_pads_to_pads_state(known_pads) do
    known_pads
    |> Map.to_list
    |> Enum.filter(fn({_name, {availability, _caps}}) ->
      availability == :always
    end)
    |> Enum.reduce(%{}, fn({name, {_availability, _caps}}, acc) ->
      acc |> Map.put(name, %{peer: nil, caps: nil})
    end)
  end


  defp format_callback_response({:ok, new_state}, :reply) do
    {:reply, :ok, new_state}
  end

  defp format_callback_response({:ok, new_state}, :noreply) do
    {:noreply, new_state}
  end

  defp format_callback_response({:error, reason, new_state}, :reply) do
    {:reply, {:error, reason}, new_state}
  end

  defp format_callback_response({:error, _reason, new_state}, :noreply) do
    {:noreply, new_state}
  end


  # Generic handler that can be used to convert return value from
  # element callback to reply that is accepted by GenServer.handle_*.
  #
  # Case when callback returned successfully and requests no further action.
  defp handle_callback({:ok, new_internal_state}, state, state_fun) do
    new_state = state_fun.(state)
    {:ok, %{new_state | internal_state: new_internal_state}}
  end

  # Generic handler that can be used to convert return value from
  # element callback to reply that is accepted by GenServer.handle_*.
  #
  # Case when callback returned successfully and wants to execute some commands
  # in response.
  defp handle_callback({:ok, commands, new_internal_state}, state, state_fun) do
    new_state = state_fun.(state)
    case handle_commands_recurse(commands, %{new_state | internal_state: new_internal_state}) do
      {:ok, new_state} ->
        {:ok, new_state}
    end
  end

  # Generic handler that can be used to convert return value from
  # element callback to reply that is accepted by GenServer.handle_info.
  #
  # Case when callback returned failure.
  defp handle_callback({:error, reason, new_internal_state}, state, state_fun) do
    warn("Handle callback: Error (reason = #{inspect(reason)})")
    {:error, reason, %{state | internal_state: new_internal_state}}
  end


  defp handle_commands_recurse([], state), do: {:ok, state}

  # Handles command that is supposed to send buffer from the given pad to its
  # linked peer. # FIXME add match when there's no peer
  defp handle_commands_recurse([{:send, {pad, %Membrane.Buffer{} = buffer}}|tail], state) do
    debug("Sending buffer from pad #{inspect(pad)}: #{inspect(buffer)}")
    # :ok = send_message(head, link_destinations)

    handle_commands_recurse(tail, state)
  end

  # Handles command that is supposed to send event from the given pad to its
  # linked peer. # FIXME add match when there's no peer
  defp handle_commands_recurse([{:send, {pad, %Membrane.Event{} = event}}|tail], state) do
    debug("Sending event from pad #{inspect(pad)}: #{inspect(event)}")
    # :ok = send_message(head, link_destinations)

    handle_commands_recurse(tail, state)
  end

  # Handles command that is supposed to send buffer or event from the
  # given pad to its linked peer.
  defp handle_commands_recurse([{:send, {pad, buffer_or_event}}|tail], state) do
    debug("Sending buffer/event from pad #{inspect(pad)}: #{inspect(buffer_or_event)}")
    # :ok = send_message(head, link_destinations)

    handle_commands_recurse(tail, state)
  end

  # Handles command that is supposed to send message from the element if there's
  # no message bus set.
  defp handle_commands_recurse([{:message, %Membrane.Message{} = message}|tail], %ElementState{message_bus: nil} = state) do
    debug("Would emit message but no message bus is set: #{inspect(message)}")

    handle_commands_recurse(tail, state)
  end

  # Handles command that is supposed to send message from the element if there's
  # a message bus.
  defp handle_commands_recurse([{:message, %Membrane.Message{} = message}|tail], %ElementState{message_bus: message_bus} = state) do
    debug("Emitting message: #{inspect(message)}")
    send(message_bus, {:membrane_message, message})

    handle_commands_recurse(tail, state)
  end

  # Handles command that is informs that caps on given pad were set.
  #
  # If this pad has a peer it will additionally send Membrane.Event.caps
  # to it.
  defp handle_commands_recurse([{:caps, {pad, caps}}|tail], state) do
    debug("Setting caps for pad #{inspect(pad)} to #{inspect(caps)}")
    # :ok = send_message(head, link_destinations)

    handle_commands_recurse(tail, state)
  end
end