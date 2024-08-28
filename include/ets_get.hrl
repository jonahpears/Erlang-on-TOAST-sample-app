-compile({nowarn_unused_function, [ {ets_get_single,2}, {ets_take_single,2}, {ets_string,1} ]}).

ets_get_single(Table, Key) -> 
  Vals = ets:lookup(Table, Key),
  ?assert(length(Vals)==1),
  {_, Vals1} = lists:nth(1, Vals),
  Vals1.

ets_take_single(Table, Key) -> 
  Vals = ets:take(Table, Key),
  ?assert(length(Vals)==1),
  {_, Vals1} = lists:nth(1, Vals),
  Vals1.

ets_string(Table) -> ets:match_object(Table, {'$0', '$1'}).
