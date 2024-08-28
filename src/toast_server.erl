-module(toast_server).
-file("toast_server.erl", 1).
-behaviour(gen_server).

-include_lib("stdlib/include/assert.hrl").

-include("toast_data_records.hrl").

-define(ETS, toast_session).

-define(SHOW_ENABLED, true).

-define(SHOW(Str, Args, Data), case ?SHOW_ENABLED of true -> printout(Data, "~p, "++Str, [?FUNCTION_NAME]++Args); _ -> ok end).

-define(SHOW_VERBOSE, ?SHOW_ENABLED and true).

-define(VSHOW(Str, Args, Data), case ?SHOW_VERBOSE of true -> printout(Data, "(verbose, ln.~p) ~p, "++Str, [?LINE,?FUNCTION_NAME]++Args); _ -> ok end).

%% gen_server API
-export([ start_link/0,
          init/1,
          stop/0,
          handle_call/3,
          handle_cast/2,
          handle_info/2
         ]).

-export([ start_link/1 ]).

% -record(state, {}).

-include("printout.hrl").
-include("ets_get.hrl").
-include("sup_flags.hrl").
-include("toast_app_params.hrl").

%% gen_server -- start_link, called to start
start_link() -> ?MODULE:start_link([]).

start_link(Params) -> 
  printout("~p.", [?FUNCTION_NAME]),

  %% get name
  Name = maps:get(name,maps:get(role,maps:from_list(Params)),?MODULE),

  {ok, PID} = gen_server:start_link({local, Name}, ?MODULE, Params, []),
  {ok, PID}.
%%

stop() -> 
  io:format("\n\t\tServer/Session (~p) stopping.\n",[self()]),
  timer:sleep(50),
  exit(whereis(?MODULE), shutdown).

%% gen_server -- init, called after gen_server:start_link()
%% called once server started and registered process (ready to receive)
init(Args) -> 
  Params = maps:from_list(Args),
  ?SHOW("\n\tParams:\t~p.\n\n\n\n\n",[Params],Params),
  % timers:sleep(5000),

  ?assert(is_map_key(role,Params)),
  ?assert(is_map_key(roles,Params)),

  %% unpack params
  #{roles:=Roles,role:=#{name:=Name,module:=Module}} = Params,

  %% update roles to display if initialised
  Roles1 = lists:foldl(fun(#{name:=RoleName,module:=RoleModule}=_R, L) -> 
    L++[#{name=>RoleName,module=>RoleModule,init_id=>undefined,pid=>undefined,init=>false,ready=>false,started=>false,status=>undefined}]
    % maps:put(RoleName,#{name=>RoleName,module=>RoleModule,pid=>undefined,init=>false,status=>undefined},L)
  end, [], Roles),

  State = #{state=>init_ids_state,name=>Name,module=>Module,roles=>Roles1,params=>Params},
  ?SHOW("\n\tState: ~p.\n",[State],Params),

  {ok, State, 0}.


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @doc periodically check if other parties in session are 
handle_info(timeout, #{state:=init_ids_state=StateName,roles:=Roles,params:=Params}=State) ->
  ?SHOW("~p.",[StateName],Params),

  %% check if each role is registered under their name
  {InitRoleNum,NewRoles} = lists:foldl(fun(#{name:=Name,init_id:=InitID}=R, {I,L}) -> 
    case InitID of 
      %% currently undefined, check for id
      undefined -> 
        NewInitID = whereis(Name),
        ?SHOW("\n\tRole (~p) currently undefined.\n\twhereis(~p) = ~p.\n",[Name,Name,NewInitID],Params),
        case is_pid(NewInitID) of 
          %% is id, add to state data and send message
          true -> 
            NewInitID ! {init_state_message,{session_id,self()}},
            {I+1, L++[maps:put(init_id,NewInitID,R)]};

          %% is not id, check again later
          _ -> {I, L++[R]}

        end;

      %% already got pid, leave unchanged
      _ -> {I+1,L++[R]} 
    end
  end, {0, []}, Roles),
  
  %% update state roles
  State1 = maps:put(roles,NewRoles,State),

  case InitRoleNum==length(Roles) of 

    %% all roles are init for next phase
    true -> 
      ?SHOW("\n\tAll roles located for next phase,\n\t~p\n",[NewRoles],Params),
      {noreply, maps:put(state,recv_ids_state,State1)};

    %% still need to wait some more
    _ -> 
      ?SHOW("\n\tOnly (~p/~p) roles located.\n",[InitRoleNum,length(Roles)],Params),
      {noreply, State1, 50}

  end;
%%

%% @doc handle reception of initial ids 
handle_info({{name,Name},{module,Module},{init_id,_InitID},{pid,StubID}}, #{state:=recv_ids_state=StateName,roles:=Roles,params:=Params}=State) ->
  ?SHOW("~p.",[StateName],Params),

  %% update corresponding roles id
  NewRoles = lists:foldl(fun(#{name:=RoleName}=R, L) -> 
    case RoleName=:=Name of 
      %% corresponding role
      true -> L++[maps:put(pid,StubID,R)];
      %% some other role, leave unchanged
      _ -> L++[R]
    end
  end, [], Roles),

  %% determine next state
  NextState = case lists:foldl(fun(#{pid:=PID}=R, B) -> case PID=:=undefined of true -> B and false; _ -> B and true end end, true, NewRoles) of true -> exchange_ids_state; _ -> recv_ids_state end,
  
  %% update state data 
  State1 = maps:put(roles,NewRoles,State),
  State2 = maps:put(state,NextState,State1),

  case NextState of 

    %% if running state, then go to timeout and send start to both
    exchange_ids_state -> 
      ?SHOW("\n\tAll roles init.\n",[],Params),
      {noreply, State2, 0};
    
    %% wait for other init
    _ -> 
      ?SHOW("\n\tRecv'd init from (~p).\n",[StubID],Params),
      {noreply, State2}

  end;
%%

%% @doc handle exchange of ids
handle_info(timeout, #{state:=exchange_ids_state=StateName,roles:=Roles,params:=Params}=State) ->
  ?SHOW("~p.",[StateName],Params),

  %% get each role in binary session
  ?assert(length(Roles)==2),
  RoleA = lists:nth(1,Roles),
  RoleB = lists:nth(2,Roles),

  %% get ids of each role
  #{pid:=APID} = RoleA,
  #{pid:=BPID} = RoleB,

  %% exchange
  APID ! {self(), {coparty_id, BPID}},
  BPID ! {self(), {coparty_id, APID}},
  ?SHOW("\n\tExchanged PIDs of:\n\t\t(~p)\n\t\t(~p).\n",[RoleA,RoleB],Params),

  State1 = maps:put(state,ready_state,State),

  {noreply, State1};
%%

%% @doc handle reception of ready 
handle_info({StubID,ready}, #{state:=ready_state=StateName,roles:=Roles,params:=Params}=State) ->
  ?SHOW("~p.",[StateName],Params),

  %% update corresponding roles id
  NewRoles = lists:foldl(fun(#{pid:=PID}=R, L) -> 
    case PID=:=StubID of 
      %% corresponding role
      true -> L++[maps:put(ready,true,R)];
      %% some other role, leave unchanged
      _ -> L++[R]
    end
  end, [], Roles),

  %% determine next state
  NextState = case lists:foldl(fun(#{ready:=Ready}=R, B) -> case Ready of true -> B and true; _ -> B and false end end, true, NewRoles) of true -> start_state; _ -> ready_state end,

  State1 = maps:put(state,NextState,State),
  State2 = maps:put(roles,NewRoles,State1),

  case NextState of 

    %% if running state, then go to timeout and send start to both
    start_state -> 
      ?SHOW("\n\tAll roles ready.\n",[],Params),
      {noreply, State2, 0};
    
    %% wait for other ready
    _ -> 
      ?SHOW("\n\tRecv'd ready from (~p).\n",[StubID],Params),
      {noreply, State2}

  end;
%%

handle_info(timeout, #{state:=start_state=StateName,roles:=Roles,params:=Params}=State) ->
  ?SHOW("~p.",[StateName],Params),

  %% get each role in binary session
  ?assert(length(Roles)==2),
  RoleA = lists:nth(1,Roles),
  RoleB = lists:nth(2,Roles),

  %% get ids of each role
  #{pid:=APID} = RoleA,
  #{pid:=BPID} = RoleB,

  %% exchange
  APID ! {self(), start},
  BPID ! {self(), start},
  ?SHOW("\n\tSent start signal to:\n\t\t(~p)\n\t\t(~p).\n",[RoleA,RoleB],Params),

  %% update roles
  RoleA1 = maps:put(started,true,RoleA),
  RoleB1 = maps:put(started,true,RoleB),

  State1 = maps:put(state,running_state,State),
  State2 = maps:put(roles,[RoleA1,RoleB1],State1),

  {noreply, State2};
%%

handle_info(Msg, #{state:=running_state=StateName,params:=Params}=State) ->
  ?SHOW("~p,\n\tUnhandled msg: ~p.\n",[StateName,Msg],Params),
  {noreply, State}.
%%

% handle_call(, _From, _State) ->

handle_call(_Request, _From, State) -> 
  Reply = ok,
  {reply, Reply, State}.







handle_cast(_Request, State) -> 
  {noreply, State}.




start(Args) when is_list(Args) -> start(normal, Args).

start(Type, Args) when is_list(Args) -> 
  printout("~p, type=~p.", [?FUNCTION_NAME, Type]),
  printout("~p, args:\n\t~p.", [?FUNCTION_NAME, Args]),

  %% create ets for tpri app
  ets:new(toast, [set,named_table,protected]),
  ets:insert(toast, {init_session_id, self()}),
  printout("~p, created ets, added self()=~p.", [?FUNCTION_NAME, self()]),

  timer:sleep(50),


  % printout("~p, app sup started: ~p.\n", [?FUNCTION_NAME,SupID]),
  % ets:insert(toast, {sup_id, SupID}),
  % timer:sleep(50),


  %% get list of role names
  Roles = lists:foldl(fun(Elem,AccIn) -> 
      case Elem of
        {role, #{module:=_ModuleName,name:=_RoleName}} -> AccIn++[Elem];
        _ -> AccIn
      end
  end, [], Args),
  printout("~p, roles:\n\t~p.", [?FUNCTION_NAME, Roles]),

  % WorkerNum=length(Roles),
  % ets:insert(toast, {roles, Roles}),


  printout("~p, beginning ets setup.", [?FUNCTION_NAME]),
  Rs = ets_setup(length(Roles),[]),
  ets:insert(toast, {roles, Rs}),

  % ets_setup([], WorkerNum, RolePresets),
  % printout("~p, finished ets setup.\n", [?FUNCTION_NAME]),

  % printout("~p, ets:all() = ~p.\n",[?FUNCTION_NAME,ets:all()]),
  % timer:sleep(1000),

  printout("~p, ets:\n\t~p.\n", [?FUNCTION_NAME, ets_string(toast)]),

  % run(),
  ok.
%%



ets_setup(0, Rs) -> printout("~p, finished, roles:\n\t~p.",[?FUNCTION_NAME,Rs]),Rs;

ets_setup(Num, Rs) when Num>0 -> 
  receive 
    {RoleID, role, #{module:=_RoleModule,name:=_RoleName}=R} ->
      printout("~p,\n\t\t\treceived from (~p): ~p.\n",[?FUNCTION_NAME,RoleID,R]),
      ets:insert(toast, {RoleID, R}),
      ets_setup(Num-1, Rs++[RoleID])
    % _Else -> printout("~p, else:\n\t~p.",[?FUNCTION_NAME,_Else]),
    %   ets_setup(Num,Rs)
  end.

run() ->
  InitSessionID = ets_get_single(toast, session_id),
  SessionID = self(),

  %% get all roles
  Roles = ets_get_single(toast, roles),
  printout("~p, roles: ~p.", [?FUNCTION_NAME, Roles]),

  %% assuming only two roles
  A = lists:nth(1, Roles),
  B = lists:nth(2, Roles),

  printout("~p, exchanging IDs.",[?FUNCTION_NAME]),
  A ! {InitSessionID,{session_id,self()},{coparty_id,B}},
  B ! {InitSessionID,{session_id,self()},{coparty_id,A}},

  printout("~p, waiting for both to be ready.",[?FUNCTION_NAME]),
  receive 
    {A, ready} -> receive {B, ready} -> ok end;
    {B, ready} -> receive {A, ready} -> ok end
  end,
  printout("~p, both ready.",[?FUNCTION_NAME]),

  A ! {SessionID, start},
  B ! {SessionID, start},

  %% wait to see if any of them are restarted
  receive
    {{_Name1,_Module1,_ID1}=Info1, stopping, Reason1, Data1} ->
      printout("~p, received stop signal:\n\t\tInfo:\t~p,\n\t\tReason:\t~p,\n\t\tData:\t~p.\n",[?FUNCTION_NAME,Info1,Reason1,Data1]),
      receive
        {{_Name2,_Module2,_ID2}=Info2, stopping, Reason2, Data2} ->
          printout("~p, received stop signal:\n\t\tInfo:\t~p,\n\t\tReason:\t~p,\n\t\tData:\t~p.\n",[?FUNCTION_NAME,Info2,Reason2,Data2])
      end
  end,

  printout("~p, stopping.\n",[?FUNCTION_NAME]),
  % printout("~p, ets: ~p.\n",[?FUNCTION_NAME,ets:all()]),


  % SupID = ets_get(toast, sup_id),
  % printout("~p, stopping sup (~p).\n",[?FUNCTION_NAME,SupID]),
  % timer:sleep(500),

  % exit(SupID,normal),
  % timer:sleep(100),

  % stop(?MODULE).
  ok.
%%

