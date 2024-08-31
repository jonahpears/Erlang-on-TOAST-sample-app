-module(client_side_ext).

-file("client_side_ext", 1).

-define(DATA_NUM, 10).

-define(MAX_DATA_PERIOD, 1000).

-define(MONITORED, true).

-define(SHOW_MONITORED, case ?MONITORED of true -> "(m) "; _ -> "" end).

-define(SHOW_ENABLED, true).

-define(SHOW(Str, Args, Data), case ?SHOW_ENABLED of true -> printout(Data, ?SHOW_MONITORED++"~p, "++Str, [?FUNCTION_NAME]++Args); _ -> ok end).

-define(SHOW_VERBOSE, ?SHOW_ENABLED and true).

-define(VSHOW(Str, Args, Data), case ?SHOW_VERBOSE of true -> printout(Data, ?SHOW_MONITORED++"(verbose, ln.~p) ~p, "++Str, [?LINE,?FUNCTION_NAME]++Args); _ -> ok end).

-define(DO_SHOW(Str, Args, Data), printout(Data, ?SHOW_MONITORED++"(verbose) ~p, "++Str, [?FUNCTION_NAME]++Args)).

-define(MONITOR_SPEC,
        #{init => state1_std,
          map =>
              #{state1_std => #{send => #{data => state2_recv_after}}, 
                state2_recv_after => #{recv => #{error => stop_state}},
                state5_send_after => #{send => #{data => state2_recv_after}}, 
                state7_std => #{send => #{stop => stop_state}}},
          timeouts => #{state2_recv_after => {1000, state5_send_after}, state5_send_after => {50, state7_std}}, errors => #{}, resets => #{}}).

-define(PROTOCOL_SPEC, {act, s_data, {rec, "c1", {act, r_error, endP, aft, 1000, {act, s_data, {rvar, "c1"}, aft, 50, {act, s_stop, endP}}}}}).


-export([init/1, run/1, run/2, start_link/0, start_link/1, stopping/2]).

-include("stub.hrl").

%% @doc 
start_link() -> start_link([]).

%% @doc 
start_link(Args) -> stub_start_link(Args).



%% @doc Called to finish initialising process.
%% @see stub_init/1 in `stub.hrl`.
%% If this process is set to be monitored (i.e., ?MONITORED) then, in the space indicated below setup options for the monitor may be specified, before the session actually commences.
%% Processes wait for a signal from the session coordinator (SessionID) before beginning.
init(Args) ->
    % ?SHOW("\n\targs: ~p.\n", [Args], Args),
    {ok, Data} = stub_init(Args),
    ?SHOW("\n\tdata: ~p.\n", [Data], Data),
    CoParty = maps:get(coparty_id, Data),
    SessionID = maps:get(session_id, Data),
    case ?MONITORED of
        true ->
            CoParty ! {self(), setup_options, {printout, #{enabled => true, verbose => true, termination => true}}},
            CoParty ! {self(), ready, finished_setup},
            ?VSHOW("finished setting options for monitor.", [], Data);
        _ -> ok
    end,
    ?SHOW("waiting to received start signal from session (~p)",[SessionID],Data),
    receive
        {SessionID, start} ->
            ?SHOW("received start signal from session.", [], Data),
            run(CoParty, Data)
    end.

%% @doc Adds default empty list for Data.
%% @see run/2.
run(CoParty) ->
    Data = default_stub_data(),
    ?VSHOW("using default Data.", [], Data),
    run(CoParty, Data).

%% @doc Called immediately after a successful initialisation.
%% Add any setup functionality here, such as for the contents of Data.
%% @param CoParty is the process ID of the other party in this binary session.
%% @param Data is a map that accumulates data as the program runs, and is used by a lot of functions in `stub.hrl`.
%% @see stub.hrl for helper functions and more.
run(CoParty, #{options:=Options}=Data) ->
    %% stop workers from being persistent
    Data1 = maps:put(options,maps:put(presistent_nonblocking_payload_workers,false,Options),Data),
    ?DO_SHOW("running...\nData:\t~p.\n", [Data1], Data1),
    main(CoParty, Data1).

%%% @doc the main loop of the stub implementation.
%%% CoParty is the process ID corresponding to either:
%%%   (1) the other party in the session;
%%%   (2) if this process is monitored, then the transparent monitor.
%%% Data is a map that accumulates messages received, sent and keeps track of timers as they are set.
%%% Any loops are implemented recursively, and have been moved to their own function scope.
%%% @see stub.hrl for further details and the functions themselves.
main(CoParty, Data) ->
    Payload1 = get_payload1({data, Data}),
    CoParty ! {self(), data, Payload1},
    Data1 = save_msg(send, data, Payload1, Data),
    ?SHOW("sent data.", [], Data1),
    loop_state2(CoParty, Data1).

loop_state2(CoParty, Data) ->
    ?SHOW("\n\twaiting to recv.", [], Data),
    receive
        {CoParty, error = Label2, Payload2} ->
            Data1 = save_msg(recv, error, Payload2, Data),
            ?SHOW("recv ~p: ~p.", [Label2, Payload2], Data1),
            stopping(normal, CoParty, Data1)
        after 1000 ->
                  AwaitPayload5 = nonblocking_payload(fun get_payload5/1, {data, Data}, self(), ?MAX_DATA_PERIOD, Data),
                  ?VSHOW("\n\twaiting for (data) payload to be returned from (~p).", [AwaitPayload5], Data),
                  receive
                      {_AwaitPayload5, ok, {data = Label5, Payload5}} ->
                          ?VSHOW("\n\t(data) payload obtained: {~p, ~p}.", [Label5, Payload5], Data),
                          CoParty ! {self(), data, Payload5},
                          Data1 = save_msg(send, data, Payload5, Data),
                          loop_state2(CoParty, Data1);
                      {AwaitPayload5, ko} ->
                          ?VSHOW("\n\tunsuccessful payload. (probably took too long)", [], Data),
                          Payload7 = get_payload7({stop, Data}),
                          CoParty ! {self(), stop, Payload7},
                          Data1 = save_msg(send, stop, Payload7, Data),
                          ?SHOW("sent stop.", [], Data1),
                          stopping(normal, CoParty, Data1)
                  end
    end.

%%% @doc Adds default reason 'normal' for stopping.
%%% @see stopping/3.
stopping(CoParty, Data) ->
    ?VSHOW("\n\t\tData:\t~p.", [Data], Data),
    stopping(normal, CoParty, Data).

%%% @doc Adds default reason 'normal' for stopping.
%%% @param Reason is either atom like 'normal' or tuple like {error, more_details_or_data}.
stopping(normal = Reason, _CoParty, #{role:=#{name:=Name,module:=Module},session_id:=SessionID}=Data) ->
    ?SHOW("stopping normally.", [], Data),
    SessionID ! {{Name,Module,self()}, stopping, Reason, Data},
    exit(normal);
%%% @doc stopping with error.
%%% @param Reason is either atom like 'normal' or tuple like {error, Reason, Details}.
%%% @param CoParty is the process ID of the other party in this binary session.
%%% @param Data is a list to store data inside to be used throughout the program.
stopping({error, Reason, Details}=Info, _CoParty, #{role:=#{name:=Name,module:=Module},session_id:=SessionID}=Data) when is_atom(Reason) ->
    ?SHOW("error, stopping...\n\t\tReason:\t~p,\n\t\tDetails:\t~p,\n\t\tCoParty:\t~p,\n\t\tData:\t~p.",
                              [Reason, Details, _CoParty, Data],
                              Data),
    SessionID ! {{Name,Module,self()}, stopping, Info, Data},
    erlang:error(Reason, Details);
%%% @doc Adds default Details to error.
stopping({error, Reason}=Info, CoParty, Data) when is_atom(Reason) ->
    ?VSHOW("error, stopping...\n\t\tReason:\t~p,\n\t\tCoParty:\t~p,\n\t\tData:\t~p.", [Reason, CoParty, Data], Data),
    stopping({error, Reason, []}, CoParty, Data);
%%% @doc stopping with Unexpected Reason.
stopping(Reason, _CoParty, #{role:=#{name:=Name,module:=Module},session_id:=SessionID}=Data) when is_atom(Reason) ->
    ?SHOW("unexpected stop...\n\t\tReason:\t~p,\n\t\tCoParty:\t~p,\n\t\tData:\t~p.", [Reason, _CoParty, Data], Data),
    SessionID ! {{Name,Module,self()}, stopping, Reason, Data},
    exit(Reason).

%% @doc returns if no more data to be sent.
get_payload7({Args, Data}) -> none.
  % extend_with_functionality_for_obtaining_payload.



%% @see get_payload1/1
get_payload5({_Args, _Data}) -> get_payload1({_Args, _Data}).

%% @doc returns a number one higher than the one previously sent.
get_payload1({Args, Data}) -> 
  % extend_with_functionality_for_obtaining_payload.

  ?assert(Args=:=data),

  %% check how many other data have been sent
  Value = get_msgs(send,data,Data),
  
  case Value of 
    undefined -> 1;
    _ -> 
      Len = length(Value),
      case Len<?DATA_NUM of
        true -> Len+1;
        _ -> timer:sleep(1200), none
      end
  end.
