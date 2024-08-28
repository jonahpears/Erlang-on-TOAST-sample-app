%%%-------------------------------------------------------------------
%% @doc toast public API
%% @end
%%%-------------------------------------------------------------------

-module(toast_app).
-file("toast_app.erl", 1).
-behaviour(application).

-include("toast_data_records.hrl").

-export([start/2, stop/1]).

-export([ start/1,
          get_env/1
        ]).

-export([start/0]).
% -export([run/0]).
% -export([run_startup/3]).

-define(WORKER_NUM, 2).

-include_lib("stdlib/include/assert.hrl").

-include("printout.hrl").
-include("ets_get.hrl").
-include("sup_flags.hrl").
-include("toast_app_params.hrl").

get_env(Key) -> 
  case application:get_env(?MODULE, Key) of
    {ok, Val} -> {ok, Val};
    undefined -> undefined
  end.

start() -> error(no_params).
  % printout("~p, no parameters provided, using default.", [?FUNCTION_NAME]),
  % start(normal, [{use_preset, default}]).

start(Args) when is_list(Args) -> start(normal, Args).

start(Type, Args) when is_list(Args) -> 
  {ok, SupID} = toast_sup:start_link(Args),

  {ok, SupID}.

stop(_State) -> ok.
