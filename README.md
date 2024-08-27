
# Tool Usage
Before use, in terminal:
```shell
clear; rebar3 compile; rebar3 shell
```

## Mapping: TOAST Process -> Erlang API
```erlang
toast_process:to_protocol({ProtocolNameAtom, TOASTProcess}).
```

### Example
```erlang
toast_process:to_protocol({send_once, {'p', '<-', {'data','undefined'}, 'term'}}).

{act,s_data,endP}
```

## Generation: Erlang API -> Erlang Stub (with inline monitor spec.)
```erlang
gen_stub:gen(ProtocolName, Protocol, FileName).
```

### Example

```erlang
gen_stub:gen(send_once, {act,s_data,endP}, ".erl").
```


#### Erlang Stub Program 
<details>

<summary> Click to reveal </summary>

```erlang
-module(send_once).

-file("send_once", 1).

-define(MONITORED, false).

-define(SHOW_MONITORED, case ?MONITORED of true -> "(monitored) "; _ -> "" end).

-define(SHOW_ENABLED, true).

-define(SHOW(Str, Args, Data), case ?SHOW_ENABLED of true -> printout(Data, ?SHOW_MONITORED++"~p, "++Str, [?FUNCTION_NAME]++Args); _ -> ok end).

-define(SHOW_VERBOSE, ?SHOW_ENABLED and true).

-define(VSHOW(Str, Args, Data), case ?SHOW_VERBOSE of true -> printout(Data, ?SHOW_MONITORED++"(verbose) ~p, "++Str, [?FUNCTION_NAME]++Args); _ -> ok end).

-define(DO_SHOW(Str, Args, Data), printout(Data, ?SHOW_MONITORED++"(verbose) ~p, "++Str, [?FUNCTION_NAME]++Args)).

-define(MONITOR_SPEC, #{init => state1_std, map => #{state1_std => #{send => #{data => stop_state}}}, timeouts => #{}, errors => #{}, resets => #{}}).

-define(PROTOCOL_SPEC, {act, s_data, endP}).

-include("stub.hrl").

-export([init/1, run/1, run/2]).

%% @doc Called to finish initialising process.
%% @see stub_init/1 in `stub.hrl`.
%% If this process is set to be monitored (i.e., ?monitored()=:=true) then, in the space indicated below setup options for the monitor may be specified, before the session actually commences.
%% Processes wait for a signal from the session coordinator (SessionID) before beginning.
init(Args) ->
    printout("args:\n\t~p.", [Args], Args),
    {ok, Data} = stub_init(Args),
    printout("data:\n\t~p.", [Data], Data),
    CoParty = maps:get(coparty_id, Data),
    SessionID = maps:get(session_id, Data),
    case ?monitored() =:= true of
        true ->
            CoParty ! {self(), setup_options, {printout, #{enabled => true, verbose => true, termination => true}}},
            CoParty ! {self(), ready, finished_setup},
            ?VSHOW("finished setting options for monitor.", [], Data);
        _ -> ok
    end,
    receive
        {SessionID, start} ->
            ?SHOW("received start signal from session.", [], Data),
            run(CoParty, Data)
    end.

%% @doc Adds default empty list for Data.
%% @see run/2.
run(CoParty) ->
    Data = #{coparty_id => CoParty, timers => #{}, msgs => #{}, logs => #{}},
    ?VSHOW("using default Data.", [], Data),
    run(CoParty, Data).

%% @doc Called immediately after a successful initialisation.
%% Add any setup functionality here, such as for the contents of Data.
%% @param CoParty is the process ID of the other party in this binary session.
%% @param Data is a map that accumulates data as the program runs, and is used by a lot of functions in `stub.hrl`.
%% @see stub.hrl for helper functions and more.
run(CoParty, Data) ->
    ?DO_SHOW("running...\nData:\t~p.\n", [Data], Data),
    main(CoParty, Data).

%%% @doc the main loop of the stub implementation.
%%% CoParty is the process ID corresponding to either:
%%%   (1) the other party in the session;
%%%   (2) if this process is monitored, then the transparent monitor.
%%% Data is a map that accumulates messages received, sent and keeps track of timers as they are set.
%%% Any loops are implemented recursively, and have been moved to their own function scope.
%%% @see stub.hrl for further details and the functions themselves.
main(CoParty, Data) ->
    Payload1 = get_payload1(data, Data),
    CoParty ! {self(), data, Payload1},
    Data1 = save_msg(send, data, Payload1, Data),
    ?SHOW("sent data.", [], Data1),
    stopping(CoParty, Data1, normal).

%%% @doc Adds default reason 'normal' for stopping.
%%% @see stopping/3.
stopping(CoParty, Data) ->
    ?VSHOW("\nData:\t~p.", [Data], Data),
    stopping(normal, CoParty, Data).

%%% @doc Adds default reason 'normal' for stopping.
%%% @param Reason is either atom like 'normal' or tuple like {error, more_details_or_data}.
stopping(normal = _Reason, _CoParty, _Data) ->
    ?VSHOW("stopping normally.", [], _Data),
    exit(normal);
%%% @doc stopping with error.
%%% @param Reason is either atom like 'normal' or tuple like {error, Reason, Details}.
%%% @param CoParty is the process ID of the other party in this binary session.
%%% @param Data is a list to store data inside to be used throughout the program.
stopping({error, Reason, Details}, _CoParty, _Data) when is_atom(Reason) ->
    ?VSHOW("error, stopping...\nReason:\t~p,\nDetails:\t~p,\nCoParty:\t~p,\nData:\t~p.", [Reason, Details, _CoParty, _Data], _Data),
    erlang:error(Reason, Details);
%%% @doc Adds default Details to error.
stopping({error, Reason}, CoParty, Data) when is_atom(Reason) ->
    ?VSHOW("error, stopping...\nReason:\t~p,\nCoParty:\t~p,\nData:\t~p.", [Reason, _CoParty, _Data], _Data),
    stopping({error, Reason, []}, CoParty, Data);
%%% @doc stopping with Unexpected Reason.
stopping(Reason, _CoParty, _Data) when is_atom(Reason) ->
    ?VSHOW("unexpected stop...\nReason:\t~p,\nCoParty:\t~p,\nData:\t~p.", [Reason, _CoParty, _Data], _Data),
    exit(Reason).

get_payload1(_Args) -> extend_with_functionality_for_obtaining_payload.
```
</details>


#### Monitor Spec
```erlang
#{init => state1_std, map => #{state1_std => #{send => #{data => stop_state}}}, timeouts => #{}, errors => #{}, resets => #{}}
```

# Demo

## Client

### TOAST Protocol
```
!data(true,{x})
 .def c1
 .{ ?error(x=<1).end, 
    !stop(x>1).end, 
    !data(x>1,{x}).c1 }
```

### TOAST Process
```erlang
{'p', '<-', {'data', 'undefined'}, {
    'def', {
        'p', '->', {'leq',1000}, [{{'error', 'undefined'}, 'term'}], 
        'after', {
            'set', "y", {
                'delay', {t,leq,0}, {
                    'if', {"y", 'leq', 0}, 
                    'then', {'p', '<-', {'data', 'undefined'}, {'call', {"c1", {[],[]}}} }, 
                    'else', {'p', '<-', {'stop', 'undefined'}, 'term'}
                } 
            } 
        } 
    }, 
    'as', {"c1", {[],[]}} } 
}.
```
Note: In the above, we have to choose either `'data'` or `'stop'`, since the syntax of TOAST processes does not accomodate for selection.
However, instead we describe them using an if-statement to non-blockingly try to send `'data'` and, if there is no more, then instead we send `'stop'`.


### Erlang API, Manual Encoding:
```erlang
{'timer', "x", 1000, {'act', 's_data', {'rec', "c1", {'act', 'r_error', 'error', 'aft', "x", {'act', 's_data', {'timer', "x", 1000, {'rvar', "c1"}}, 'aft', 0, {'act', 's_stop', 'endP'}} } } } }.
```
Note: In the above, we utilise a non-blocking sending action for `'data'` to enable the system to send `'stop'` once no more `'data'` can be sent.


#### Erlang Stub
Using:
```erlang
gen_stub:gen(client, {'timer', "x", 1000, {'act', 's_data', {'rec', "c1", {'act', 'r_error', 'error', 'aft', "x", {'act', 's_data', {'timer', "x", 1000, {'rvar', "c1"}}, 'aft', 0, {'act', 's_stop', 'endP'}} } } } }, "side_manual.erl").
```

<details>

<summary>Click to reveal code</summary>

```erlang
-module(client_side_manual).

-file("client_side_manual", 1).

-define(MONITORED, false).

-define(SHOW_MONITORED, case ?MONITORED of true -> "(monitored) "; _ -> "" end).

-define(SHOW_ENABLED, true).

-define(SHOW(Str, Args, Data), case ?SHOW_ENABLED of true -> printout(Data, ?SHOW_MONITORED++"~p, "++Str, [?FUNCTION_NAME]++Args); _ -> ok end).

-define(SHOW_VERBOSE, ?SHOW_ENABLED and true).

-define(VSHOW(Str, Args, Data), case ?SHOW_VERBOSE of true -> printout(Data, ?SHOW_MONITORED++"(verbose) ~p, "++Str, [?FUNCTION_NAME]++Args); _ -> ok end).

-define(DO_SHOW(Str, Args, Data), printout(Data, ?SHOW_MONITORED++"(verbose) ~p, "++Str, [?FUNCTION_NAME]++Args)).

-define(MONITOR_SPEC,
        #{init => state2_std,
          map =>
              #{state2_std => #{send => #{data => state3_recv_after}}, state3_recv_after => #{recv => #{error => error_state}},
                state7_send_after => #{send => #{data => state8_unexpected_timer_start_state}}, state11_std => #{send => #{stop => stop_state}}},
          timeouts => #{state3_recv_after => {x, state7_send_after}, state7_send_after => {0, state11_std}},
          errors => #{state3_recv_after => unspecified_error}, resets => #{init_state => #{x => 1000}, state7_send_after => #{x => 1000}}}).

-define(PROTOCOL_SPEC,
        {timer,
         "x",
         1000,
         {act, s_data, {rec, "c1", {act, r_error, error, aft, "x", {act, s_data, {timer, "x", 1000, {rvar, "c1"}}, aft, 0, {act, s_stop, endP}}}}}}).


-export([init/1, run/1, run/2, start_link/0, start_link/1, stopping/2]).

-include_lib("headers/stub.hrl").

%% @doc 
start_link() -> start_link([]).

%% @doc 
start_link(Args) -> stub_start_link(Args).



%% @doc Called to finish initialising process.
%% @see stub_init/1 in `stub.hrl`.
%% If this process is set to be monitored (i.e., ?MONITORED) then, in the space indicated below setup options for the monitor may be specified, before the session actually commences.
%% Processes wait for a signal from the session coordinator (SessionID) before beginning.
init(Args) ->
    printout("args:\n\t\t~p.", [Args]),
    {ok, Data} = stub_init(Args),
    printout("data:\n\t\t~p.", [Data]),
    CoParty = maps:get(coparty_id, Data),
    SessionID = maps:get(session_id, Data),
    case ?MONITORED of
        true ->
            CoParty ! {self(), setup_options, {printout, #{enabled => true, verbose => true, termination => true}}},
            CoParty ! {self(), ready, finished_setup},
            ?VSHOW("finished setting options for monitor.", [], Data);
        _ -> ok
    end,
    receive
        {SessionID, start} ->
            ?SHOW("received start signal from session.", [], Data),
            run(CoParty, Data)
    end.

%% @doc Adds default empty list for Data.
%% @see run/2.
run(CoParty) ->
    Data = #{coparty_id => CoParty, timers => #{}, msgs => #{}, logs => #{}},
    ?VSHOW("using default Data.", [], Data),
    run(CoParty, Data).

%% @doc Called immediately after a successful initialisation.
%% Add any setup functionality here, such as for the contents of Data.
%% @param CoParty is the process ID of the other party in this binary session.
%% @param Data is a map that accumulates data as the program runs, and is used by a lot of functions in `stub.hrl`.
%% @see stub.hrl for helper functions and more.
run(CoParty, Data) ->
    ?DO_SHOW("running...\nData:\t~p.\n", [Data], Data),
    main(CoParty, Data).

%%% @doc the main loop of the stub implementation.
%%% CoParty is the process ID corresponding to either:
%%%   (1) the other party in the session;
%%%   (2) if this process is monitored, then the transparent monitor.
%%% Data is a map that accumulates messages received, sent and keeps track of timers as they are set.
%%% Any loops are implemented recursively, and have been moved to their own function scope.
%%% @see stub.hrl for further details and the functions themselves.
main(CoParty, Data) ->
    Data1 = set_timer(x, 1000, Data),
    ?VSHOW("set timer x with duration: 1000.", [], Data1),
    Payload2 = get_payload2({data, Data}),
    CoParty ! {self(), data, Payload2},
    Data1 = save_msg(send, data, Payload2, Data),
    ?SHOW("sent data.", [], Data1),
    loop_state3(CoParty, Data1).

loop_state3(CoParty, Data) ->
    TID_x_3 = get_timer(x, Data),
    ?SHOW("waiting to recv.", [], Data),
    receive
        {CoParty, error = Label3, Payload3} ->
            Data1 = save_msg(recv, error, Payload3, Data),
            ?SHOW("recv ~p: ~p.", [Label3, Payload3], Data1),
            error(unspecified_error),
            stopping(unspecified_error, CoParty, Data1);
        {timeout, TID_x_3, x} ->
            AwaitPayload7 = nonblocking_payload(fun get_payload7/1, {data, Data}, self(), 0, Data),
            ?VSHOW("waiting for payload to be returned from (~p).", [AwaitPayload7], Data),
            receive
                {_AwaitPayload7, ok, {data = Label7, Payload7}} ->
                    ?VSHOW("payload obtained:\n\t\t{~p, ~p}.", [Label7, Payload7], Data),
                    CoParty ! {self(), data, Payload7},
                    Data1 = save_msg(send, data, Payload7, Data),
                    Data1 = set_timer(x, 1000, Data),
                    ?VSHOW("set timer x with duration: 1000.", [], Data1),
                    loop_state3(CoParty, Data);
                {AwaitPayload7, ko} ->
                    ?VSHOW("unsuccessful payload. (probably took too long)", [], Data),
                    Payload11 = get_payload11({stop, Data}),
                    CoParty ! {self(), stop, Payload11},
                    Data1 = save_msg(send, stop, Payload11, Data),
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
stopping(normal = _Reason, _CoParty, _Data) ->
    ?SHOW("stopping normally.", [], _Data),
    exit(normal);
%%% @doc stopping with error.
%%% @param Reason is either atom like 'normal' or tuple like {error, Reason, Details}.
%%% @param CoParty is the process ID of the other party in this binary session.
%%% @param Data is a list to store data inside to be used throughout the program.
stopping({error, Reason, Details}, _CoParty, _Data) when is_atom(Reason) ->
    ?SHOW("error, stopping...\n\t\tReason:\t~p,\n\t\tDetails:\t~p,\n\t\tCoParty:\t~p,\n\t\tData:\t~p.",
                              [Reason, Details, _CoParty, _Data],
                              _Data),
    erlang:error(Reason, Details);
%%% @doc Adds default Details to error.
stopping({error, Reason}, CoParty, Data) when is_atom(Reason) ->
    ?VSHOW("error, stopping...\n\t\tReason:\t~p,\n\t\tCoParty:\t~p,\n\t\tData:\t~p.", [Reason, CoParty, Data], Data),
    stopping({error, Reason, []}, CoParty, Data);
%%% @doc stopping with Unexpected Reason.
stopping(Reason, _CoParty, _Data) when is_atom(Reason) ->
    ?SHOW("unexpected stop...\n\t\tReason:\t~p,\n\t\tCoParty:\t~p,\n\t\tData:\t~p.", [Reason, _CoParty, _Data], _Data),
    exit(Reason).

get_payload2({_Args, _Data}) -> extend_with_functionality_for_obtaining_payload.

get_payload11({_Args, _Data}) -> extend_with_functionality_for_obtaining_payload.

get_payload7({_Args, _Data}) -> extend_with_functionality_for_obtaining_payload.
```

</details>

#### Monitor Specification
```erlang
#{init => state2_std,
          map =>
              #{state2_std => #{send => #{data => state3_recv_after}}, state3_recv_after => #{recv => #{error => error_state}},
                state7_send_after => #{send => #{data => state8_unexpected_timer_start_state}}, state11_std => #{send => #{stop => stop_state}}},
          timeouts => #{state3_recv_after => {x, state7_send_after}, state7_send_after => {0, state11_std}},
          errors => #{state3_recv_after => unspecified_error}, resets => #{init_state => #{x => 1000}, state7_send_after => #{x => 1000}}}
```


### Erlang API, Automatic Mapping:
```erlang
toast:process_to_protocol(client, {'p', '<-', {'data', 'undefined'}, {
    'def', {
        'p', '->', {'leq',1000}, [{{'error', 'undefined'}, 'term'}], 
        'after', {
            'set', "y", {
                'delay', {t,leq,0}, {
                    'if', {"y", 'leq', 0}, 
                    'then', {'p', '<-', {'data', 'undefined'}, {'call', {"c1", {[],[]}}} }, 
                    'else', {'p', '<-', {'stop', 'undefined'}, 'term'}
                } 
            } 
        } 
    }, 
    'as', {"c1", {[],[]}} } 
}).

{act,s_data,
    {rec,"c1",
        {act,r_error,endP,aft,1000,
           {act,s_data,{rvar,"c1"},aft,0,{act,s_stop,endP}}}}}.
```

#### Erlang Stub
Using:
```erlang
gen_stub:gen(client, {act,s_data,{rec,"c1",{act,r_error,endP,aft,1000,{act,s_data,{rvar,"c1"},aft,0,{act,s_stop,endP}}}}}, "side_automatic.erl").
```

<details>

<summary>Click to reveal code</summary>

```erlang
-module(client_side_automatic).

-file("client_side_automatic", 1).

-define(MONITORED, false).

-define(SHOW_MONITORED, case ?MONITORED of true -> "(monitored) "; _ -> "" end).

-define(SHOW_ENABLED, true).

-define(SHOW(Str, Args, Data), case ?SHOW_ENABLED of true -> printout(Data, ?SHOW_MONITORED++"~p, "++Str, [?FUNCTION_NAME]++Args); _ -> ok end).

-define(SHOW_VERBOSE, ?SHOW_ENABLED and true).

-define(VSHOW(Str, Args, Data), case ?SHOW_VERBOSE of true -> printout(Data, ?SHOW_MONITORED++"(verbose) ~p, "++Str, [?FUNCTION_NAME]++Args); _ -> ok end).

-define(DO_SHOW(Str, Args, Data), printout(Data, ?SHOW_MONITORED++"(verbose) ~p, "++Str, [?FUNCTION_NAME]++Args)).

-define(MONITOR_SPEC,
        #{init => state1_std,
          map =>
              #{state1_std => #{send => #{data => state2_recv_after}}, state2_recv_after => #{recv => #{error => stop_state}},
                state8_std => #{send => #{data => state2_recv_after}}, state10_std => #{send => #{stop => stop_state}}},
          timeouts => #{state2_recv_after => {1000, state5_unexpected_timer_start_state}, state6_unexpected_delay_state => {0, state7_if_else}}, errors => #{},
          resets => #{state2_recv_after => #{y0 => 0}}}).

-define(PROTOCOL_SPEC,
        {act,
         s_data,
         {rec,
          "c1",
          {act, r_error, endP, aft, 1000, {timer, "y0", 0, {delay, 0, {if_not_timer, "y0", {act, s_data, {rvar, "c1"}}, 'else', {act, s_stop, endP}}}}}}}).


-export([init/1, run/1, run/2, start_link/0, start_link/1, stopping/2]).

-include_lib("headers/stub.hrl").

%% @doc 
start_link() -> start_link([]).

%% @doc 
start_link(Args) -> stub_start_link(Args).



%% @doc Called to finish initialising process.
%% @see stub_init/1 in `stub.hrl`.
%% If this process is set to be monitored (i.e., ?MONITORED) then, in the space indicated below setup options for the monitor may be specified, before the session actually commences.
%% Processes wait for a signal from the session coordinator (SessionID) before beginning.
init(Args) ->
    printout("args:\n\t\t~p.", [Args]),
    {ok, Data} = stub_init(Args),
    printout("data:\n\t\t~p.", [Data]),
    CoParty = maps:get(coparty_id, Data),
    SessionID = maps:get(session_id, Data),
    case ?MONITORED of
        true ->
            CoParty ! {self(), setup_options, {printout, #{enabled => true, verbose => true, termination => true}}},
            CoParty ! {self(), ready, finished_setup},
            ?VSHOW("finished setting options for monitor.", [], Data);
        _ -> ok
    end,
    receive
        {SessionID, start} ->
            ?SHOW("received start signal from session.", [], Data),
            run(CoParty, Data)
    end.

%% @doc Adds default empty list for Data.
%% @see run/2.
run(CoParty) ->
    Data = #{coparty_id => CoParty, timers => #{}, msgs => #{}, logs => #{}},
    ?VSHOW("using default Data.", [], Data),
    run(CoParty, Data).

%% @doc Called immediately after a successful initialisation.
%% Add any setup functionality here, such as for the contents of Data.
%% @param CoParty is the process ID of the other party in this binary session.
%% @param Data is a map that accumulates data as the program runs, and is used by a lot of functions in `stub.hrl`.
%% @see stub.hrl for helper functions and more.
run(CoParty, Data) ->
    ?DO_SHOW("running...\nData:\t~p.\n", [Data], Data),
    main(CoParty, Data).

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
    ?SHOW("waiting to recv.", [], Data),
    receive
        {CoParty, error = Label2, Payload2} ->
            Data1 = save_msg(recv, error, Payload2, Data),
            ?SHOW("recv ~p: ~p.", [Label2, Payload2], Data1),
            stopping(normal, CoParty, Data1)
        after 1000 ->
                  Data1 = set_timer(y0, 0, Data),
                  ?VSHOW("set timer y0 with duration: 0.", [], Data1),
                  ?VSHOW("delay (~p).", [0], Data),
                  timer:sleep(0),
                  TID_y0_7 = get_timer(y0, Data1),
                  receive
                      {timeout, TID_y0_7, y0} ->
                          ?VSHOW("took branch for timer (~p) completing.", [y0], Data1),
                          Payload10 = get_payload10({stop, Data1}),
                          CoParty ! {self(), stop, Payload10},
                          Data2 = save_msg(send, stop, Payload10, Data1),
                          ?SHOW("sent stop.", [], Data2),
                          stopping(normal, CoParty, Data2)
                      after 0 ->
                                ?VSHOW("took branch for timer (~p) still running.", [y0], Data1),
                                Payload8 = get_payload8({data, Data1}),
                                CoParty ! {self(), data, Payload8},
                                Data2 = save_msg(send, data, Payload8, Data1),
                                ?SHOW("sent data.", [], Data2),
                                loop_state2(CoParty, Data2)
                  end
    end.

%%% @doc Adds default reason 'normal' for stopping.
%%% @see stopping/3.
stopping(CoParty, Data) ->
    ?VSHOW("\n\t\tData:\t~p.", [Data], Data),
    stopping(normal, CoParty, Data).

%%% @doc Adds default reason 'normal' for stopping.
%%% @param Reason is either atom like 'normal' or tuple like {error, more_details_or_data}.
stopping(normal = _Reason, _CoParty, _Data) ->
    ?SHOW("stopping normally.", [], _Data),
    exit(normal);
%%% @doc stopping with error.
%%% @param Reason is either atom like 'normal' or tuple like {error, Reason, Details}.
%%% @param CoParty is the process ID of the other party in this binary session.
%%% @param Data is a list to store data inside to be used throughout the program.
stopping({error, Reason, Details}, _CoParty, _Data) when is_atom(Reason) ->
    ?SHOW("error, stopping...\n\t\tReason:\t~p,\n\t\tDetails:\t~p,\n\t\tCoParty:\t~p,\n\t\tData:\t~p.",
                              [Reason, Details, _CoParty, _Data],
                              _Data),
    erlang:error(Reason, Details);
%%% @doc Adds default Details to error.
stopping({error, Reason}, CoParty, Data) when is_atom(Reason) ->
    ?VSHOW("error, stopping...\n\t\tReason:\t~p,\n\t\tCoParty:\t~p,\n\t\tData:\t~p.", [Reason, CoParty, Data], Data),
    stopping({error, Reason, []}, CoParty, Data);
%%% @doc stopping with Unexpected Reason.
stopping(Reason, _CoParty, _Data) when is_atom(Reason) ->
    ?SHOW("unexpected stop...\n\t\tReason:\t~p,\n\t\tCoParty:\t~p,\n\t\tData:\t~p.", [Reason, _CoParty, _Data], _Data),
    exit(Reason).

get_payload10({_Args, _Data}) -> extend_with_functionality_for_obtaining_payload.

get_payload8({_Args, _Data}) -> extend_with_functionality_for_obtaining_payload.

get_payload1({_Args, _Data}) -> extend_with_functionality_for_obtaining_payload.
```

</details>

#### Monitor Specification
```erlang
#{init => state1_std,
          map =>
              #{state1_std => #{send => #{data => state2_recv_after}}, state11_std => #{send => #{stop => stop_state}},
                state2_recv_after => #{recv => #{error => error_state}}, state9_std => #{send => #{data => state2_recv_after}}},
          timeouts => #{state2_recv_after => {1000, state6_unexpected_timer_start_state}, state7_unexpected_delay_state => {0, state8_if_else}},
          errors => #{state2_recv_after => unspecified_error}, resets => #{state2_recv_after => #{y0 => 0}}}
```

## Server

### TOAST Protocol
```
?data(true,{x})
 .def s1
 .{ !error(x=<1).end, 
    ?stop(x>1).end, 
    ?data(x>1,{x}).s1 }
```

### TOAST Process
```erlang
{'q', '->', 'infinity', {'data', 'undefined'}, {
    'set', "x", {
        'def', {
            'delay', {t, leq, 10000}, {
                'if', {"x", leq, 1000}, 
                'then', {'q', '<-', {'error', 'undefined'}, 'error'},
                'else', {
                    'q', '->', 'infinity', [
                        {{'data', 'undefined'}, {'call', {"s1", {[{'data','undefined'}],[]}}}},
                        {{'stop', 'undefined'}, 'term'}
                    ]
                }
            } 
        }, 
        'as', {"s1", {[{'data','undefined'}],[]}} }
    }
}.
```


### Erlang API, Automatic Mapping:
```erlang
toast:process_to_protocol(server, {'q', '->', 'infinity', {'data', 'undefined'}, {
    'set', "x", {
        'def', {
            'delay', {t, leq, 10000}, {
                'if', {"x", leq, 1000}, 
                'then', {'q', '<-', {'error', 'undefined'}, 'error'},
                'else', {
                    'q', '->', 'infinity', [
                        {{'data', 'undefined'}, {'call', {"s1", {[{'data','undefined'}],[]}}}},
                        {{'stop', 'undefined'}, 'term'}
                    ]
                }
            } 
        }, 
        'as', {"s1", {[{'data','undefined'}],[]}} }
    }
}).

{act,r_data,
     {rec,"s1",
          {act,s_error,error,aft,1000,
               {branch,[{data,{rvar,"s1"}},{stop,endP}]}}}}.
```
Notice in the above, that the timer `"x"` and the non-deterministic delay of `1000` that occured before an `if-then-else` statement containing send `error` has been replaced with a `send-after` structure in the Erlang API. 
The mapping function detects such instances as a potential for non-blocking sends with dependencies, and handles them as such.


#### Erlang Stub
Using:
```erlang
gen_stub:gen(server, {act,r_data,{rec,"s1",{act,s_error,error,aft,1000,{branch,[{data,{rvar,"s1"}},{stop,endP}]}}}}, "side.erl").
```

<details>

<summary>Click to reveal code</summary>

```erlang
-module(server_side).

-file("server_side", 1).

-define(MONITORED, false).

-define(SHOW_MONITORED, case ?MONITORED of true -> "(monitored) "; _ -> "" end).

-define(SHOW_ENABLED, true).

-define(SHOW(Str, Args, Data), case ?SHOW_ENABLED of true -> printout(Data, ?SHOW_MONITORED++"~p, "++Str, [?FUNCTION_NAME]++Args); _ -> ok end).

-define(SHOW_VERBOSE, ?SHOW_ENABLED and true).

-define(VSHOW(Str, Args, Data), case ?SHOW_VERBOSE of true -> printout(Data, ?SHOW_MONITORED++"(verbose) ~p, "++Str, [?FUNCTION_NAME]++Args); _ -> ok end).

-define(DO_SHOW(Str, Args, Data), printout(Data, ?SHOW_MONITORED++"(verbose) ~p, "++Str, [?FUNCTION_NAME]++Args)).

-define(MONITOR_SPEC,
        #{init => state1_std,
          map =>
              #{state1_std => #{recv => #{data => state2_send_after}}, state2_send_after => #{send => #{error => error_state}},
                state7_unexpected_branch_state => #{recv => #{act_data => state2_send_after, act_stop => stop_state}}},
          timeouts => #{state2_send_after => {1000, state7_unexpected_branch_state}}, errors => #{state2_send_after => unspecified_error}, resets => #{}}).

-define(PROTOCOL_SPEC, {act, r_data, {rec, "s1", {act, s_error, error, aft, 1000, {branch, [{data, {rvar, "s1"}}, {stop, endP}]}}}}).


-export([init/1, run/1, run/2, start_link/0, start_link/1, stopping/2]).

-include_lib("headers/stub.hrl").

%% @doc 
start_link() -> start_link([]).

%% @doc 
start_link(Args) -> stub_start_link(Args).



%% @doc Called to finish initialising process.
%% @see stub_init/1 in `stub.hrl`.
%% If this process is set to be monitored (i.e., ?MONITORED) then, in the space indicated below setup options for the monitor may be specified, before the session actually commences.
%% Processes wait for a signal from the session coordinator (SessionID) before beginning.
init(Args) ->
    printout("args:\n\t\t~p.", [Args]),
    {ok, Data} = stub_init(Args),
    printout("data:\n\t\t~p.", [Data]),
    CoParty = maps:get(coparty_id, Data),
    SessionID = maps:get(session_id, Data),
    case ?MONITORED of
        true ->
            CoParty ! {self(), setup_options, {printout, #{enabled => true, verbose => true, termination => true}}},
            CoParty ! {self(), ready, finished_setup},
            ?VSHOW("finished setting options for monitor.", [], Data);
        _ -> ok
    end,
    receive
        {SessionID, start} ->
            ?SHOW("received start signal from session.", [], Data),
            run(CoParty, Data)
    end.

%% @doc Adds default empty list for Data.
%% @see run/2.
run(CoParty) ->
    Data = #{coparty_id => CoParty, timers => #{}, msgs => #{}, logs => #{}},
    ?VSHOW("using default Data.", [], Data),
    run(CoParty, Data).

%% @doc Called immediately after a successful initialisation.
%% Add any setup functionality here, such as for the contents of Data.
%% @param CoParty is the process ID of the other party in this binary session.
%% @param Data is a map that accumulates data as the program runs, and is used by a lot of functions in `stub.hrl`.
%% @see stub.hrl for helper functions and more.
run(CoParty, Data) ->
    ?DO_SHOW("running...\nData:\t~p.\n", [Data], Data),
    main(CoParty, Data).

%%% @doc the main loop of the stub implementation.
%%% CoParty is the process ID corresponding to either:
%%%   (1) the other party in the session;
%%%   (2) if this process is monitored, then the transparent monitor.
%%% Data is a map that accumulates messages received, sent and keeps track of timers as they are set.
%%% Any loops are implemented recursively, and have been moved to their own function scope.
%%% @see stub.hrl for further details and the functions themselves.
main(CoParty, Data) ->
    ?SHOW("waiting to recv.", [], Data),
    receive
        {CoParty, data = Label1, Payload1} ->
            Data1 = save_msg(recv, data, Payload1, Data),
            ?SHOW("recv ~p: ~p.", [Label1, Payload1], Data1),
            loop_state2(CoParty, Data1)
    end.

loop_state2(CoParty, Data) ->
    AwaitPayload2 = nonblocking_payload(fun get_payload2/1, {error, Data}, self(), 1000, Data),
    ?VSHOW("waiting for payload to be returned from (~p).", [AwaitPayload2], Data),
    receive
        {_AwaitPayload2, ok, {error = Label2, Payload2}} ->
            ?VSHOW("payload obtained:\n\t\t{~p, ~p}.", [Label2, Payload2], Data),
            CoParty ! {self(), error, Payload2},
            Data1 = save_msg(send, error, Payload2, Data),
            error(unspecified_error),
            stopping(unspecified_error, CoParty, Data);
        {AwaitPayload2, ko} ->
            ?VSHOW("unsuccessful payload. (probably took too long)", [], Data),
            ?SHOW("waiting to recv.", [], Data),
            receive
                {CoParty, act_data = Label7, Payload7} ->
                    Data1 = save_msg(recv, act_data, Payload7, Data),
                    ?SHOW("recv ~p: ~p.", [Label7, Payload7], Data1),
                    loop_state2(CoParty, Data1);
                {CoParty, act_stop = Label7, Payload7} ->
                    Data1 = save_msg(recv, act_stop, Payload7, Data),
                    ?SHOW("recv ~p: ~p.", [Label7, Payload7], Data1),
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
stopping(normal = _Reason, _CoParty, _Data) ->
    ?SHOW("stopping normally.", [], _Data),
    exit(normal);
%%% @doc stopping with error.
%%% @param Reason is either atom like 'normal' or tuple like {error, Reason, Details}.
%%% @param CoParty is the process ID of the other party in this binary session.
%%% @param Data is a list to store data inside to be used throughout the program.
stopping({error, Reason, Details}, _CoParty, _Data) when is_atom(Reason) ->
    ?SHOW("error, stopping...\n\t\tReason:\t~p,\n\t\tDetails:\t~p,\n\t\tCoParty:\t~p,\n\t\tData:\t~p.",
                              [Reason, Details, _CoParty, _Data],
                              _Data),
    erlang:error(Reason, Details);
%%% @doc Adds default Details to error.
stopping({error, Reason}, CoParty, Data) when is_atom(Reason) ->
    ?VSHOW("error, stopping...\n\t\tReason:\t~p,\n\t\tCoParty:\t~p,\n\t\tData:\t~p.", [Reason, CoParty, Data], Data),
    stopping({error, Reason, []}, CoParty, Data);
%%% @doc stopping with Unexpected Reason.
stopping(Reason, _CoParty, _Data) when is_atom(Reason) ->
    ?SHOW("unexpected stop...\n\t\tReason:\t~p,\n\t\tCoParty:\t~p,\n\t\tData:\t~p.", [Reason, _CoParty, _Data], _Data),
    exit(Reason).

get_payload2({_Args, _Data}) -> extend_with_functionality_for_obtaining_payload.
```

</details>

#### Monitor Specification
```erlang
#{init => state1_std,
          map =>
              #{state1_std => #{recv => #{data => state2_unexpected_timer_start_state}}, state3_send_after => #{send => #{error => error_state}},
                state8_unexpected_branch_state => #{recv => #{act_data => state3_send_after, act_stop => stop_state}}},
          timeouts => #{state3_send_after => {1000, state8_unexpected_branch_state}}, errors => #{state3_send_after => unspecified_error},
          resets => #{state1_std => #{x1000 => 1000}}}
```


# Running Stubs in Sample Project
In this documentation we continue to use the `client` and `server` example.
Using:
```erlang
gen_stub:gen(server, {act,r_data,{rec,"s1",{act,s_error,error,aft,1000,{branch,[{data,{rvar,"s1"}},{stop,endP}]}}}}, "side.erl"),
gen_stub:gen(client, {act,s_data,{rec,"c1",{act,r_error,endP,aft,1000,{act,s_data,{rvar,"c1"},aft,0,{act,s_stop,endP}}}}}, "side.erl").
```
First, enter the Erlang shell:
```shell
erl
```

## Quick Reference

### In `erl` shell
#### Compiling
```erlang
c(server_side), 
c(client_side), 
c(gen_monitor), 
c(toast_sup), 
c(toast_app).
```

#### Starting the app
```erlang
toast_app:start([
  {role, #{module=>server_side,name=>server_side}},
  {role, #{module=>client_side,name=>client_side}} ]).
```

#### Running the app
```erlang
toast_app:run().
```

### Using `rebar3` shell
Compile and run the app using the following command:
```shell
rebar3 compile; rebar3 shell
```

However, note that the app will start with the parameters as defined in `toast.app.src`.
For example:
```src
{application, toast,
 [{description, "An OTP application"},
  {vsn, "0.1.0"},
  {registered, []},
  {mod, {toast_app, []}},
  {applications,
   [kernel,
    stdlib
   ]},
  {env,[]},
  {modules, []},

  {licenses, ["Apache-2.0"]},
  {links, []}
 ]}.
```

Note line 5 of the above: `{mod, {toast_app, []}}`.
The empty list `[]` denotes the startup parameters for the app.

When using our sample app, you must provide the startup parameters list elements of the form:
```erlang
{role, #{module=>module_name,name=>name_to_print}}
```
As shown above, in the previous method of running the app.


#### Running the app
Upon entering the `rebar3 shell` the app will start itself and finish setting up.
Once finished, enter the following command the run:
```erlang
toast_app:run().
```



## Runtime Monitors

In each generated Erlang stub program, there is a macro named `MONITORED` defined at the top.
By default, `MONITORED` is set to `false` indicating that this process should not be monitored.
Simply set `MONITORED` to `true` to enable runtime monitoring.

### Monitor Configuration



### Extensible Monitors

Monitors are spawned from the `gen_monitor.erl` template file.
This file uses the `gen_statem` behaviour, with `callback_mode() -> [handle_event_function, state_enter].`

Past line 134, the only function definition is that of `handle_event/4`.
The different events are separated into general categories to help make it clear the order/priority of which handler will be called for each event.

A user may simply extend this file by inserting their custom event handler at the appropriate point, with entries earlier in the file having higher priority. 
See the line 268 for an example of custom behaviour, with the `emergency_signal` event.





