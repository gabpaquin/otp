%%
%% %CopyrightBegin%
%% 
%% Copyright Ericsson AB 1997-2011. All Rights Reserved.
%% 
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%% 
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%% 
%% %CopyrightEnd%
%%

%%%------------------------------------------------------------------
%%% Purpose:Convert Erlang files to html. (Pretty faaast... :-)
%%%------------------------------------------------------------------

%--------------------------------------------------------------------
% Some stats (Sparc5@110Mhz):
% 4109 lines (erl_parse.erl):              3.00 secs
% 1847 lines (application_controller.erl): 0.57 secs
% 3160 lines (test_server.erl):            1.00 secs
% 1199 lines (ts_estone.erl):              0.35 secs
%
% Avg: ~4.5e-4s/line, or ~0.45s/1000 lines, or ~2200 lines/sec.
%--------------------------------------------------------------------

-module(erl2html2).
-export([convert/2, convert/3]).

convert([], _Dest) ->   % Fake clause.
    ok;
convert(File, Dest) ->
    %% The generated code uses the BGCOLOR attribute in the
    %% BODY tag, which wasn't valid until HTML 3.2.  Also,
    %% good HTML should either override all colour attributes
    %% or none of them -- *never* just a few.
    %%
    %% FIXME: The colours should *really* be set with
    %% stylesheets...
    Header = ["<!DOCTYPE HTML PUBLIC "
	      "\"-//W3C//DTD HTML 3.2 Final//EN\">\n"
	      "<!-- autogenerated by '"++atom_to_list(?MODULE)++"'. -->\n"
	      "<html>\n"
	      "<head><title>", File, "</title></head>\n\n"
	      "<body bgcolor=\"white\" text=\"black\""
	      " link=\"blue\" vlink=\"purple\" alink=\"red\">\n"],
    convert(File, Dest, Header).
    
convert(File, Dest, Header) ->
    case file:read_file(File) of
	{ok, Bin} ->
	    Code=binary_to_list(Bin),
	    statistics(runtime),
	    {Html1, Lines} = root(Code, [], 1),
	    Html = [Header,
		    "<pre>\n", Html1, "</pre>\n", 
		    footer(Lines),"</body>\n</html>\n"],
	    file:write_file(Dest, Html);
	{error, Reason}  ->
	    {error, Reason}
    end.

root([], Res, Line) ->
    {Res, Line};
root([Char0|Code], Res, Line0) ->
    Char = [Char0],
    case Char of
	"-" ->
	    {Match, Line1, NewCode0, AttName} = 
		read_to_char(Line0+1, Code, [], [$(, $.]),
	    {_, Line2, NewCode, Stuff} = read_to_char(Line1, NewCode0, [], $\n),
	    NewRes = [Res,linenum(Line0),"-<b>",AttName,
			 "</b>",Match, Stuff, "\n"],
	    root(NewCode, NewRes, Line2);
	"%" ->
	    {_, Line, NewCode, Stuff} = read_to_char(Line0+1, Code, [], $\n),
	    NewRes = [Res,linenum(Line0),"<i>%",Stuff,"</i>\n"],
	    root(NewCode, NewRes, Line);
	"\n" ->
	    root(Code, [Res,linenum(Line0), "\n"], Line0+1);
	" " ->
	    {_, Line, NewCode, Stuff} = read_to_char(Line0+1, Code, [], $\n),
	    root(NewCode, [Res,linenum(Line0)," ",Stuff, "\n"],
		 Line);
	"\t" ->
	    {_, Line, NewCode, Stuff} = read_to_char(Line0+1, Code, [], $\n),
	    root(NewCode, [Res,linenum(Line0),"\t",Stuff, "\n"],
		 Line);
	[Chr|_] when Chr>96, Chr<123 ->
	    %% Assumed to be function/clause start.
	    %% FIXME: This will trivially generate non-unique anchors
	    %% (one for each clause) --- which is illegal HTML.
	    {_, Line1, NewCode0, FName0} = read_to_char(Line0+1, Code, [], $(),
	    {_, Line2, NewCode, Stuff} = 
                read_to_char(Line1,NewCode0, [], $\n),
	    FuncName = [[Chr],FName0],
	    NewRes=[Res,"<a name=",FuncName,">",
		    linenum(Line0),"<b>",FuncName,"</b></a>",
		    "(",Stuff, "\n"],
	    root(NewCode, NewRes, Line2);
	Chr ->
	    {_, Line, NewCode, Stuff} = read_to_char(Line0+1, Code, [], $\n),
	    root(NewCode, [Res,linenum(Line0),Chr,Stuff, "\n"],
		 Line)
    end.

read_to_char(Line0, [], Res, _Chr) ->
    {nomatch, Line0, [], Res};
read_to_char(Line0, [Char|Code], Res, Chr) ->
    case Char of
	Chr -> {Char, Line0, Code, Res};
	_ when is_list(Chr) ->
	    case lists:member(Char,Chr) of
		true -> 
		    {Char, Line0, Code, Res};
		false -> 
		    {Line,NewCode,NewRes} = maybe_convert(Line0,Code,Res,Char),
		    read_to_char(Line, NewCode, NewRes, Chr)
	    end;
	_ ->
	    {Line,NewCode,NewRes} = maybe_convert(Line0,Code,Res,Char),
	    read_to_char(Line,NewCode, NewRes, Chr)
    end.

maybe_convert(Line0,Code,Res,Chr) ->
    case Chr of
	%% Quoted stuff should not have the highlighting like normal code
	%% FIXME: unbalanced quotes (e.g. in comments) will cause trouble with
	%% highlighting and line numbering in the rest of the module.
	$" ->  
	    {_, Line1, NewCode, Stuff0} = read_to_char(Line0, Code, [], $"),
            {Line2,Stuff} = add_linenumbers(Line1,lists:flatten(Stuff0),[]),
	    {Line2,NewCode,[Res,$",Stuff,$"]};
	%% These chars have meaning in HTML, and *must* *not* be
	%% written as themselves.
	$& ->
	    {Line0, Code, [Res,"&amp;"]};
	$< ->
	    {Line0, Code, [Res,"&lt;"]};
	$> ->
	    {Line0, Code, [Res,"&gt;"]};
	%% Everything else is simply copied.
	OtherChr ->
	    {Line0, Code, [Res,OtherChr]}
    end.

add_linenumbers(Line,[Chr|Chrs],Res) ->
    case Chr of
	$\n -> add_linenumbers(Line+1,Chrs,[Res,$\n,linenum(Line)]);
	_  -> add_linenumbers(Line,Chrs,[Res,Chr])
    end;
add_linenumbers(Line,[],Res) ->
    {Line,Res}.

%% Make nicely indented line numbers.
linenum(Line) ->
    Num = integer_to_list(Line),
    A = case Line rem 10 of
	    0 -> "<a name=\"" ++ Num ++"\"></a>";
	    _ -> []
	end,
    Pred =
	case length(Num) of
	    Length when Length < 5 ->
		lists:duplicate(5-Length,$\s);
	    _ -> 
		[]
	end, 
    [A,Pred,integer_to_list(Line),":"].

footer(_Lines) ->
    "".
%%    {_, Time} = statistics(runtime),
%%    io:format("Converted ~p lines in ~.2f Seconds.~n",
%%	      [Lines, Time/1000]),
%%    S = "<i>The transformation of this file (~p lines) took ~.2f seconds</i>",
%%    F = lists:flatten(io_lib:format(S, [Lines, Time/1000])),
%%    ["<hr size=1>",F,"<br>\n"].
