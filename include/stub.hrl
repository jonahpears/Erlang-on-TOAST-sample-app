-export([ stub_start_link/0,
          stub_start_link/1,
          stub_init/1,
          send/3,
          recv/3,
          send_before/4, 
          recv_before/4,
          set_timer/3,
          get_timer/2,
          default_stub_data/0,
          save_msg/3,
          get_msg/2,
          get_msgs/2,
          nonblocking_selection/5,
          nonblocking_payload/5
        ]).
-compile(nowarn_export_all).


-include_lib("stdlib/include/assert.hrl").

-include("printout.hrl").

%% @doc determines if start_link/0/1 creates monitor in the same node
-ifdef(MONITORED).
-else.
-define(MONITORED, false).
-endif.

%% @doc if monitored, put specification here (i.e.: module:spec_fun() or spec_map=#{...}) OR, pass in with Args list
-ifdef(MONITOR_SPEC).
-else.
-define(MONITOR_SPEC, #{}).
-endif.

%% @doc 
stub_start_link() -> stub_start_link([]).



%% @doc start link with monitored stub
stub_start_link(Args) when ?MONITORED=:=true ->
  Params = maps:from_list(Args),
  ?SHOW("\n\tParams:\t~p.\n",[Params],Params),
  PID = self(),

  %% get name 
  Name = maps:get(name, maps:get(role, Params), ?MODULE),
  MonitorName = Name, %% ! names must be the same for Session/server to find IDs

  %% update monitor args with new name
  MonitorArgs = maps:to_list(maps:put(role,maps:put(name,MonitorName,maps:get(role,Params)),Params)),

  %% spawn main stub within same node
  StubID = erlang:spawn_link(?MODULE, init, [Args++[{init_sus_id, PID}]]),
  ?SHOW("\n\tStarting stub in (~p).\n",[StubID],Params),

  %% get monitor spec
  MonitorSpec = case is_map(?MONITOR_SPEC) of true -> ?MONITOR_SPEC; _ -> ?assert(is_map_key(monitor_spec,Params)), maps:get(monitor_spec,Params) end,

  %% spawn monitor within same node 
  MonitorID = erlang:spawn_link(node(), gen_monitor, start_link, [MonitorArgs++[{fsm,MonitorSpec},{init_sus_id, PID},{sus_id, StubID}]]),
  ?SHOW("\n\tStarting monitor in (~p).\n",[MonitorID],Params),

  %% return as monitor
  {ok, MonitorID};


%% @doc normal unmonitored start_link
stub_start_link(Args) -> 
  Params = maps:from_list(Args),
  ?SHOW("\n\tParams:\t~p.\n",[Params],Params),
  PID = self(),

  StubID = erlang:spawn_link(?MODULE, init, [Args++[{init_sus_id, PID}]]),
  
  %% get name 
  Name = maps:get(name, maps:get(role, Params), ?MODULE),

  %% register stub under name
  erlang:register(Name,StubID),

  ?SHOW("\n\tStarting stub in (~p).\n",[StubID],Params),
  {ok, StubID}.
%%






%% @doc called after start_link returns
stub_init(Args) ->
  %  when ?MONITORED=:=true ->
  Params = maps:from_list(Args),
  ?SHOW("\n\tParams: ~p.\n",[Params],Params),

  ?assert(is_map_key(role,Params)),
  ?assert(is_map_key(session_name,Params)),
  % ?assert(is_map_key(init_sus_id,Params)),

  %% unpack from param map
  #{role:=#{module:=Module,name:=Name}=Role,session_name:=SessionName,init_sus_id:=InitID} = Params,

  %% make data
  Data = maps:put(role,Role,default_stub_data()),

  %% wait for session to finish setting up
  ?SHOW("\n\tWaiting to receive SessionID from session/server.\n",[],Params),
  receive {init_state_message,{session_id,SessionID}} ->

    %% add to data
    Data1 = maps:put(session_id,SessionID,Data),

    MsgSessionInit = {{name,Name},{module,Module},{init_id,InitID},{pid,self()}},

    case ?MONITORED of 
      %% dont send if monitored
      true -> ok;
      %% send to session if unmonitored
      _ -> 
        timer:sleep(50),
        %% exchange with server current ID
        SessionID ! MsgSessionInit
    end,

    ?SHOW("\n\tRecv'd SessionID (~p).\n\n\tSent self back to SessionID: ~p.\n\n\tWaiting to receive CoPartyID from session/server.\n",[SessionID,MsgSessionInit],Params),
    receive {SessionID, {coparty_id, CoPartyID}} ->

      %% update to contain ids
      Data2 = maps:put(coparty_id,CoPartyID,Data1),

      case ?MONITORED of
        %% dont exchange if monitored
        true -> ok;
        %% exchange ids with coparty
        _ ->
          %% send init to coparty
          MsgCoPartyInit = {self(),init,SessionID},
          CoPartyID ! MsgCoPartyInit,

          ?SHOW("\n\tSent CoParty (~p): ~p.\n\n\tWaiting to receive init message from CoParty (~p).\n",[CoPartyID,MsgCoPartyInit,CoPartyID],Data2),
    
          receive {CoPartyID, init, SessionID} ->
            ?VSHOW("\n\tRecv'd init fom CoParty (~p).\n\n\tSent ready signal to Session (~p),\n\tand waiting for start signal.\n",[CoPartyID,SessionID],Data2),
            
            %% tell session ready to proceed
            SessionID ! {self(), ready}
          end  
      end,

      %% return to stub to finish setup (passing params to monitor)
      {ok, Data2}

    end
  end.
%%





% %% @doc init function for unmonitored process.
% stub_init(Args) ->
%   Params = maps:from_list(Args),
%   ?SHOW("\n\tParams:\t~p.\n",[Params],Params),

%   ?assert(is_map_key(role,Params)),
%   ?assert(is_map_key(session_name,Params)),
%   ?assert(is_map_key(init_sus_id,Params)),

%   %% unpack from param map
%   #{role:=#{module:=Module,name:=Name}=Role,session_name:=SessionName,init_sus_id:=InitID} = Params,

%   %% wait for session to finish setting up
%   ?SHOW("\n\tWaiting to receive init message from session/server.\n",[],Params),
%   receive {init_state_message,{session_id,SessionID}} ->

%     %% get pid of server running session
%     ?assert(is_pid(SessionID)=:=whereis(SessionName)),
%     ?assert(is_process_alive(SessionID)),

%     %% exchange with server current ID
%     SessionID ! {{name,Name},{module,Module},{init_id,InitID},{pid,self()}},
%     % receive {}

%     ok

%   end,

%   %% TODO below is old, integrate with above



%   Params = maps:from_list(Args),
%   ?SHOW("\n\t\tParams:\t~p.\n",[Params],Params),
%   PID = self(),

%   %% unpack from param map
%   Role = maps:get(role,Params,role_unspecified),

%   InitSessionID = maps:get(session_id,Params,no_session_id_found),
%   ?VSHOW("InitSessionID: ~p.",[InitSessionID],Params),
%   ?assert(is_pid(InitSessionID)),

%   InitSessionID ! {self(),role,Role},

%   Data = maps:put(session_id,InitSessionID,default_stub_data()),
%   Data1 = maps:put(role,maps:get(role,Params),Data),

%   % %% wait to receive coparty id from session
%   ?VSHOW("\n\t\t\twaiting to receive CoPartyID from session.\n",[],Data1),
%   receive {InitSessionID, {session_id,SessionID}, {coparty_id, CoPartyID}} ->
%     ?VSHOW("received CoPartyID (~p) from SessionID (~p),\n\t\t\tnow waiting for init message from CoParty.",[CoPartyID, SessionID],Data1),
%     Data2 = maps:put(coparty_id,CoPartyID,Data1),
%     Data3 = maps:put(session_id,SessionID,Data2),
%     %% exchange init message
%     CoPartyID ! {PID, init},
%     receive {CoPartyID, init} ->
%       ?VSHOW("\n\t\t\tnow telling session (~p) ready,\n\t\t\tand waiting for signal to start.\n",[SessionID],Data3),
%       %% tell session ready to proceed
%       SessionID ! {self(), ready},
%       {ok, Data3}
%     end
%   end.
% %%




%% @docs default map for stubs
default_stub_data() -> #{timers=>maps:new(),msgs=>maps:new(),logs=>maps:new(),coparty_id=>undefined, options => #{presistent_nonblocking_payload_workers=>true, output_logs_to_file=>true, logs_written_to_file=>false}}.





%%%%%%%%%%%%%%%%%%%%%
%%% timer management
%%%%%%%%%%%%%%%%%%%%%

%% @docs tells the monitor of the process to set the timer of Name to Duration.
%% if the timer is already set, then the timer is reset.
%% similar to the other definitions of `set_timer`, except goes via the monitor.
set_timer(Name, Duration, #{coparty_id:=CoParty,timers:=Timers}=Data) when ?MONITORED=:=true -> 
  ?VSHOW("about to call (~p).",[CoParty],Data),
  %% call monitor synchronously to do this
  %% monitor returns their updated copy of timer map.
  Timers1 = gen_statem:call(CoParty,{set_timer, {Name, Duration}, Timers}),
  ?VSHOW("\n\treceived response from (~p),\n\told timers: ~p,\n\tnew timers: ~p.\n",[CoParty,Timers,Timers1],Data),
  %% return with updated timers
  maps:put(timers,Timers1,Data);
%%

%% @docs resets timer that already exists (for unmonitored process).
set_timer(Name, Duration, #{timers:=Timers}=Data) when is_map_key(Name,Timers) -> 
  %% cancel timer
  erlang:cancel_timer(maps:get(Name,Timers)),
  %% start new timer
  TID = erlang:start_timer(Duration, self(), Name),
  Data1 = maps:put(timers, maps:put(Name, TID, Timers), Data),
  ?VSHOW("\n\treset timer ~p (~p),\n\told data: ~p,\n\tnew data: ~p.\n",[Name,TID,Data,Data1],Data1),
  Data;
%%

%% @docs starts new timer that did not exist (for unmonitored process).
set_timer(Name, Duration, #{timers:=Timers}=Data) -> 
  %% start new timer
  TID = erlang:start_timer(Duration, self(), Name),
  Data1 = maps:put(timers, maps:put(Name, TID, Timers), Data),
  ?VSHOW("\n\tset new timer ~p (~p),\n\told data: ~p,\n\tnew data: ~p.\n",[Name,TID,Data,Data1],Data1),
  Data1.
%%

%% @doc retrieves timer pid from data if exists.
%% note: does not require different functionality when monitored since the stub process always has a copy of the timers in their Data.
get_timer(Name, #{timers:=Timers}=_Data) 
when is_atom(Name) and is_map_key(Name, Timers) -> 
  maps:get(Name, Timers);
%%

%% @doc returns `{ko, no_such_timer}` if timer does not exist.
get_timer(_Name, #{timers:=_Timers}=_Data)
when not is_map_key(_Name, _Timers) -> 
  ?VSHOW("\n\ttimer (~p) not found in timers:\n\t~p.\n",[_Name,_Timers],_Data),
  {ko, no_such_timer}.
%%

%% @doc kills all active timers
% kill_timers(#{timers:=Timers}=_Data) ->
%   maps:fold(fun(_K,TimerID,_) ->
%     exit(TimerID,normal)
%   end, [], Timers).
% %%

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% message management (received)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc saves message to data to front of list under that label
save_msg(Kind, Label, Payload, #{logs:=Logs,msgs:=Msgs}=Data) 
when is_atom(Kind) and is_atom(Label) ->
  case Kind of 
    send -> MapName = logs, Map = Logs;
    recv -> MapName = msgs, Map = Msgs
  end,
  %% add to head of corresponding list
  maps:put(MapName, maps:put(Label, [Payload]++maps:get(Label,Map,[]), Map), Data).
%%


%% @doc retrieves message from front of list
get_msg(Kind, Label, #{logs:=Logs,msgs:=Msgs}=_Data) 
when is_atom(Kind) and is_atom(Label) ->
  case Kind of 
    send -> Map = Logs;
    recv -> Map = Msgs
  end,
  case maps:get(Label, Map, []) of
    [] -> undefined;
    [H|_T] -> H
  end.
%%

%% @doc retrieves all messages under label
get_msgs(Kind, Label, #{logs:=Logs,msgs:=Msgs}=_Data) 
when is_atom(Kind) and is_atom(Label) ->
  case Kind of 
    send -> Map = Logs;
    recv -> Map = Msgs
  end,
  case maps:get(Label, Map, []) of
    [] -> undefined;
    [_H|_T]=All -> All
  end.
%%

%% @doc by default will all be for recving messages
save_msg(Label, Payload, Data) when is_atom(Label) and is_map(Data) -> save_msg(recv, Label, Payload, Data).
get_msg(Label, Data) when is_atom(Label) and is_map(Data) -> get_msg(recv, Label, Data).
get_msgs(Label, Data) when is_atom(Label) and is_map(Data) -> get_msgs(recv, Label, Data).



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% non-blocking behaviour: payloads
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc Calls Fun with Args and forwards the result to PID.
%% If Fun completes within Timeout milliseconds, returns Result.
%% Otherwise signals PID 'ko' since it took too long.
nonblocking_payload(Fun, {Label,_}=Args, PID, Timeout, #{options:=#{presistent_nonblocking_payload_workers:=IsPersistent}}=Data) 
when is_integer(Timeout) ->
  spawn( fun() -> 
    Waiter = self(),
    TimeConsumer = spawn( fun() -> Waiter ! {self(), ok, Fun(Args)} end ),
    receive 
      {TimeConsumer, ok, Result} -> 
        ?VSHOW("\n\tpayload completed within (~pms),\n\tResult: ~p.\n",[Timeout,Result],Data),
        %% check structure of result
        case Result of

          %% if appears to be payload, then return as is 
          {_Label,_Payload} -> PID ! {self(), ok, Result};
        
          %% otherwise, wrap with label
          _ -> PID ! {self(), ok, {Label,Result}}
        end

    after Timeout -> 

      case IsPersistent of 

        %% if persistent, send ko to stub, but then wait to receive message and still forward on
        true -> 
          PID ! {self(), ko},
          %
          receive {TimeConsumer, ok, Result} -> 
            ?VSHOW("\n\t(persistent) payload completed (~pms),\n\tResult: ~p.\n",[Timeout,Result],Data),
            %% check structure of result
            case Result of

              %% if appears to be payload, then return as is 
              {_Label,_Payload} -> PID ! {self(), ok, Result};
            
              %% otherwise, wrap with label
              _ -> PID ! {self(), ok, {Label,Result}}
            end
          end;

        %% if not persistent, then just return to stub and kill processor
        _ ->
          ?VSHOW("\n\tpayload did not complete within (~pms) sending ko.",[Timeout],Data),
          PID ! {self(), ko}, 
          exit(TimeConsumer, normal) 
        end
    end 
  end );
%%

%% @doc Calls Fun with Args and forwards the result to PID.
%% this version takes a reference to a timer directly
%% @see nonblocking_payload with Timeout
nonblocking_payload(Fun, Args, PID, TimerRef, Data) 
when is_reference(TimerRef) ->
  ?VSHOW("\n\tfetching value of timer-ref (~p).",[TimerRef],Data),
  Duration = erlang:read_timer(TimerRef),
  ?VSHOW("\n\tremaining duration timer is (~pms).",[Duration],Data),
  nonblocking_payload(Fun, Args, PID, Duration, Data);
%%

%% @doc Calls Fun with Args and forwards the result to PID.
%% @see nonblocking_payload with Timeout
nonblocking_payload(Fun, Args, PID, Timer, Data) 
when is_atom(Timer) ->
  ?VSHOW("\n\tfetching ref of timer (~p).",[Timer],Data),
  TimerRef = get_timer(Timer,Data),
  nonblocking_payload(Fun, Args, PID, TimerRef, Data).
%%


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% non-blocking behaviour: selection
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @doc Calls Fun with Args and forwards the result to nonblocking_payload and then to PID.
%% If Fun completes within Timeout milliseconds, then Result is passed to nonblocking_payload.
%% If nonblocking_payload responds too late, ko is sent back to PID.
nonblocking_selection(Fun, Args, PID, Timeout, Data) when is_integer(Timeout) ->
  spawn( fun() -> 
    %% spawn timer in the case of being passed to nonblocking_payload, need to take into account the duration of Fun
    Timer = erlang:start_timer(Timeout, self(), nonblocking_selection),
    ?VSHOW("\n\tstarted timer (~p)",[Timer],Data),
    Selector = self(),
    %% spawn process in same node to send back results of selection
    SelectingWorker = spawn( fun() -> Selector ! {self(), ok, Fun(Args)} end ),
    ?VSHOW("\n\twaiting to get selection back from (~p)",[SelectingWorker],Data),
    receive 
      %% if worker process determines selection, and returns necessary function/args to obtain payload to send
      {SelectingWorker, ok, {PayloadFun, PayloadArgs}=R} -> 
        ?VSHOW("\n\tselection made before (~p) completes,\n\tResult: ~p.",[Timer,R],Data),
        %% spawn new process using function to obtain payload
        NonBlocking = nonblocking_payload(PayloadFun, PayloadArgs, self(), Timer, Data),
        ?VSHOW("\n\twaiting to get payload back from (~p).",[NonBlocking],Data),
        %% forward result of nonblocking_waiter to PID
        receive 
          {NonBlocking, ok, {_Label, _Payload}=Result} -> 
            ?VSHOW("\n\tpayload received: (~p: ~p).",[_Label, _Payload],Data),
            PID ! {self(), ok, Result};
          {NonBlocking, ko} -> 
            ?VSHOW("\n\tpayload returned ko.",[],Data),
            PID ! {self(), ko}, 
            exit(NonBlocking, normal) 
          end;
      %% if timer expires first, signal PID that after-branch should be taken and terminate workers
      {timeout, Timer, nonblocking_selection} -> 
        ?VSHOW("s\n\telecting worker took longer than (~p) to complete.",[Timer],Data),
        PID ! {self(), ko}, 
        exit(SelectingWorker, normal) 
    end 
  end );
%%

%% @doc re-directs to function that takes integer value, which is here derived from the timer.
nonblocking_selection(Fun, Args, PID, Timer, Data) when is_atom(Timer) ->
  TID = get_timer(Timer,Data),
  ?VSHOW("\n\tfetching value of timer (~p, ~p).",[Timer,TID],Data),
  Duration = erlang:read_timer(TID),
  ?VSHOW("\n\tremaining duration of (~p) is: ~pms.",[Timer,Duration],Data),
  nonblocking_selection(Fun, Args, PID, Duration, Data).
%%


%%%%%%%%%%%%%%%%%%%%%%
%%% proposed snippets 
%%%%%%%%%%%%%%%%%%%%%%

%% @doc Wrapper function for sending the result of Fun with Label if it finished within Timeout milliseconds
send_before(CoPartyID, {Label, {Fun, Args}}, Timeout, Data) 
when is_pid(CoPartyID) and is_atom(Label) -> 
  NonBlocking = nonblocking_payload(Fun, Args, self(), Timeout, Data),
  ?VSHOW("\n\twaiting to receive payload from (~p) to send (~p).",[NonBlocking,Label],Data),
  receive 
    {NonBlocking, ok, Payload} -> 
      ?VSHOW("\n\tfor (~p), payload: ~p.",[Label,Payload],Data),
      send(CoPartyID, {Label, Payload}, Data);
    {NonBlocking, ko} -> 
      ko
  end.

%% @doc 
% recv_before(MonitorID, Label, Timeout) when ?MONITORED and is_pid(MonitorID) and is_atom(Label) -> gen_statem:call(MonitorID, {recv, Label, Timeout});

%% @doc 
recv_before(CoPartyID, Label, Timeout, Data) 
when is_pid(CoPartyID) and is_atom(Label) -> 
  ?VSHOW("\n\twaiting to receive (~p) within (~pms),",[Label,Timeout],Data),
  receive 
    {CoPartyID, Label, Payload} -> 
      ?VSHOW("recv'd (~p: ~p).",[Label,Payload],Data),
      {ok, Payload} 
  after Timeout -> 
    ?VSHOW("\n\ttimeout, did not recv (~p).",[Label],Data),
    {ko, timeout} 
  end.

%% @doc Wrapper function for sending messages asynchronously via synchronous Monitor
% send(MonitorID, {Label, _Payload}=Msg) when ?MONITORED and is_pid(MonitorID) and is_atom(Label) -> gen_statem:call(MonitorID, {send, Msg});

%% @doc Wrapper function for sending messages asynchronously
send(CoPartyID, {Label, _Payload}=Msg, Data) 
when is_pid(CoPartyID) and is_atom(Label) -> 
  CoPartyID ! {self(), Msg}, 
  ?VSHOW("sent (~p).",[Msg],Data),
  ok.

%% @doc Wrapper function for receiving message asynchronously via synchronous Monitor
% recv(MonitorID, Label) when is_pid(MonitorID) and is_atom(Label) -> gen_statem:call(MonitorID, {recv, Label});

%% @doc Wrapper function for receiving message asynchronously
recv(CoPartyID, Label, Data) 
when is_pid(CoPartyID) and is_atom(Label) -> 
  ?VSHOW("\n\twaiting to receive (~p).",[Label],Data),
  receive 
    {CoPartyID, Label, Payload} -> 
      ?VSHOW("recv'd (~p: ~p).",[Label,Payload],Data),
      {ok, Payload} 
  end.



