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
          handle_cast/2
          % handle_info/2
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
  ?SHOW("\n\t\tParams:\t~p.\n",[Params],Params),

  ?assert(is_map_key(module,Params)),
  ?assert(is_map_key(name,Params)),
  ?assert(is_map_key(roles,Params)),

  %% unpack params
  #{roles:=Roles,name:=Name,module:=Module} = Params,

  %% update roles to display if initialised
  Roles1 = lists:foldl(fun(#{name:=RoleName,module:=RoleModule}=_R, L) -> 
    L++[#{name=>RoleName,module=>RoleModule,pid=>undefined,init=>false,status=>undefined}]
  end, [], Roles),

  % %% create ets for session
  % ets:new(?ETS, [set,named_table,protected]),
  % ets:insert(?ETS, {init_session_id, self()}),

  % %% store role names
  % RoleNames = lists:foldl(fun(#{name:=RoleName}=_R,L) -> L++[RoleName] end, [], Roles),
  % ets:insert(?ETS, {roles, RoleNames}),

  % %% store roles
  % lists:foreach(fun(#{name:=RoleName,module:=RoleModule}=Role) ->
  %   %% should be unique
  %   %% make sure has not already been added
  %   ?assert(length(ets:lookup(?ETS,RoleName))==0),
  %   %% add to ets
  %   ets:insert(?ETS, {RoleName,#{name=>RoleName,module=>RoleModule,pid=>undefined,init=>false}})
  % end, Roles),

  % SessionID ! {{name,Name},{module,Module},{init_id,InitID},{pid,self()}},

  % [{app_id,AppID}|_T] = ets:lookup(tpri,app_id),
  % printout("~p, lookup AppID: ~p.", [?FUNCTION_NAME, AppID]),
  % AppID ! {tpri, server_id, self()},

  % {ok, _SupID} = toast_sup:start_link(Params),

  {ok, #{state=>init_state,name=>Name,module=>Module,roles=>Roles1}, 0}.


%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%% @doc handle reception of
handle_info(timeout, #{state:=init_state}=_State) ->
  %% get existing ets
  Role = ets_take_single(?ETS,Name),
  %% update
  Role1 = maps:put(pid,StubID,Role),
  Role2 = maps:put(init,true,Role1),
  %% add to ets
  ets:insert(?ETS, {Name, Role2}),
  %% check what state to be in
  NextState = case length(lists:foldl(fun(#{init:=IsInit}=_R,I) -> case IsInit of true -> I+1; _ -> I end end, 0, ets:lookup(?ETS,roles)))==2 of true -> live_state; _ -> init_state end,
  %% make reply
  Reply = ok,
  %% return
  {reply,Reply,NextState}.
%%

%% @doc handle reception of
handle_info({name,Name},{module,Module},{init_id,_InitID},{pid,StubID}, #{state:=init_state}=_State) ->
  %% get existing ets
  Role = ets_take_single(?ETS,Name),
  %% update
  Role1 = maps:put(pid,StubID,Role),
  Role2 = maps:put(init,true,Role1),
  %% add to ets
  ets:insert(?ETS, {Name, Role2}),
  %% check what state to be in
  NextState = case length(lists:foldl(fun(#{init:=IsInit}=_R,I) -> case IsInit of true -> I+1; _ -> I end end, 0, ets:lookup(?ETS,roles)))==2 of true -> live_state; _ -> init_state end,
  %% make reply
  Reply = ok,
  %% return
  {reply,Reply,NextState}.
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

