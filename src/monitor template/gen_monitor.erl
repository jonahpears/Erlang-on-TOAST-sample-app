-module(gen_monitor).
-file("gen_monitor.erl", 1).

-behaviour(gen_statem).

% -include("toast_data_records.hrl").

-define(SHOW(Str,Args,Data),
  #{options:=#{printout:=#{enabled:=Enabled}}} = Data,
  case Enabled of 
    true -> %% check if state is available to use
      case is_map_key(state,Data) of 
        true -> printout(Data, "~p, "++Str,[maps:get(state,Data)]++Args);
        _ -> printout(Data, "~p, "++Str,[?FUNCTION_NAME]++Args)
      end;
    _ -> ok
  end ).

-define(VSHOW(Str,Args,Data),
  #{options:=#{printout:=#{enabled:=Enabled,verbose:=Verbose}}} = Data,
  case (Enabled and Verbose) of 
    true -> 
      case is_map_key(state,Data) of 
        true -> printout(Data, "(verbose, ln.~p) ~p, "++Str,[?LINE, maps:get(state,Data)]++Args);
        _ -> printout(Data, "(verbose, ln.~p) ~p, "++Str,[?LINE, ?FUNCTION_NAME]++Args)
      end;
    _ -> ok
  end ).

%% gen_statem
-export([ start_link/0,
          callback_mode/0,
          init/1,
          stop/0,
          terminate/3 ]).

%% custom wrappers for gen_statem
-export([ start_link/1 ]).

%% callbacks
-export([ handle_event/4 ]).

%% better printing
% -export([ format_status/1 ]).

%% generic callbacks
% -export([ send/2, recv/1 ]).

-include_lib("stdlib/include/assert.hrl").

% -include_lib("src/headers/printout.hrl").
% -include("printout.hrl").
-include("include/printout.hrl").

-include("nested_map_merger.hrl").
-include("list_to_map_builder.hrl").
-include("list_to_map_getter.hrl").
-include("list_to_map_setter.hrl").
-include("role_mon_data.hrl").


% -include_lib("src/headers/role_mon_show.hrl").
% -include_lib("src/headers/nested_map_merger.hrl").
% -include_lib("src/headers/list_to_map_builder.hrl").
% -include_lib("src/headers/list_to_map_getter.hrl").
% -include_lib("src/headers/list_to_map_setter.hrl").
% -include_lib("src/headers/role_mon_data.hrl").
% -include_lib("src/headers/role_mon_options.hrl").

%% @doc callback mode, we use hand_event_function to develop monitors better suited to parameterised fsm.
callback_mode() -> [handle_event_function, state_enter].

%% @doc started with no params, this will not work.
%% needs to be started with data map, as found in "role_mon_data.hrl"
%% this will be redirected, and use default params. (which have no FSM, so will fail.)
start_link() -> start_link([]).

%% @doc started with list, redirects to case with data map.
start_link(List) when is_list(List) ->
  %% get data-map from list
  Data = data(List),
  start_link(Data);
%%

%% @doc starts init in same node.
start_link(_Data) when is_map(_Data) -> 
  % ?SHOW("",[],_Data),

  %% merge with default data
  Data = nested_map_merger(default_data(), _Data),

  % ?VSHOW("\n\t\tdata:\t~p.",[Data],Data),

  Name = maps:get(name,maps:get(role,Data)),

  %% start in same node
  Ret = gen_statem:start_link({local, Name}, gen_monitor, [Data], []),
  % ?VSHOW("Ret: ~p.",[Ret],Data),
  
  case Ret of
    {ok,_PID} -> PID = _PID;
    _ -> PID = self()
  end,

  ?SHOW("starting as: ~p.",[PID],Data),
  {ok, PID}.
%%

%% @doc called during start_link, and the monitor will begin from here (with fresh pid).
init([Data]) when is_map(Data) -> 
  ?SHOW("",[],Data),
  ?VSHOW("\n\tdata:\t~p.\n",[Data],Data),
  %% enter setup state
  {ok, setup_state, Data}.
%%



%%%%%%%%%%%%%%%%%%%%%%%%%
%%% monitor termination
%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc stop function
stop() -> gen_statem:stop(?MODULE).

%% @doc termination due to emergency_signal
%% will dump contents of Data to output if options specify.
terminate(Reason, emergency_signal=_State, #{data:=#{options:=#{printout:=#{termination:=Dump}}}=Data}=_StopData) ->
  case Dump of 
    true -> ?VSHOW("\n\treason:\t~p,\n\tdata:\t~p.\n",[Reason,Data],Data);
    _ -> ?VSHOW("\n\treason:\t~p.\n",[Reason],Data)
  end;
%%
  

%% @doc general expected termination
%% will dump contents of Data to output if options specify.
terminate(Reason, _State, #{data:=#{options:=#{printout:=#{termination:=Dump}}}=Data}=_StopData) ->
  case Dump of 
    true -> ?VSHOW("\n\treason:\t~p,\n\tdata:\t~p.\n",[Reason,Data],Data);
    _ -> ?VSHOW("\n\treason:\t~p.\n",[Reason],Data)
  end;
%%

%% @doc catch-all termination
%% will dump contents of Data to output if options specify.
terminate(Reason, _State, StopData) ->
  ?SHOW("unhandled termination,\n\treason:\t~p,\n\tstate:\t~p,\n\tstop data:\t~p.\n",[Reason,_State,StopData],maps:get(data,StopData,default_data())).
%%
  


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% monitor master-enter event
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc when we enter a new state and have not updated the data stored in our data yet, update it here.
%% this event re-applies the enter event to redirect to the next most applicable enter event
%% (keeps the auto-printing state up-to-date.)
handle_event(enter, _OldState, State, #{state:=DataState,enter_flags:=_Flags}=Data)
when State=/=DataState -> 
  %% sanity check
  % ?assert(OldState=:=DataState),
  %% update to new state
  Data1 = maps:put(state,State,Data),
  % %% update prev state
  % Data2 = maps:put(prev_state,OldState,Data1),
  %% reset enter flags
  Data3 = maps:put(enter_flags,#{},Data1),
  ?SHOW("(->).",[],Data3),
  {repeat_state, Data3};
%%


%%%%%%%%%%%%%%%%%%%%%%%%%
%%% monitor setup
%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc state enter clause for setup_state, second only to the master enter event (above).
%% catch before start to allow monitor to finish setting up with the session and for the monitored process to set options.
%% (immediately silently-timeouts to do this.)
handle_event(enter, _OldState, setup_state=_State, #{coparty_id:=undefined}=Data) -> 
  % Data1 = reset_return_state(Data),
  % {keep_state, Data1, [{state_timeout, 0, wait_to_finish}]};
  {keep_state_and_data, [{state_timeout, 0, wait_to_finish}]};
%%


%% @doc timeout state used when setting up to allow monitor to finish setting up with the session and for the monitored process to set options.
handle_event(state_timeout, wait_to_finish, setup_state=_State, #{coparty_id:=undefined,sus_id:=SusID,init_sus_id:=SusInitID,session_id:=InitSessionID,role:=Role,fsm:=#{init:=Init},options:=_Options}=Data) ->
  ?VSHOW("beginning setup.",[],Data),

  ?assert(is_pid(InitSessionID)),
  ?VSHOW("InitSessionID: ~p.",[InitSessionID],Data),
  ?assert(is_pid(InitSessionID)),

  %% pretend to be monitored process in session, act as they would to session
  InitSessionID ! {self(),role,Role},
  ?VSHOW("sent to session:\n\t\t\t{~p, role, ~p}.\n",[self(),Role],Data),

  %% wait to receive coparty id from session
  ?VSHOW("\n\t\t\twaiting to receive CoPartyID from session.\n",[],Data),
  receive {InitSessionID, {session_id,SessionID}, {coparty_id, CoPartyID}} ->
    ?VSHOW("\n\treceived CoPartyID (~p) from SessionID (~p),\n\t\t\tnow waiting for init message from CoParty.\n",[CoPartyID, SessionID],Data),
    Data1 = maps:put(coparty_id,CoPartyID,Data),
    Data2 = maps:put(session_id,SessionID,Data1),

    %% pass back to sus the monitor id (they have the outdated one from start_link only)
    %% we send all this information to ensure credibility of monitor to sus
    SusID ! {{monitor_id,self()}, {init_sus_id, SusInitID}, {init_session_id, InitSessionID}, {session_id,SessionID}},
    ?VSHOW("sent to sus (~p):\n\t\t\t~p.\n",[SusID,{{'monitor_id',self()},{'init_sus_id',SusInitID},{init_session_id,InitSessionID},{session_id,SessionID}}],Data2),

    %% prepare to receive setup options from sus
    Processed = process_setup_params(Data2),
    ?VSHOW("\n\tprocessed return:\n\t~p.\n",[Processed],Data2),
    {ok, Data3} = Processed,
    ?VSHOW("\n\tfinished setup param phase,\n\t\t\tData:\t~p.\n",[Data3],Data3),

    %% exchange init message
    CoPartyID ! {self(), init},
    receive {CoPartyID, init} ->
      ?VSHOW("\n\tnow telling session (~p) ready,\n\t\t\tand waiting for signal to start.\n",[SessionID],Data3),
      %% tell session ready to proceed
      SessionID ! {self(), ready},
      
      %% wait for signal from session
      ?VSHOW("waiting for session start signal.",[],Data3),
      receive {SessionID, start} -> 
        %% pass onto sus (from session)
        SusID ! {SessionID, start},
        ?VSHOW("received start signal and forwarded to sus.",[],Data3),
        {next_state,Init,Data3} 
      end 
    end
  end;
%%


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% monitor stopping
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc catch before stop.
%% notice StopData is used rather than Data. this contains the reason for termination.
%% @see state_timeout case below.
handle_event(enter, _OldState, stop_state=_State, #{reason:=_Reason,data:=_Data}=StopData) -> 
  ?VSHOW("stop_state,\n\n\tStopData:\t~p.\n",[StopData],_Data),
  {keep_state, StopData, [{state_timeout, 0, exit_deferral}]};
%%

%% @doc catching entering stop_state without StopData.
%% wraps Data in generic StopData and reenters
handle_event(enter, _OldState, stop_state=_State, Data) 
when is_map(Data) -> 
  ?VSHOW("caught stop_state with no StopData,\n\t\t\tData:\t~p.\n",[Data],Data),
  StopData = stop_data([{reason, normal}, {data, Data}]), 
  ?VSHOW("\n\n\tStopData:\t~p.\n",[StopData],Data),
  {repeat_state, StopData};
%%

%% @doc catch before stop, state_timeout immediately reached once entering stop_state.
%% users may extend this defintion (copy/paste) to debug certain termination reasons, or perform specific behaviour before terminating depending on reason.
handle_event(state_timeout, exit_deferral, stop_state=_State, #{reason:=Reason,data:=Data}=StopData)
when is_map(StopData) and is_map(Data) -> 
  ?VSHOW("\n\t\t\treason:\t~p.\n",[Reason],Data),
  {stop, Reason, StopData};
%%




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% monitor error state reached
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc reaching an error state is similar to stop_state, except there is a non-normal reason for termination
handle_event(enter, OldState, error_state=_State, #{fsm:=#{errors:=Errors}}=Data)
when is_map(Data) ->
  % ?VSHOW("\n\t\t\tOldState:\t~p,\n\t\t\tData:\t~p.\n",[OldState,Data],Data),
  %% get error reason from old state
  ErrorReason = maps:get(OldState,Errors,error_not_specified),
  StopData = stop_data([{reason, ErrorReason}, {data, Data}]),
  ?VSHOW("\n\n\tStopData:\t~p.\n",[StopData],Data),
  {keep_state, StopData, [{state_timeout, 0, goto_stop}]};
%%

%% @see stop_state state_timeout above
handle_event(state_timeout, goto_stop, error_state=_State, #{data:=Data}=StopData) ->
  ?VSHOW("(stopping)",[],Data),
  {next_state, stop_state, StopData};
%%




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% monitor emergency-stop 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc example of extension for reserved actions (beyond scope of TOAST protocols.)
%% below, `emergency_signal` allow the monitored process to directly signal the supervisor, by causing an abnormal termination of the monitor.
%% @see stop_state above
handle_event(enter, _OldState, emergency_signal=_State, Data)
when is_map(Data) ->
  StopData = stop_data([{reason, sus_issued_signal}, {data, Data}]),
  {keep_state, StopData, [{state_timeout, 0, goto_stop}]};
%%

%% @see stop_state state_timeout above
handle_event(state_timeout, goto_stop, emergency_signal=_State, StopData) ->
  {next_state, stop_state, StopData};
%%




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% postpone receptions whilst stopping
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc postpone any receptions whilst error
handle_event(info, _Msg, _State, #{reason:=_Reason,data:=Data}=StopData)
when is_map(Data) ->
  ?VSHOW("(stopping, postponed reception)",[],Data),
  {keep_state_and_data, [postpone]};
%%

%% @doc postpone any receptions whilst stopping
handle_event(info, _Msg, stop_state=_State, Data)
when is_map(Data) ->
  ?VSHOW("(postponed reception)",[],Data),
  {keep_state_and_data, [postpone]};
%%

%% @doc postpone any receptions whilst error
handle_event(info, _Msg, error_state=_State, Data)
when is_map(Data) ->
  ?VSHOW("(postponed reception)",[],Data),
  {keep_state_and_data, [postpone]};
%%

%% @doc postpone any receptions whilst error
handle_event(info, _Msg, emergency_signal=_State, Data)
when is_map(Data) ->
  ?VSHOW("(postponed reception)",[],Data),
  {keep_state_and_data, [postpone]};
%%




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% monitor enter state & reset timers
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc entering a state that is due to reset (some) timer(s)
%% starts the timers with the necessary amount of time and then flags them as done for the next 
handle_event(enter, _OldState, State, #{fsm:=#{resets:=Resets},enter_flags:=Flags,queue:=#{state_to_return_to:=undefined}}=Data)
when is_map_key(State, Resets) and not is_map_key(resets,Flags) ->
  %% flag resets to not enter this again on re-entry
  Data1 = maps:put(enter_flags,maps:put(resets,true,Flags),Data),
  %% get timers to be reset
  TimersToReset = maps:get(State,Resets),
  ?VSHOW("timers to be reset: ~p.",[TimersToReset],Data1),
  %% for each, start them
  maps:foreach(fun(K,V) -> erlang:start_timer(V,self(),list_to_atom("timer_"++atom_to_list(K))) end, TimersToReset),
  %% re-enter state to perform other startup activities
  {repeat_state, Data1};
%%


%% @doc for setting/resetting timers at the request of the monitored process.
%% @returns an updated map of timers.
handle_event({call, From}, {set_timer, {Name, Duration}, StubTimers}, _State, #{process_timers:=Timers}=Data) -> 
  %% check timer exists 
  ?VSHOW("checking timer (~p) exists.",[Name],Data),
  case is_map_key(Name,Timers) of 
    true ->
      %% then cancel (make sure not running)
      ?SHOW("resetting timer (~p).",[maps:get(Name,Timers)],Data),
      erlang:cancel_timer(maps:get(Name,Timers));
    
    _ -> ok
  end,
  %% start new timer
  TID = erlang:start_timer(Duration, self(), Name),
  Timers1 = maps:put(Name, {false,TID}, Timers),
  StubTimers1 = maps:put(Name, TID, StubTimers),
  Data1 = maps:put(timers, Timers1, Data),
  ?VSHOW("updated timers, returning update to sus.",[],Data1),
  %% return
  {keep_state, Data1, [{reply, From, StubTimers1}]};
%%


%% @doc for handling timers completeing.
%% automatically forward timers back to monitored process.
handle_event(info, {timeout, TimerRef, Timer}, State, #{sus_id:=SusID,timers:=Timers,fsm:=#{timeouts:=Timeouts}}=Data)
when is_map_key(Timer,Timers) and is_reference(TimerRef) and is_atom(Timer) ->
  ?VSHOW("timer (~p) has completed.",[Timer],Data),
  %% forward to monitored process 
  SusID ! {timeout, TimerRef, Timer},
  %% signal timer has completed
  Data1 = maps:put(timers,maps:put(Timer,{true,TimerRef},Timers),Data),
  %% check if this corresponds to a timeout (immediate)
  case is_map_key(State,Timeouts) of
    true ->
      StateTimeout = maps:get(State,Timeouts),
      ?VSHOW("state has timeout: ~p.",[StateTimeout],Data1),
      {Timeout, TimeoutState} = StateTimeout,
      %% check if corresponds to this
      case Timeout=:=Timer of 
        true -> 
          ?VSHOW("continuing to timeout state: ~p.",[TimeoutState],Data1),
          {next_state, TimeoutState, Data1};
        _ ->
          ?VSHOW("state has timeouts, but none are relevant to (~p).",[Timer],Data1),
          {keep_state, Data1}
      end;
    %% continue as normal
    _ -> {keep_state, Data1}
  end;
%%




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% monitor enter state & set integer timeouts
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc entering a state with a timeout (integer)
%% (we do not have to set timer timeouts, as they are triggered automatically when a message is received from the timer.)
handle_event(enter, _OldState, State, #{fsm:=#{timeouts:=Timeouts,map:=Map},enter_flags:=Flags,queue:=#{state_to_return_to:=undefined}}=Data)
when is_map_key(State, Timeouts) 
and (is_integer(element(1,map_get(State, Timeouts))) 
and (not is_map_key(timeouts,Flags))) ->
  %% flag resets to not enter this again on re-entry
  Data1 = maps:put(enter_flags,maps:put(timeouts,true,Flags),Data),
  %% get timeout
  {Duration, ToState} = maps:get(State, Timeouts),
  % ?VSHOW("timeout of (~p) to: ~p.",[Duration,ToState],Data1),
  %% get current actions
  Actions = maps:get(State, Map, none),
  case Actions of 
    none -> 
      ?VSHOW("unusual -- expected state to have actions but found none,\n\t\t\tdata:\t~p.\n",[Data1],Data1);
    _ -> 
      ?SHOW("has timeout (~pms) to: ~p.",[Duration,ToState],Data1),
      %% manually check verbose
      #{options:=#{printout:=#{verbose:=Verbose}}} = Data,
      case Verbose of 
        true -> 
          %% assuming mixed-states are modelled as two (with silent/timeout edge between them)
          Action = lists:nth(1, maps:keys(Actions)),
          %% get outgoing edges
          #{Action:=Edges} = Actions,
          %% print
          ?VSHOW("available actions:\n\t\t\t~s.\n",[lists:foldl(fun({Label, Succ}, AccIn) -> AccIn++[io_lib:format("~p: ~p -> ~p,",[Action,Label,Succ])] end, [], maps:to_list(Edges))],Data1);
        _ -> ok
      end
  end,
  %% 
  {repeat_state, Data1, [{state_timeout, Duration, ToState}]};
%%




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% monitor process queued sending actions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% TODO update the old ones for here




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% monitor process postponed receptions
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% TODO update the old ones for here




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% monitor ground-enter state
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc here the monitor will re-enter for the final time, having finished all other applicable state_enter functions
handle_event(enter, _OldState, _State, Data) -> 
  ?VSHOW("grounded enter-state reached.\n\t\t\t(no other state-enter applications)\n\t\t\ttrace:\t~p.\n",[maps:get(trace,Data,trace_not_found)],Data),
  keep_state_and_data;
%%




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% transparent monitoring 
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc forward/send messages from monitored process to co-party.
%% this even handles sending messages prescribed to currently occur.
handle_event(info, {SusID, Label, Payload}, State, #{coparty_id:=CoPartyID,sus_id:=SusID,fsm:=#{map:=Map},trace:=Trace,options:=#{grace_period:=#{send:=SendGrace}=GracePeriod}=Options}=Data) 
when is_map_key(State, Map) and is_atom(map_get(Label, map_get(send, map_get(State, Map)))) ->  
  %% send message to co-party
  CoPartyID ! {self(), Label, Payload},
  %% get next state
  #{State:=#{send:=#{Label:=NextState}}} = Map,
  %% update trace
  Trace1 = [{NextState,{send,{Label,Payload}}}] ++ Trace,
  %% update options
  Options1 = maps:put(grace_period,maps:put(send,maps:put(count,0,SendGrace),GracePeriod),Options),
  %% update data
  Data1 = maps:put(trace,Trace1,Data),
  Data2 = maps:put(options,Options1,Data1),
  ?SHOW("send (~p: ~p) -> ~p.",[Label,Payload,NextState],Data2),
  {next_state, NextState, Data2};
%%  

%% @doc monitored process attempted to send a message that is not (currently, possibly) prescribed by the protocol.
%% this event allows such an attempt to be postponed until the next state.
handle_event(info, {SusID, Label, _Payload}=Msg, State, #{coparty_id:=_CoPartyID,sus_id:=SusID,options:=#{selected_preset:=SelectedPreset,grace_period:=#{send:=#{enabled:=GracePeriodEnabled,num:=MaxNum,count:=Count,immunity_state:=ImmunityState}=SendGrace}=GracePeriod}=Options}=Data) ->

  case GracePeriodEnabled of 

    %% if allowed grace period
    true ->

      case ((MaxNum-Count)>0) or State=:=ImmunityState of 

        %% if within grace, postpone
        true ->
          ?SHOW("\n\t\t\ttried to send (~p) early, postponed (grace period).\n",[Msg],Data),
          NewCount = case ImmunityState of true -> Count; _-> Count+1 end,
          Data1 = maps:put(options,maps:put(grace_period,maps:put(send,maps:put(count,NewCount,SendGrace), GracePeriod),Options),Data),
          {keep_state, Data1, [postpone]};

        %% expended grace
        _ ->
          ?SHOW("protocol violation:\n\t\t\ttried to send (~p) too early,\n\t\t\t(not configured to enforce protocol,\n\t\t\t and grace period (~p/~p) expended).\n",[Msg,MaxNum,Count],Data),
          StopData = stop_data([{reason, protocol_violation_send_wrong_time_expended_grace_period}, {data, Data}]),
          ?VSHOW("after violation, stopping,\n\n\tStopData:\t~p.\n",[StopData],Data),
          {next_state, stop_state, StopData}

      end;

    %% no grace given
    _ ->
      case SelectedPreset of 

        %% if enforcement, then postpone
        enforcement -> 
          ?SHOW("\n\t\t\ttried to send (~p) at wrong time, postponed (enforcement).\n",[Msg],Data),
          {keep_state_and_data, [postpone]};

        %% protocol violation
        _ ->
          ?SHOW("protocol violation:\n\t\t\ttried to send (~p) at wrong time,\n\t\t\t(not configured to enforce protocol).\n",[Msg],Data),
          StopData = stop_data([{reason, protocol_violation_send_wrong_time}, {data, Data}]),
          ?VSHOW("after violation, stopping,\n\n\tStopData:\t~p.\n",[StopData],Data),
          {next_state, stop_state, StopData}

      end

  end;
%%




%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% fsm protocol monitoring
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%





%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% fsm protocol monitoring
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


% %% % % % % % %
% %% handling instructions from user/implementation/controller
% %% % % % % % %

% %% normal sending actions (when in a proper state)
% handle_event(info, {act, send, Label, Payload, Meta}, State, #{name:=Name,fsm:=#{map:=Map}}=Data) 
% when is_map_key(State, Map) ->
%   show({Name, "~p,\n\t\t\t\tinstruction, send:\n\t\t\t\t{~p, ~p, ~p}.", [State, Label, Payload, Meta], Data}),
%   Meta1 = maps:from_list(Meta),
%   %% make sure special "from_queue" is not inserted
%   Meta2 = maps:remove(from_queue, Meta1),
%   {keep_state_and_data, [{next_event, cast, {send, Label, Payload, Meta2}}]};

% %% normal sending actions (but caught when other actions are being processed) -- postpone
% handle_event(info, {act, send, _Label, _Payload, _Meta}, State, #{name:=Name}=Data) ->
%   show(verbose, {Name, "~p,\n\t\t\t\tpostponing send instruction...", [State], Data}),
%   {keep_state_and_data, [postpone]};


% %% mistakingly try to request message received under label
% handle_event(info, {act, recv, Label}, State, #{name:=Name}=Data) ->
%   show({Name, "~p,\n\t\t\t\t{recv, ~p},\n\n\t\t\t\tThis is a mistake! To retrieve messages use:\n\t\t\t\t\t\"gen_statem:call(?THIS_PID, {recv, ~p}).\"", [State, Label, Label], Data}),
%   keep_state_and_data;





%% % % % % % %
%% custom init/stop wrappers
%% % % % % % %



%% % % % % % %
%% states enter
%% % % % % % %




% %% state enter, mixed choice (and no queued actions)
% handle_event(enter, _OldState, State, #{name:=Name,fsm:=#{timeouts:=Timeouts,map:=Map},queue:=#{state_to_return_to:=undefined}}=Data)
% when is_map_key(State, Timeouts) ->
%   %% get timeout
%   {TimeoutDuration, TimeoutState} = maps:get(State, Timeouts),
%   %% get current actions
%   Actions = maps:get(State, Map, none),
%   %% display available actions if verbose
%   #{options:=#{printout:=#{verbose:=Verbose}}} = Data,
%   case Verbose of 
%     true -> 
%       %% assuming mixed-states are modelled as two (with silent/timeout edge between them)
%       Action = lists:nth(1, maps:keys(Actions)),
%       %% get outgoing edges
%       #{Action:=Edges} = Actions,
%       EdgeStr = lists:foldl(fun({Label, Succ}, Acc) -> Str = io_lib:format("\n\t\t\t\t~p: <~p> -> ~p",[Action, Label, Succ]), Acc ++ [Str] end, [], maps:to_list(Edges)),
%       show(verbose, {Name, "(->) ~p [t:~p], actions:~s.", [State, TimeoutDuration, EdgeStr], Data});
%     _ ->
%       show({Name, "(->) ~p [t:~p].", [State, TimeoutDuration], Data})
%   end,
%   %% if no actions, this is unusual (and likely unintended)
%   case Actions==none of
%     true -> 
%       show({Name, "~p,\n\t\t\t\tunusual, no actions from this state:\n\t\t\t\t~p.", [State, Map], Data});
%     _ -> ok
%   end,
%   {keep_state, Data, [{state_timeout, TimeoutDuration, TimeoutState}]};




% %% state enter, no queued actions and no mixed-choice
% handle_event(enter, _OldState, State, #{name:=Name,fsm:=#{map:=Map},queue:=#{state_to_return_to:=undefined}=Queue}=Data) ->
%   %% get current actions
%   Actions = maps:get(State, Map, none),
%   %% display available actions if verbose
%   #{options:=#{printout:=#{verbose:=Verbose}}} = Data,
%   case Verbose of 
%     true -> 
%       %% assuming mixed-states are modelled as two (with silent/timeout edge between them)
%       Action = lists:nth(1, maps:keys(Actions)),
%       %% get outgoing edges
%       #{Action:=Edges} = Actions,
%       EdgeStr = lists:foldl(fun({Label, Succ}, Acc) -> Str = io_lib:format("\n\t\t\t\t~p: <~p> -> ~p",[Action, Label, Succ]), Acc ++ [Str] end, [], maps:to_list(Edges)),
%       show(verbose, {Name, "(->) ~p, actions:~s.", [State, EdgeStr], Data});
%     _ ->
%       show({Name, "(->) ~p.", [State], Data})
%   end,
%   %% if no actions, this is unusual (and likely unintended)
%   case Actions==none of
%     true -> 
%       show({Name, "~p,\n\t\t\t\tunusual, no actions from this state: ~p.", [State, Map], Data});
%     _ -> ok
%   end,
%   %% since any queued actions have been processed, clear 'check_recvs'
%   Queue1 = Queue#{check_recvs => []},
%   Data1 = Data#{queue => Queue1},
%   {keep_state, Data1};




% %% state enter, begin handling queued actions
% handle_event(enter, _OldState, State, #{name:=Name,queue:=#{on:=[],off:=Off,state_to_return_to:=undefined}}=Data) when is_list(Off) ->
%   show({Name, "(->) ~p, with (~p) queued actions.", [State, length(Off)], Data}),
%   {keep_state_and_data, [{state_timeout,0,begin_process_queue}]};

% handle_event(state_timeout, begin_process_queue, State, #{name:=Name,queue:=#{on:=[],off:=Off,state_to_return_to:=undefined}=Queue}=Data) ->
%   show(verbose, {Name, "(->) ~p, (state_timeout).", [State], Data}),
%   %% move off-queue to (active) on-queue
%   Queue1 = Queue#{on=>Off,off=>[],state_to_return_to=>State},
%   Data1 = Data#{queue=>Queue1},
%   {repeat_state, Data1};




% %% state enter, continue handling queued actions (list Off may be non-empty, containing those already tried this state)
% handle_event(enter, _OldState, State, #{name:=Name,queue:=#{on:=On,state_to_return_to:=StateToReturnTo}}=Data) when is_list(On) and StateToReturnTo=/=undefined ->
%   show( verbose, {"(->) ~p (handling queue),\n\t\t\t\tdata: ~p.", [State,Data]},
%         else, {"(->) ~p (handling queue).", [State]}, {Name, Data}),
%   {keep_state_and_data, [{state_timeout,0,continue_process_queue}]};

% handle_event(state_timeout, continue_process_queue, State, 
% #{ name:=Name, 
%    queue:=#{on:=[#{label:=Label,payload:=Payload,meta:=#{aging:=#{enabled:=LocalAgingEnabled,age:=Age}=Aging,drop:=#{after_recv:=DropAfterRecv,after_labels:=DropAfterLabels}}=Meta}=H|T], check_recvs:=CheckRecvs, state_to_return_to:=StateToReturnTo}=Queue,
%    options:=#{queue:=#{enabled:=true,aging:=#{enabled:=GlobalAgingEnabled,max_age:=MaxAge}}}}=Data) when is_map(Meta) ->
%   show({Name, "(->) ~p, queued action: ~p.", [State, H]}),
%   %% update next data
%   Queue1 = Queue#{on=>T},
%   Data1 = Data#{queue=>Queue1},
%   %% check if this should be dropped due to contents of check_recvs
%   DoNotDrop = lists:foldl(fun(Elem, Acc) -> Acc and lists:member(Elem, CheckRecvs) end, true, DropAfterLabels),
%   case DoNotDrop or DropAfterRecv of
%     true ->
%       Aging1 = Aging#{age=>Age+1},
%       Meta1 = maps:put(aging, Aging1, Meta),
%       Meta2 = maps:put(from_queue, true, Meta1),
%       %% check if aging enabled
%       case MaxAge of
%         -1 -> %% overrides both global and local aging, disabling them both
%           {next_state, StateToReturnTo, Data1, [{next_event, cast, {send, Label, Payload, Meta2}}]};
%         _ -> %% need to check if message is aged and valid to send
%           case GlobalAgingEnabled or LocalAgingEnabled of
%             true -> %% aging applies to this action
%               case Age>=MaxAge of
%                 true -> %% message is young enough to try again
%                   {next_state, StateToReturnTo, Data1, [{next_event, cast, {send, Label, Payload, Meta2}}]};
%                 _ -> %% message is too old to try again
%                   {next_state, StateToReturnTo, Data1}
%               end;
%             _ -> %% message cannot be aged
%               {next_state, StateToReturnTo, Data1, [{next_event, cast, {send, Label, Payload, Meta2}}]}
%           end
%       end;
%     _ -> %% this queued action has flagged itself to be dropped after a recent receive
%       show( verbose, {"~p, dropped queued action (~p: ~p) since:\n\t\t\t\tdrop_after_recv: ~p,\n\t\t\t\tdrop_after_labels: ~p,\n\t\t\t\tcheck_recvs: ~p.", [State, Label, Payload, DropAfterRecv, DropAfterLabels, CheckRecvs]},
%             else, {"~p, dropped queued action (~p: ~p).", [State, Label, Payload]}, 
%             {Name, Data1} ),
%       {next_state, StateToReturnTo, Data1}
%   end;






% %% % % % % % %
% %% sending actions
% %% % % % % % %

% %% auto-label -- try and find label and then send. if no label found, add to queue
% handle_event(cast, {send, dont_care=Label, Payload, Meta}, State, #{name:=Name,fsm:=#{map:=Map},queue:=#{off:=Off}=Queue,options:=#{queue:=#{enabled:=QueueEnabled}}}=Data) 
% when is_map_key(State, Map) and is_map(Meta) and is_map_key(auto_label, Meta) and map_get(enabled, map_get(auto_label, Meta))
%  ->
%   show(verbose, {Name, "~p,\n\t\t\t\tattempting to auto-label.", [State], Data}),
%   #{State:=Directions} = Map,
%   case lists:member(send,maps:keys(Directions)) of
%     true -> %% this should correspond, therefore use this label
%       %% get label from current available sending actions, which we assume to be one
%       #{send:=Actions} = Directions,
%       Label1 = lists:nth(1, maps:keys(Actions)),
%       % io:format("\n"),
%       show({Name, "~p,\n\t\t\t\tauto-labelled:\n\t\t\t\t(~p, ~p), ~p.", [State, Label1, Payload, Meta], Data}),
%       {keep_state_and_data, [{next_event, cast, {send, Label1, Payload, Meta}}]};
%     _ -> %% then this is a recv? add to queue
%       show(verbose, {Name, "~p,\n\t\t\t\tcannot auto-label, adding to queue.", [State], Data}),
%       %% if no queue in meta, use global option
%       case lists:member(queue, maps:keys(Meta)) of
%         true -> Meta1 = Meta;
%         _ -> Meta1 = maps:put(queue, #{enabled=>QueueEnabled}, Meta)
%       end,
%       Action = new_queued_action(Label, Payload, maps:to_list(Meta1)),
%       %% check if this message is flagged to be queued (default: true)
%       #{meta:=#{queue:=#{enabled:=ActionQueueEnabled}}} = Action,
%       case ActionQueueEnabled of
%         true -> %% this message is flagged to be queued 
%           Off1 = Off ++ [Action];
%         _ -> %% this message has been specifically flagged to not be queued
%           Off1 = Off,
%           %% assuming mixed-states are modelled as two (with silent/timeout edge between them)
%           show( verbose, {"~p, wrong state to send (~p: ~p),\n\t\t\t\tand global-queue option set to true,\n\t\t\t\tbut -- message explicitly flagged to not be queue-able:\n\t\t\t\t~p.", [State, Label, Payload, Action]},
%                 else, {"~p, unusual, cannot add to queue: ~p.", [State, {Label, Payload}]}, {Name, Data})
%       end,
%       Queue1 = Queue#{off=>Off1},
%       Data1 = Data#{queue=>Queue1},
%       show(verbose, {Name, "~p,\n\t\t\t\tsuccessfully added to queue:\n\t\t\t\t~p.", [State,maps:get(queue,Data1)], Data}),
%       {keep_state, Data1}
%   end;

% %% from correct states
% handle_event(cast, {send, Label, Payload, Meta}, State, #{name:=Name,coparty_id:=CoPartyID,fsm:=#{map:=Map},trace:=Trace}=Data) 
% when is_map_key(State, Map) and is_atom(map_get(Label, map_get(send, map_get(State, Map)))) and is_map(Meta) ->
%   %% send message to co-party
%   CoPartyID ! {self(), Label, Payload},
%   %% get next state
%   #{State:=#{send:=#{Label:=NextState}}} = Map,
%   %% update trace
%   Trace1 = [NextState] ++ Trace,
%   Data1 = maps:put(trace,Trace1,Data),
%   show({Name, "~p,\n\t\t\t\tsend (~p: ~p),\n\t\t\t\ttrace: ~p.", [State, Label, Payload, Trace1], Data1}),
%   {next_state, NextState, Data1};

% %% from wrong states, and queue enabled 
% handle_event(cast, {send, Label, Payload, Meta}, State, #{name:=Name,fsm:=#{map:=Map},queue:=#{off:=Off}=Queue,options:=#{queue:=#{enabled:=true=QueueEnabled}}}=Data) 
% when is_map_key(State, Map) and is_map(Meta) ->
%   %% if no queue in meta, use global option
%   case lists:member(queue, maps:keys(Meta)) of
%     true -> Meta1 = Meta;
%     _ -> Meta1 = maps:put(queue, #{enabled=>QueueEnabled}, Meta)
%   end,
%   Action = new_queued_action(Label, Payload, maps:to_list(Meta1)),
%   %% check if this message is flagged to be queued (default: true)
%   #{meta:=#{queue:=#{enabled:=ActionQueueEnabled}}} = Action,
%   case ActionQueueEnabled of
%     true -> %% this message is flagged to be queued 
%       show(verbose, {Name, "~p,\n\t\t\t\twrong state to send (~p: ~p),\n\t\t\t\tand global-queue option set to true,\n\t\t\t\tand message can be queued,\n\t\t\t\taction: ~p.", [State, Label, Payload, Action], Data}),
%       Off1 = Off ++ [Action];
%     _ -> %% this message has been specifically flagged to not be queued
%       Off1 = Off,
%       %% assuming mixed-states are modelled as two (with silent/timeout edge between them)
%       show( verbose, {"~p, wrong state to send (~p: ~p),\n\t\t\t\tand global-queue option set to true,\n\t\t\t\tbut -- message explicitly flagged to not be queue-able:\n\t\t\t\t~p.", [State, Label, Payload, Action]},
%             else, {"~p, unusual, cannot add to queue: ~p.", [State, {Label, Payload}]}, {Name, Data})
%   end,
%   %% next data has updated off-queue 
%   Queue1 = Queue#{off=>Off1},
%   Data1 = Data#{queue=>Queue1},
%   %% check if meta says from_queue
%   FromQueue = lists:member(from_queue, maps:keys(Meta)),
%   case FromQueue of true -> IsFromQueue = maps:get(from_queue, Meta); _ -> IsFromQueue = false end,
%   case IsFromQueue of
%     true -> %% then state allowed to repeat
%       {repeat_state, Data1};
%     _ ->
%       {keep_state, Data1}
%   end;

% %% from wrong states, and queue explicitly enabled (although global queue is off)
% handle_event(cast, {send, Label, Payload, #{queue:=true}=Meta}, State, #{name:=Name,fsm:=#{map:=Map},queue:=#{off:=Off}=Queue,options:=#{queue:=#{enabled:=false}}}=Data) 
% when is_map_key(State, Map) and is_map(Meta) ->
%   %% assimulate into map-format with full meta
%   Action = new_queued_action(Label, Payload, Meta),
%   %% assuming mixed-states are modelled as two (with silent/timeout edge between them)
%   show( verbose, {"~p, wrong state to send (~p: ~p),\n\t\t\t\tand global-queue option set to false,\n\t\t\t\tbut -- message flagged to be queue-able:\n\t\t\t\t~p.", [State, Label, Payload, Action]}, 
%         else, {"~p, added to queue: ~p.", [State, {Label, Payload}]}, {Name, Data}),
%   %% add to queue
%   Off1 = Off ++ [Action],
%   %% next data has updated off-queue 
%   Queue1 = Queue#{off=>Off1},
%   Data1 = Data#{queue=>Queue1},
%   {keep_state, Data1};








%% % % % % % %
%% receiving actions, 
%% % % % % % %

%% @doc receive from correct states
handle_event(info, {CoPartyID, Label, Payload}, State, #{coparty_id:=CoPartyID,sus_id:=SusID,fsm:=#{map:=Map},trace:=Trace,options:=#{grace_period:=#{recv:=RecvGrace}=GracePeriod}=Options}=Data) 
when is_map_key(State, Map) and is_atom(map_get(Label, map_get(recv, map_get(State, Map)))) ->  
  ?VSHOW("received (~p), forwarding to: ~p.",[Label,SusID],Data),
  SusID ! {self(), Label, Payload},
  %% get next state
  #{State:=#{recv:=#{Label:=NextState}}} = Map,
  %% update trace
  Trace1 = [{NextState,{recv,Label,Payload}}] ++ Trace,
  %% update options
  Options1 = maps:put(grace_period,maps:put(recv,maps:put(count,0,RecvGrace),GracePeriod),Options),
  %% update data
  Data1 = Data#{trace=>Trace1,options=>Options1},
  ?SHOW("recv (~p) -> ~p.",[Label,NextState],Data1),
  {next_state, NextState, Data1};
%%

%% @doc received message at wrong state AND configured as enforcement monitor
handle_event(info, {_CoPartyID, _Label, _Payload}=Msg, State, #{coparty_id:=CoPartyID,options:=#{selected_preset:=SelectedPreset,grace_period:=#{recv:=#{enabled:=GracePeriodEnabled,num:=MaxNum,count:=Count,immunity_state:=ImmunityState}=RecvGrace}=GracePeriod}=Options}=Data)
when _CoPartyID=:=CoPartyID ->

  case GracePeriodEnabled of 

    %% if allowed grace period
    true ->

      case ((MaxNum-Count)>0) or State=:=ImmunityState of %% ? use '>=' over '>' to stop it from triggering immediately at the next state

        %% if within grace, postpone
        true ->
          ?SHOW("\n\t\t\treceived (~p) early, postponed (grace period).",[Msg],Data),
          NewCount = case ImmunityState of true -> Count; _-> Count+1 end,
          Data1 = maps:put(options,maps:put(grace_period,maps:put(recv,maps:put(count,NewCount,RecvGrace), GracePeriod),Options),Data),
          {keep_state, Data1, [postpone]};

        %% expended grace
        _ ->
          ?SHOW("protocol violation:\n\t\t\treceived (~p) too early,\n\t\t\t(not configured to enforce protocol,\n\t\t\t and grace period (~p/~p) expended).\n",[Msg,MaxNum,Count],Data),
          StopData = stop_data([{reason, protocol_violation_reception_expended_grace_period}, {data, Data}]),
          ?VSHOW("after violation, stopping,\n\n\tStopData:\t~p.\n",[StopData],Data),
          {next_state, stop_state, StopData}

      end;

    %% no grace given
    _ ->
      case SelectedPreset of 
    
        %% if enforcement, then postpone
        enforcement -> 
          ?SHOW("\n\t\t\treceived (~p) early, postponed (enforcement).",[Msg],Data),
          {keep_state_and_data, [postpone]};

        %% protocol violation
        _ ->
          ?SHOW("protocol violation:\n\t\t\treceived (~p) too early,\n\t\t\t(not configured to enforce protocol).\n",[Msg],Data),
          StopData = stop_data([{reason, protocol_violation_too_early_reception}, {data, Data}]),
          ?VSHOW("after violation, stopping,\n\n\tStopData:\t~p.\n",[StopData],Data),
          {next_state, stop_state, StopData}

      end

  end;
%%




%% % % % % % %
%% timeouts
%% % % % % % %

%% during processing
handle_event(state_timeout, NextState, State, Data) 
when is_map(Data) and NextState=:=State ->
  ?VSHOW("state_timeout (during processing),\n\t\t\t(~p) -> (~p),\n\t\t\ttrace:\t~p.\n",[State,NextState,maps:get(trace,Data,trace_not_found)],Data),
  {next_state, NextState, Data};
%%

%% mixed-choice
handle_event(state_timeout, NextState, State, Data) 
when is_map(Data) ->
  ?VSHOW("state_timeout (mixed-choice),\n\t\t\t(~p) -> (~p),\n\t\t\ttrace:\t~p.\n",[State,NextState,maps:get(trace,Data,trace_not_found)],Data),
  {next_state, NextState, Data};
%%





%% % % % % % %
%% retreive latest message of given label
%% % % % % % %
% handle_event({call, From}, {recv, Label}, _State, #{msgs:=Msgs}=_Data) -> 
%   % show({Name, "~p,\n\t\t\t\tlooking for msg with label (~p).", [State, Label], Data}),
%   case maps:get(Label, Msgs, no_msg_found_under_label) of
%     no_msg_found_under_label=Err -> 
%       % show({"~p, no msgs with label (~p) found.", [State, Label], Data}),
%       ReplyMsg = {error, Err};
%     Matches -> 
%       % NumMsgs = lists:length(Matches),
%       % H = lists:nth(1, Matches),
%       % show({"~p, found msg (~p: ~p) out of ~p.", [State, Label, H, NumMsgs], Data}),
%       ReplyMsg = {ok, #{  label => Label, matches => Matches }}
%   end,
%   {keep_state_and_data, [{reply, From, ReplyMsg}]};
% %%





%% % % % % % %
%% handle external requests to 
%% % % % % % %

% %% change options (single surface level key-val)
% handle_event({call, From}, {options, OptionKey, Map}, State, #{name:=Name,options:=Options}=Data) 
% when is_map_key(OptionKey, Options) and is_map(Map) ->    
%   show({Name, "~p,\n\t\t\t\tchanging option:\n\t\t\t\t~p => ~p.", [State, OptionKey, Map], Data}),
%   CurrentOption = maps:get(OptionKey, Options),
%   NewOption = nested_map_merger(CurrentOption, Map),
%   Options1 = maps:put(OptionKey, NewOption, Options),
%   Data1 = Data#{options=>Options1},
%   % show(verbose, {Name, "~p,\n\tupdated: ~p => ~p,\n\told: ~p\n\tnew: ~p.", [State,OptionKey, Map,Options,Options1], Data1}),
%   {keep_state, Data1, [{reply, From, ok}]};
    
% %% request copy of options
% handle_event({call, From}, get_options, State, #{name:=Name,options:=Options}=Data) ->    
%   show(verbose, {Name, "~p,\n\t\t\t\tsharing options with ~p,\n\t\t\t\tOptions: ~p.", [State, From, Options], Data}),
%   {keep_state, Data, [{reply, From, {ok, Options}}]};

% %% request copy of data
% handle_event({call, From}, get_data, State, #{name:=Name}=Data) ->    
%   show(verbose, {Name, "~p,\n\t\t\t\tsharing data with ~p,\n\t\t\t\tData: ~p.", [State, From, Data], Data}),
%   {keep_state, Data, [{reply, From, {ok, Data}}]};

% %% request fsm terminate
% handle_event({call, _From}, {terminate, Reason}, State, #{name:=Name}=Data) ->
%   show({Name, "~p,\n\t\t\t\tinstructed to terminate,\n\t\t\t\treason: ~p.", [State, Reason], Data}),
%   StopData = stop_data([{reason, Reason}, {data, Data}]), 
%   {next_state, stop_state, StopData};






%% % % % % % %
%% anything else
%% % % % % % %
%% @doc catch any other kind of event and stop.
handle_event(EventType, EventContent, State, _Data) 
when is_map(_Data) ->
  %% make sure _Data is usable
  Data = case is_map_key(state,_Data) of true -> _Data; _ -> case is_map_key(reason,_Data) of true -> maps:get(data,_Data); _ -> default_data() end end,

  ?SHOW("error occured, unhandled event... (stopping)\n\t\t\tState:\t~p,\n\t\t\tEventType:\t~p,\n\t\t\tEventContent:\t~p,\n\t\t\tData:\t~p.\n",[State,EventType,EventContent,_Data],Data),
  StopData = stop_data([{reason, unhandled_event}, {data, Data}]), 
  {next_state, stop_state, StopData}.
%%

%% @doc loop until monitored process signals no more options to be set.
%% options are set by specifying the key within options, and providing a map which is then merged on-top of the existing (with priority to the newer map).
process_setup_params(#{sus_id:=SusID,options:=Options}=Data) ->
  ?VSHOW("waiting for option to be set.",[],Data),
  receive 
    %% finished setup, forward to coparty and continue as normal
    {SusID, ready, finished_setup} -> 
      ?VSHOW("sus (~p) is ready, finished setting options.",[SusID],Data),
      {ok, Data};

    %% continue to process more options
    {SusID, setup_options, {OptionKey, Map}} ->
      ?SHOW("setting options for (~p).",[OptionKey],Data),
      %% merge with current option
      CurrentOption = maps:get(OptionKey, Options),
      NewOption = nested_map_merger(CurrentOption, Map),
      % ?SHOW("new option: ~p.",[NewOption],Data),
      %% update options with merged option
      Options1 = maps:put(OptionKey, NewOption, Options),
      %% update data with new options
      Data1 = maps:put(options,Options1,Data),
      ?VSHOW("updated (~p)...\n\tfrom:\t~p,\n\tto:\t~p.\n",[OptionKey,CurrentOption,NewOption],Data1),
      %% repeat until ready signal
      process_setup_params(Data1)
  end.
%%

