%%%-------------------------------------------------------------------
%% @doc toast top level supervisor.
%% @end
%%%-------------------------------------------------------------------

-module(toast_sup).
-file("toast_sup.erl", 1).
-behaviour(supervisor).

-include("toast_data_records.hrl").

%% supervisor exports
-export([ start_link/0,
          init/1 ]).
        
-export([ start_link/1 ]).

-include("toast_app_params.hrl").
-include("sup_flags.hrl").
-include("child_spec.hrl").
-include("ets_get.hrl").

-include("printout.hrl").

%% supervisor -- start_link
start_link() -> ?MODULE:start_link([]).

start_link(Params) -> 
  printout("~p.", [?FUNCTION_NAME]),

  {ok, PID} = supervisor:start_link({local, ?MODULE}, ?MODULE, Params),
  {ok, PID}.

%% sup_flags() = #{strategy => strategy(),         % optional
%%                 intensity => non_neg_integer(), % optional
%%                 period => pos_integer()}        % optional
%% child_spec() = #{id => child_id(),       % mandatory
%%                  start => mfargs(),      % mandatory
%%                  restart => restart(),   % optional
%%                  shutdown => shutdown(), % optional
%%                  type => worker(),       % optional
%%                  modules => modules()}   % optional

%% init
init(Params) -> 
  printout("~p.", [?FUNCTION_NAME]),
  init(Params, #{ roles => [], child_options => default_child_options(), sup_flags => default_sup_flags() }).

init([], Params) -> init(finished, Params);

init([H|T], Params) -> 
  case H of 
    {role, RoleModuleName} ->
      %% add new role 
      Params1 = maps:update_with(roles, fun(V) -> V ++ [RoleModuleName] end, [RoleModuleName], Params);
    {Key, Val} ->
      %% other param
      Params1 = maps:put(Key, Val, Params);
    _ -> 
      %% no change
      Params1 = Params
  end,
  init(T, Params1);

%% finished parsing both params
init(finished, Params) ->
  % printout("~p, finished.", [?FUNCTION_NAME]),
  printout("~p, finished,\n\tparams: ~p.", [?FUNCTION_NAME, Params]),

  ChildOptions = maps:get(child_options, Params),
  SupFlags = maps:get(sup_flags, Params),
  SupFlags1 = maps:put(auto_shutdown, all_significant, SupFlags),

  Roles = maps:get(roles, Params),
  printout("~p, num_roles: ~p.", [?FUNCTION_NAME, length(Roles)]),
  printout("~p, roles:\n\t~p.", [?FUNCTION_NAME, Roles]),

  SessionID = ets_get(toast,session_id),
  printout("~p, session_id: ~p.",[?FUNCTION_NAME, SessionID]),

  %% create supervisor for each role
  SpecFun = fun(#{module:=ModuleName,name:=RoleName}=Role, AccIn) -> 
      RegID = RoleName,
      AccIn ++ [child_spec(ModuleName,RegID,ChildOptions,[{session_id,SessionID},{role,Role}])]
  end,

  ChildSpecs = lists:foldl(SpecFun, [], Roles),

  {ok, {SupFlags1, ChildSpecs}}.
