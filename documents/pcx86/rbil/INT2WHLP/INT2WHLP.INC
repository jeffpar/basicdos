(* INT2WHLP Pascal Program Include File *)

(*
  Interrupt List -> WinHelp converter (c) 1994 by Christian MÅller-Planitz
  ------------------------------------------------------------------------
*)

(* v. 1.22 *)

const
  tableArraySize = 250; (* elements in table arrays *)

type
  stringPtr = ^string;
  categoryStringPtrArr = array['!'..#126] of stringPtr;
  titleStringPtrArr = array[byte] of stringPtr;
  stringListPtr = ^stringList;
  stringList = record next: stringListPtr; s: string; end;
    (* NB! The program relies on "next" being the first field *)
  stringListPtrPtr = ^stringListPtr;
  aliasStringType = string[119];
  tableArray = array[1..tableArraySize] of integer;

var
  flagStrings,categoryStrings,categoryKeyStrings: categoryStringPtrArr;
  INTtitles: titleStringPtrArr;

  CONST
	InPath  : dirStr = '';
	OutPath : dirStr = '';
	TopicNo : Word = 0;
	LastSection : String[3] = '';	{ stores number of last processed int }
	IntTopicStr : String[7] = '';	{ stores handle to page with subfunctions of the int's}
	highestTableNumber: string[7] = '0';
	tableDigits: integer = 5; (* prior to release 59: 4 *)
	filterFileName: pathStr = '';
	filtered: boolean = false;
	compression: string[19] = 'NO';
	emptyString: string[1] = '';
	noteString: string[5] = 'note';
	noneString: string[7] = '(none)';
	buildExpr: string = '';
	secReg: string[7] = ' '; (* secReg[1] = ' ' *)
	equStr: string[7] = ' Ax = ';
	equStr2: string[3] = ' = ';
	equBlanks: byte = 2;
	  (* These two variables can be changed to ' Ax=' and 0 by
	     program parameter -Q-. They control the format of search
	     strings as "INT nn AX = ahal" or "INT nn AX=ahal".
	     equStr[3] is assigned 'L', 'H', or 'X' by the program.
	  *)
	tables: boolean = true; (* enables table cross referencing *)
	backRef: boolean = false; (* disables the very first backward xref *)
	missingTableCounter: word = 0;
	missingTableLimit = 5; (* wait for user response when reached *)
	indexColumns: integer = 1;
	queuedEntry: string[127] = '';
	  (* stores an entry for the index, inserted by a call to insertQueued *)
	notesCount: word = 0;    (* counts "Notes" entries in index *)
	title: string[127] = ''; (* current "Notes" or "INT nn ... " *)
	lastINTno: integer = -1;
	firstAliasP: stringListPtr = NIL; (* aliases to be written to HPJ *)
	nl: string[5] = '\par '; (* global NewLine string for AddTopic *)
	indentIndex: string[7] = '\par   '; (* or '\par ' *)
	insertCounter: integer = 0; (* counts inserted table references *)
	tabTop: integer = 0; (* current top of table array *)
	maxTabTop: integer = 0; (* highest value of currentTabTop *)
	refTop: integer = 0; (* current top of reference array *)
	maxRefTop: integer = 0; (* highest value of currentRefTop *)
	warnings: word = 0; (* counts issued warnings *)

const
  (* The following typed constants controls some program behaviors. They
     can all be set under configuration file and program parameter control.
     The configuration section [OPTIONS] uses keys with the same names as
     the typed constants, and the program parameters are listed for each
     constant.
  *)
  singlesInMain: boolean = false;
	(* There are two levels in the Interrupts index: A main index
	   with an entry for each interrupt, and a page for each interrupt
	   number. If "singlesInMain" is true, the entry in the main index
	   refers directly to the interrupt text if there is only one entry
	   in the table for that interrupt, if  "singlesInMain" is false, the
	   entry in the main index refers to a page with only one field.
	   Controlled by program parameter -1.
	*)
  twoIndexes: boolean = true;
	(* If "twoIndexes" is true, the program mantains two indexes,
	   "Interrupt Index" with all the topics in the Interrupt List, and
	   "Interrupts" as described above. If the flag is false, only the
	   latter index is created.
	   Controlled by program parameter -2.
	*)
  errorLog: boolean = false;
	(* controles whether HCxx error messages are written to a log file,
	   or to the screen only.
	   Controlled by program parameter -E.
	*)
  indexHeaders: boolean = true;
	(* controles whether or not a heading "INT nn" is inserted for every
	   new interrupt number in the "Interrupt Index". Ignored if
	   "twoIndexes" is false.
	   Controlled by program parameter -H.
	*)
  markKeys: boolean = true;
	(* If true, keywords (like "See also:", "Notes:") are bolded, if
	   false, they are not.
	   Controlled by program parameter -M.
	*)
  releaseNo: integer = 59;
	(* This variable can be used to control program behavior and thus
	   facilitate compilation of older releases of the Interrupt List.
	   Currently it is used to:
	   1: Inhibit table as separate topics and table cross references if
	     releaseNo<41.
	   2: Compile wite 4 digit table entries rather than 5 if releaseNo<59.
	   Controlled by program parameter -R.
	*)
  scrollIndexTitle: boolean = true;
	(* Windows have a non-scroll area with the window title. Index
	   windows have an initial title part describing List release
	   number and help file compile date (inserted by specifying
	   "specialClassification" in the call to procedure "NewHlpPage").
	   If "scrollIndexTitle" is true, only the general part of the
	   title is in the non-scroll region, thus opening more space for
	   the scrolling part. If the flag is false, the whole title field
	   is made non-scrolable.
	   Controlled by program parameter -S.
	*)
  tableWindow: boolean = true;
	(* If true, tables activated from a "#nnnn" hotspot appear in a
	   secondary window, if fase, in the main window.
	   Controlled by program parameter -T.
	*)
  expandedIndex: boolean = true;
	(* controls whether the Interrupt Index initialy pops up in expanded
	   or compressed format.
	   Controlled by program parameter -X.
	*)
  longKeys: boolean = true;
	(* disables the long form of interrupt search keys if false (e.g.
	   disables "INT 03 AH = 09" so only the short form "03 09" is
	   available).
	   Controlled by program parameter -L.
	*)
  tableKWT: char = 'K';
	(* default keyword table for table (#nnnn) keywords, thus using the
	   standard keyword table. Can be set to 'T' to conserve space in the
	   standard table.
	   Controlled by program parameter K with argument T.
	*)

(* Help windows topic titles and identifiers: *)
	(* The following text describes windows titles as defined by the "$"
	   footnotes and topic identifiers (context strings) as defined by
	   the "#" footnotes. The identifiers can be used to open the List
	   at a given position by an external call to WINHELP.

window title		identifier	text

Contents:		CONTENTS	Main index.
Interrupt Index		idIndex		Total list, only if "twoIndexes" is true.
Interrupts	        idInterrupts	Main interrupt index.
INT NN List		nn_0		Index for INT NN, nn are two hex digits.
INT NN AHAL - <header>	nn_1		First entry about INT NN, the following
					entries have consecutive identifiers
					... nn_9, nn_10, ... . Aliases for
					Interrupt List topics can be compiled
					and written to the Help Project file.
					These aliases can be used to identify
					any (unique) topic.
Tables			idTables	Table index.
NN AHAL <table title>	tnnnn		Table No. nnnn, nnnn are the four
					decimal digits from the List. Aliases
					can be compiled based on table position
					and title.
					NN and AHAL in the title are the
					interrupt number and the register
					contents (sub function) where the table
					is defined.
FILELIST		1		The initial part of the Interrrupt List.
<notes>			n		Other notes have consecutive numbers as
					identifiers.
INTERRUP.1ST File	id1st		INTERRUP.1ST file window.
none			idPartComp	Partial compilation popup window if
					parameter -f<name>.
Filter Method		idFlt_meth	Filter Method if parameter -f<name>.
Filter File		idFlt_file	Filter File if parameter -f<name>.
Credits			idCredits	The Credits window.
none		Compressed_Index	This identifier is used as a marker.
#Table Search		idTableSearch	If option -K:T+ is used.
Table Search Details	idTableDetails	Ditto.

The identifiers mentioned above are reserved for program use. Titles and
identifiers for other windows are defined in the configuration file.

The program maintains 6 browse chains, as defined by the "+" footnotes:

The "main" chain:
	m:1	the Credits window.
	m:2	the Contents window.
	m:3	the Interrupt Index window provided "twoIndexes" is true.
	m:4	the Interrupts window.
	m:5	the Tables window provided "releaseNo" >= 41.
	m:9	index windows included as window type 2.

The "list" chain:
	l:0	the interrupt list sub index windows.

The "interrupt" chain:
	i:0	the interrupt windows.

The "file" chain:
	f:0	files included by the program or as window type 1.

The "table" chain:
	t:0	the table windows provided "releaseNo" >= 41.

The "ports" chain:
	p:0	the sub windows compiled from window type 2 inclusion.

The "table search" chain:
	ts:1, 2	the two table search help windows (option -KT only).

Window type 3 inclusions can link onto these chains or maintain their own
chains under user control.

*)

(* Constants defining windows setup etc.
   All the typed constants can be changed by the configuration file, and
   some of them also by program parameters.
*)

(* definitions for the *.HPJ file: *)
	windowsTitle =     '"Ralf Brown''s Interrupt List"';
	secWindowsTitle =  '"Interrupt List Tables"';
	secWindow = 'ITW'; (* the name of the secondary window *)
	mainW: string[5] = '>main'; (* or '' *)
	tableW: string[((length(secWindow)+3) AND $FE) - 1] = '>'+secWindow;
	windowsPosSize: string[21]   =   '';
	  (* or: '(xpos,ypos,width,heigth)' *)
	secWindowsPosSize: string[21] =  '(43,0,980,1023)';
	  (* values must be defined for a secondary window *)
	windowsMaximized = '0';      (* '0': no; '1': yes (overrides size) *)
	windowsBackgr: string[19]    = ''; (* or: '(red,green,blue)' *)
	windowsHdrBackgr: string[19] = ''; (* or: '(red,green,blue)' *)

(* definitions for fonts, attributes, and size: *)
	headerFont: string[31]       = 'roman Times New Roman';
	  (* or 'swiss Arial' *)
	textFont: string[31]         = 'modern Courier New';
	deciPoints: word             = 90;
	  (* 10 times point size *)
	headerDeciPoints: word       = 140;
	header2ndDeciPoints: word    = 120;
	headerAttrib =     '';       (*
	    \b   = bold
	    \i   = italics
	  *)
	highlightInt =     '';       (* this attribute highlights specificly
				       the "INT nn" part of the header *)
	indent =           '1060';   (* left indent of header after line one *)
	  (* (in twips, twentieth of a point, 1/1440 of an inch) *)
	dateSep =  '-';        (* for compile time YYYY-MM-DD string *)
	timeSep =  ':';        (* for compile time H:MM string *)
	(*.$define m_dd_yy *)  (* defines date format, default is yyyy-mm-dd *)
	(*.$define d_mm_yy *)  (* defines date format if m_dd_yy is undefined *)
	(*.$define yy_mm_dd *) (* defines date format to yy-mm-dd instead of
				  yyyy-mm-dd if both m_dd_yy and d_mm_yy
				  are undefined *)

  Var
      ProcessTime    : Longint;
      IndexFile      : Text;                    { stores one entry per int-number }
      IntFile        : Text;                    { stores *all* section names }
	{ the function of these two files was reversed in version 1.15 }
      SubIntFile     : Text;                    { stores all subfunctions of an int per page }
      TableFile      : Text;                    { stores tables references (index) }
      IntTopics      : Text;
      TabTopics      : Text;
      HPJ            : Text;                    { hlep compiler project file }
      indexHeader    : string;                  { index and subindex header string }
      compilationStr : string[159];             { compilation information }
      TopicStr   : String[15];			{ used in CheckKeyWords and ProcessList }
      indexPages,indexRows: integer;
      dateString: string[19];
      fontSize, headerSize, header2ndSize: string[7];
      aliasP,tableAliasP: stringListPtr;
	(* aliases read from configuration file *)
      aliasId,tableAliasId: string[19];
      aliasString,tableAliasString: aliasStringType;
      nextAliasPP: stringListPtrPtr;
	(* stored aliases, to be written to the HPJ file *)
      INTcounts: array[byte] of word;
      currentDir,homeDir: dirStr;
      currentTable: string[7];
      lineCount  : word; (* for error report *)
      tabArray: tableArray; (* tables found in current interrupt *)
      refArray: tableArray; (* tables referenced in current interrupt *)

  Const
    (* classification characters < '!' do not insert a classification string as
       a keyword.
    *)
    InvalidClassification = '-'; (* don't insert classification string as keyword *)
    nullClassification = #0;     (* no title as keyword *)
    specialClassification = #1;  (* use indexHeader in header *)
    tableClassification = #2;    (* insert '#' + currentTable as keyword *)
    titleOnlyClassification = #3; (* onsert only the title as keyword *)

function readKeyWd: word;
(* Calls BIOS to read the keyboard, returns scan code in hi and char. in lo *)
  inline($B4/$00/ {mov ah,0}  $CD/$16 {int $16});

procedure wl(s: string);
(* a substitute for single-string "writeln" to screen (or "output") (saves
   20 bytes of code per call).
*)
  begin writeln(s) end;

procedure errorExit(msg: string; err: byte);
(* prints "msg" to screen and halts with errorlevel "err" *)
  begin wl(msg); halt(err); end;

function exist(filename: pathStr): boolean;
(* check the existance of "filename" *)
  var b: boolean; t: text;
  begin
(*$I-*)
    assign(t,filename);
    reset(t);
    b:=IOresult=0;
    if b then close(t);
    exist:=b;
(*$I+*)
  end; (* function exist *)

procedure defaultDir(var fileName: pathStr; var default: dirStr);
(* if fileName has no drive, root, or current specification, then insert the
   default directory.
*)
  begin
    if (fileName[2]<>':') AND (fileName[1]<>'\') AND (fileName[1]<>'.') then
      insert(default,filename,1);
    fileName:=fExpand(fileName);
  end; (* procedure defaultDir *)

(* Some of the following procedures are Windows getPrivateProfileXxx-like
   routines to search the configuration file. If INT2WHLP.CFG is not found
   in the current directory or in INT2WHLP.EXE's home directory, or if
   the section or entry is not found in the file, the "value" parameter is
   unchanged, otherwise the section/entry value is assigned to "value". A
   boolean value is considered false if it is 0, and true otherwise.
*)

function findProfile(var configFile: text; var section: dirStr): boolean;
(* opens INT2WHLP.CFG on configFile and reads up to the specified section.
   findProfile returns true if the configuration file was located, false
   otherwise. If eof(configFile) returns true after a successful call
   to findProfile this indicates that the section was not found, or it was
   empty and last.
*)
  var i,l: integer; s: string;
  begin
(*$I-*)
    findProfile:=false; (* suggest configuration file absent *)
    if exist(progName+'.CFG') then assign(configFile,progName+'.CFG')
    else assign(configFile,homeDir+progName+'.CFG');
    reset(configFile);
    if IOresult<>0 then exit;
    findProfile:=true;
    i:=1;
    l:=length(section);
    if l=0 then exit; (* we will interpret section='' as "open only" *)
    while (i<=l) AND NOT eof(configFile) do begin
      readln(configFile,s);
      i:=1;
      if (length(s)>=l+2) AND (s[1]='[') AND (s[l+2]=']') then
	while (i<=l) AND (upcase(section[i])=upcase(s[succ(i)])) do inc(i);
    end; (* while i<=l ... *)
(*$I+*)
  end; (* procedure findProfile *)

procedure profileList(section: dirStr; var listP: stringListPtr);
(* reads all the entries in the specified section to a linked list and
   assigns the beginning of the list to listP. Empty lines and lines
   starting with a semicolon (;) are ignored.
*)
  label done,doneNC;
  var listPP: ^stringListPtr; s: string; configFile: text;
  begin
    listPP:=@listP;
    if NOT findProfile(configFile,section) then goto doneNC;
      (* no configuration file *)
    while NOT eof(configFile) do begin
      readln(configFile,s);
      if (s<>'') AND (s[1]<>';') then begin
	if s[1]='[' then goto done;
	getMem(listPP^,length(s)+1+sizeOf(pointer));
	listPP^^.s:=s;
	listPP:=@listPP^^.next;
      end; (* if (s<>'')... *)
    end; (* while NOT eof() *)
  done:
    close(configFile);
  doneNC:
    listPP^:=NIL;
  end; (* procedure profileList *)

procedure freeStringRec(var p: stringListPtr);
(* updates p to point to the next record, and frees the current one *)
  var p1: stringListPtr;
  begin
    if p=NIL then exit;
    p1:=p;
    p:=p1^.next;
    freeMem(p1,length(p1^.s)+1+sizeOf(pointer));
  end; (* procedure freeStringRec *)

procedure profileString(section, entry: dirStr; var value: string;
  bufferLen: integer);
  label done;
  var i,l: integer; s: string; configFile: text;
  begin
(*$I-*)
    if (section='') OR (entry='') then exit;
    if NOT findProfile(configFile,section) then exit;
      (* no configuration file *)
    i:=1;
    l:=length(entry);
    while (i<=l) AND NOT eof(configFile) do begin
      readln(configFile,s);
      if (s<>'') AND (s[1]='[') then goto done;
      i:=1;
      if (length(s)>l) AND (s[succ(l)]='=') then
	while (i<=l) AND (upcase(entry[i])=upcase(s[i])) do inc(i);
    end; (* while i<=l ... *)
    if i>l then value:=copy(s,succ(i),bufferLen);
  done:
    close(configFile);
(*$I+*)
  end; (* procedure profileString *)

procedure profileInt(section, entry: dirStr; var value: integer);
  var i,j: integer; s: string[19];
  begin
    s:='';
    profileString(section,entry,s,pred(sizeOf(s)));
    if s='' then exit;
    val(s,i,j);
    if j=0 then value:=i;
  end; (* procedure profileInt *)

procedure profileBoolean(section, entry: dirStr; var value: boolean);
  var i: integer;
  begin
    i:=ord(value);
    profileInt(section,entry,i);
    value:=i<>0;
  end; (* procedure profileBoolean *)

procedure scan(line: string; var spa: categoryStringPtrArr);
(* scans lines with format "xxx a - definition a, A - definition A" and
   allocates memory and stores the definitions at appropriate index in spa.
*)
  var
    p: integer;
    c: char;
    ok: boolean;
  begin
    repeat
      p:=pos(' - ',line);
      if p=0 then exit;
      if p>1 then c:=line[p-1];
      ok:=((p=2) OR ((p>2) AND (line[p-2]<=' '))) AND (c>' ') AND (c<#127);
      delete(line,1,p+2);
      if ok then begin
	p:=pos(' - ',line);
	if p=0 then p:=length(line)+1 else dec(p,2);
	while line[p-1]<=' ' do dec(p);
	if line[p-1]=',' then dec(p);
	getmem(spa[c],p);
	spa[c]^:=copy(line,1,p-1);
	delete(line,1,p);
      end; (* if ok *)
    until false; (* terminated by exit *)
  end; (* procedure scan *)

procedure check1st(var s: string);
(* scans s for the occurence of 'INTERRUP.1ST' and inserts xref to id1st.
   Letter case is ignored.
*)
  var p: byte; s1: string[119];
  begin
    s1[0]:=s[0];
    for p:=1 to length(s) do s1[p]:=upcase(s[p]);
    p:=pos('INTERRUP.1ST',s1);
    if p<>0 then begin
      insert('}{\v id1st}',s,p+12);
      insert('{\uldb ',s,p);
    end; (* if p<>0 *)
  end; (* procedure check1st *)

procedure getINTtitle(var line: string; var titles: titleStringPtrArr);
(* allocates memory and copies a line starting with "INT nn " to titles[nn]^ *)
  type (* for type casts *)
    lineRec = record l: byte; INT: longint; nn: word; spc: char; end;
    hexRec = record l: byte; dollar: char; nn: word; end;
  const
    intC = ord('I')+ord('N')*$100+ord('T')*$10000+ord(' ')*$1000000;
    intNumber: string[3] = '$nn'; (* preset length to 3 and [1] to '$' *)
  var
    lineR: lineRec absolute line; (* for typecast *)
    intR: hexRec absolute intNumber; (* for typecast *)
    n,j: integer;
  begin
    if (length(line)<8) OR (lineR.spc<>' ') OR (lineR.INT<>intC) then exit;
    intR.nn:=lineR.nn; (* two characters typecasted to a word *)
    val(intNumber,n,j);
    if j<>0 then exit;
    getmem(titles[n],succ(length(line)));
    titles[n]^:=line;
  end; (* procedure getINTtitle *)

procedure getNextAlias(var aliasP: stringListPtr;
   var aliasId, aliasString: string);
(* extract an alias string from the heap and free the heap memory *)
  var n: integer;
  begin
    aliasString:='';
    if aliasP=NIL then exit;
    aliasString:=aliasP^.s;
    freeStringRec(aliasP); (* free memory and update aliasP *)
    n:=pos('=',aliasString);
    if n<2 then errorExit('Missing alias Id in '+aliasString,aliasErr);
    if n>pred(sizeOf(aliasId)) then errorExit('Alias Id too long in '
      +aliasString,aliasErr);
    aliasId:=copy(aliasString,1,n);
    delete(aliasString,1,n);
  end; (* procedure getNextAlias *)

procedure saveAlias(var aPP: stringListPtrPtr; s: dirStr);
(* allocates memory on the heap, stores information, and updates aPP *)
  begin
    getmem(aPP^,length(s)+1+sizeOf(pointer));
    aPP^^.next:=NIL;
    aPP^^.s:=s;
    aPP:=@aPP^^.next
  end; (* procedure saveAlias *)

procedure processAliasList(aP: stringListPtr);
  begin
    while aP<>NIL do begin
      writeln(HPJ,aP^.s);
      aP:=aP^.next;
    end; (* while aP<>NIL *)
  end; (* procedure processAliasList *)

procedure setTabs(var f: text; spaces, deciPoints, tabs: word);
(* writes tab settings to file f, tabspacing approximately "spaces" character
   columns width New Courier font with size 1/10*"deciPoints". Number of tab
   settings = "tabs".
   The tabs are valid until the next "\pard".
*)
  var i: integer; s: string[11];
  begin
    for i:=1 to tabs do begin
      str(longint(i*spaces*deciPoints)*1170 DIV 1000,s);
      (* tab spacing = (point size)*(column width)*11.70 *)
	(* at least, this seems to fit pretty well *)
      write(f,'\tx',s);
    end; (* for i:=1 *)
    writeln(f);
  end; (* procedure setTabs *)

procedure writeIndex(s: string);
  begin writeln(indexFile, s); end;

  procedure CreateHPJ;
    var i,n: integer; bP: stringListPtr; s: pathStr;
    begin
      assign(HPJ, OutPath + hfName+'.HPJ');
      rewrite(HPJ);
      n:=0;
      profileList('BUILDTAGS',bP);
      if bP<>NIL then begin (* write [BuildTags] section *)
	writeln(HPJ,'[BUILDTAGS]');
	while bP<>NIL do begin
	  writeln(HPJ,bP^.s);
	  freeStringRec(bP); (* free memory and update bP *)
	end; (* while bP<>NIL *)
	writeln(HPJ);
      end; (* if i>0 *)
      profileList('BAGGAGE',bP);
      if bP<>NIL then begin (* write [Baggage] section *)
	writeln(HPJ,'[BAGGAGE]');
	while bP<>NIL do begin
	  writeln(HPJ,bP^.s);
	  freeStringRec(bP); (* free memory and update bP *)
	end; (* while bP<>NIL *)
	writeln(HPJ);
      end; (* if i>0 *)
      s:=fExpand(OutPath);
      if length(s)>3 then dec(s[0]); (* delete terminating '\' if not root *)
      writeln(HPJ, '[OPTIONS]'#13#10'CONTENTS=CONTENTS'#13#10'COMPRESS=',compression);
      writeln(HPJ,'REPORT=ON'#13#10'WARNING=2'#13#10'ROOT=',s);
	(* warning=2 avoids the "Using old *.ph file" warning *)
      if errorLog then writeln(HPJ,'ERRORLOG='+hfName+'.ERR');
      if buildExpr<>'' then writeln(HPJ,'BUILD=',buildExpr);
      writeln(HPJ, 'CITATION=Copied from Ralf Brown''s Interrupt List');
      writeln(HPJ, 'COPYRIGHT='+hfName+' Layout: Christian MÅller-Planitz');
      s:='interrup.ico';
      if NOT exist (s) then s:=HomeDir+'interrup.ico';
      if NOT exist (s) then s:=InPath+'interrup.ico';
      if exist(s) then writeln(HPJ, 'ICON=',s);
      s:='';
      if tableKWT<>'K' then s:=s+tableKWT;
	(* the only one supported so far *)
      if s<>'' then writeln(HPJ, 'MULTIKEY=',s);
      writeln(HPJ, #13#10'[CONFIG]'#13#10'CreateButton(`id_print'',`&Print'',`Print()'')');
      writeln(HPJ, 'CreateButton(`id_copy'',`C&opy'',`CopyTopic()'')'#13#10'BrowseButtons()');
      writeln(HPJ, 'CreateButton(`id_exit'',`E&xit'',`Exit()'')');
      if tableKWT<>'K' then
	writeln(HPJ,'RR(`seckey.dll'',  `SearchSecondaryKey'',`ISISSSS'')');
      if twoindexes AND NOT expandedIndex then
	writeln(HPJ, 'SaveMark(`Compressed_Index'')');
      profileList('INTWINCONFIG',bP);
      while bP<>NIL do begin (* copy [INTWINCONFIG] entries *)
	writeln(HPJ,bP^.s);
	freeStringRec(bP); (* free memory and update bP *)
      end; (* while bP<>NIL *)
      writeln(HPJ, #13#10'[WINDOWS]'#13#10'main='+windowsTitle+',',windowsPosSize,
	','+windowsMaximized+',',windowsBackgr,',',windowsHdrBackgr);
      if tableWindow then writeln(HPJ, secWindow+'='+secWindowsTitle+',',
	secWindowsPosSize,','+windowsMaximized+',',windowsBackgr,',',
	windowsHdrBackgr);
      writeln(HPJ, #13#10'[FILES]');
    end;

  Procedure OpenRTF(VAR F: Text; Name: String);
    begin
     {$I-}
      assign(F, OutPath + Name);
      rewrite(F);
     {$I+}
      if IOResult <> 0 then errorExit('Error craeting '+OutPath+Name,rtfErr);

      writeln(HPJ, Name);

      writeln(F, '{\rtf1\pc \deff1{\fonttbl{\f0\f',headerFont,';}');
      writeln(F, '{\f1\f',textFont,';}}');
      writeln(F, '{\colortbl \red255\green0\blue0;\red0\green0\blue0;');
      writeln(F, '\red0\green0\blue255;\red255\green255\blue255;}');
      writeln(F, '\plain',fontSize,'\pard\keep');
      TextRec(F).UserData[1]:=ord(false); (* mark as unused *)
    end;


  Procedure CloseRTF(VAR F: Text);
    begin
      writeln(F, '}');
      close(F);
    end;

  Procedure PageRTF(VAR F: Text);
    begin
      if boolean(TextRec(F).UserData[1]) then write(F, '\page')
      else TextRec(F).UserData[1]:=ord(true);
    end;

  Function HEX(b:byte):string;
    Const h : array [0..15] of char = ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');
    begin
      Hex[0]:=#2; Hex[1]:=h[b shr 4]; Hex[2]:=h[b and 15];
    end;


  Procedure ReadLine(VAR F: Text; VAR S: String);
    VAR q: Word;

    begin
      readln(F, S);
      q:= 1;
      while q <= Length(s) do    { duplicate all '\' etc. }
	begin
	  case s[q] of
	    '\', '{', '}': begin insert('\', s, q); inc(q); end;
    (* v. 1.13: DOS framing characters are not transformed properly by
       selecting the "pc" character set. We will transform single and double
       horizontal frames to '-', vertical frames to '|', and all other
       framing characters to '+'. Please note that some codepage 850 extended
       characters are also transformed to '+'.
    *)
	    #196, #205: s[q]:='-';
	    #179, #186: s[q]:='|';
	    #176..#223: s[q]:='+';
	    #128..#255: begin
	      insert(#39+HEX(ord(s[q])), s, q+1);
	      s[q] := '\';
	      Inc(q,3);
	    end; (* case #128..#255 *)
	  end; (* case s[q] of *)
	  if q>=255 then begin
	    writeln('Too many graphic characters in line ', lineCount);
	    ErrorExit('Please edit the file and try again', formatErr);
	  end; (* if q>255 *)
	  Inc(q);
	end; (* while q>=length(s) *)

    end;



  Procedure OutLN(VAR F: Text; S : String);
    begin
      writeln(F, '\par ', S);
    end;


  Procedure Intro;
    begin
      wl(#10'Interrupt List-WinHelp preprocessor '+progname+' version '+progvers);
      wl(copyright);
      wl(e_mail+#13#10);
      wl('Use "'+progname+' ?" for help.'#13#10);
    end;

  Procedure Explain;
    begin
      wl('This program converts the Interrupt List written by Ralf Brown to a RTF-Format');
      wl('that is used as an input format by the Microsoft WinHelp compiler.'#10);

      wl('In order to generate a Windows 3.1 helpfile you need the WinHelp compiler');
      wl('"HC31.EXE", which is distributed with almost all Windows compilers and which');
      wl('is also available on many Internet sites and FIDO BBS systems.'#10);

      wl('Please note that you also need a fast computer and a *lot* of free space on');
      wl('your harddrive, see the file I2W-HINT.TXT. If you want to find out whether you');
      wl('are able to compile a RTF file, I recommend that you experiment with the files');
      wl('in the I2W-TEST.ZIP subpackage.'#10);

      wl('After this program finishes, you have to invoke the WinHelp compiler with');
      writeln('the command "HC31 ',hfName,'.HPJ".'#10);

      wl('For more information about '+progName+' program options and configuration file,');
      wl('read the I2W-OPT.TXT and I2W-CFG.TXT files.'#10);

      wl('Have fun ! --CMP'#10);

      wl('P.S. If you have problems building the helpfile or if you simply want to write');
      wl('     an e-mail to me, please write to:');
      wl('     '+e_mail);
      halt(0);
    end;

procedure initializeArrays;
  var i: integer; ch: char;
  begin
    for ch:='!' to #126 do begin (* default to empty string *)
      flagStrings[ch]:=@emptyString;
      categoryStrings[ch]:=@emptyString;
      categoryKeyStrings[ch]:=@emptyString;
    end; (* for ch:='!' *)
    categoryStrings['!']:=@noteString;
    categoryStrings['-']:=@noneString;
    for i:=$00 to $FF do begin INTcounts[i]:=0; INTtitles[i]:=@emptyString; end;
  end; (* procedure initializeArrays *)

procedure findDateAndCopyright;
  var a,b,c,d: word; s,ss: string[99]; t: text;
  begin
    getDate(a,b,c,d);
    (*$ifdef m_dd_yy *)
      str(b*1000000+(c*1000+a MOD 100),dateString);
      dateString[length(dateString)-5]:=dateSep;
      dateString[length(dateString)-2]:=dateSep;
    (*$else*)
      (*$ifdef d_mm_yy *)
	str(c*1000000+(b*1000+a MOD 100),dateString);
	dateString[length(dateString)-5]:=dateSep;
	dateString[length(dateString)-2]:=dateSep;
      (*$else*)
	str(a*1000000+(b*1000+c),dateString);
	dateString[5]:=dateSep;
	dateString[8]:=dateSep;
	(*$ifdef yy_mm_dd *) delete(dateString,1,2); (*$endif*)
      (*$endif*)
    (*$endif*)
    getTime(a,b,c,d);
    str((a*1000+b)+100000,s);
    s[4]:=timeSep;
    s[1]:=' ';
    if a<10 then delete(s,2,1);
    dateString:=dateString+' -'+s;
  (*$I-*)
    assign(t,InPath+'interrup.lst');
    reset(t);
    if IOresult<>0 then begin
      assign(t,InPath+'interrup.a');
      reset(t);
      if IOresult<>0 then
	errorExit('Unable to open INTERRUP file in directory '+InPath,fileErr);
    end; (* if IOresult<>0 *)
  (*$I+*)
    ReadLine(t,s);
    ReadLine(t,ss);
    close(t);
    for a:=1 to 2 do begin
      b:=pos(#9,s); (* remove two wide areas of whitespace *)
      if b<>0 then while s[b]=#9 do delete(s,b,1)
      else begin
	b:=pos('        ',s);
	if b<>0 then while s[b]=' ' do delete(s,b,1)
      end; (* else *)
      if b<>0 then insert('      ',s,b); (* insert 6 spaces instead *)
    end; (* for a:=1 *)
    indexHeader:='{\keep '+s+#13#10'\par{'+header2ndSize+' '+ss+'}'#13#10'\par';
    if scrollIndexTitle then indexHeader:=indexHeader+'\pard';
    indexHeader:=indexHeader+#13#10'\par}';
    compilationStr:=progName+' v. '+progVers+' compilation.'#13#10'\par '
      +hfName+'.HLP compiled '+dateString+'.';
    if filtered then compilationStr:=compilationStr
      +' {\ul Partial compilation.}{\v idPartComp}';
  end; (* procedure findDateAndCopyright *)

procedure interpretParameters;
(* interprets program parameters and parts of the configuration file *)
  var i,argVal: integer; s: string[79]; blanks: boolean;
  function argStart: integer;
    begin if (s[3]=':') OR (s[3]='=') then argStart:=4 else argStart:=3; end;
  procedure copyParam(var dest: string; len: byte);
    begin dest:=copy(s,argStart,len); end;
  procedure getArgVal;
    (* assigns value of argument, or $8000, to argVal *)
    var i: integer; st: string[9];
    begin
      copyParam(st,9);
      val(st,argVal,i);
      if i<>0 then argVal:=integer($8000);
    end; (* procedure getArgVal in interpretParameters *)
  function getBool: boolean;
    begin getBool:=(length(s)<3) OR (s[3]<>'-'); end;
  procedure setSize(var fs: string; dp: word);
    (* converts decipoints to an RTF halfpoint font size string *)
    begin
      str(dp DIV 5,fs);
      insert('\fs',fs,1);
    end; (* procedure setSize in interpretParameters *)
  procedure keywordTable(n: integer);
    (* handles keyword table parameters *)
    var c: char; b: boolean;
    begin
      while n<=length(s) do begin
	c:=s[n+1];
	b:=(n<length(s)) AND (c='-');
	case upcase(s[n]) of
	  'T': if b then tableKWT:='K' else tableKWT:='T';
	  (* currently only T is used *)
          else errorExit('Unknown argument "'+s[n]+'" in option '+s,paramErr);
	end; (* case upcase(s[i] of *)
	case c of '-','+': inc(n); end;
	inc(n);
      end; (* while i<length(s)*)
    end; (* procedure keywordTable in interpretParameters *)

  begin
    blanks:=true;
    (* first, check configuration file *)
    profileString('OPTIONS','build',buildExpr,pred(sizeOf(buildExpr)));
    profileString('OPTIONS','compression',compression,pred(sizeOf(compression)));
    profileString('OPTIONS','filterFile',filterFileName,pred(sizeOf(filterFileName)));
    profileBoolean('OPTIONS','singlesInMain',singlesInMain);
    profileBoolean('OPTIONS','twoIndexes',twoIndexes);
    profileBoolean('OPTIONS','errorLog',errorLog);
    profileBoolean('OPTIONS','indexHeaders',indexHeaders);
    profileInt('OPTIONS','indexColumns',indexColumns);
    profileBoolean('OPTIONS','markKeys',markKeys);
    profileBoolean('OPTIONS','equalBlanks',blanks);
    profileInt('OPTIONS','releaseNo',releaseNo);
    profileBoolean('OPTIONS','scrollIndexTitle',scrollIndexTitle);
    profileBoolean('OPTIONS','tableWindow',tableWindow);
    profileBoolean('OPTIONS','expandedIndex',expandedIndex);
    profileBoolean('OPTIONS','longKeys',longKeys);
    s:='';
    profileString('OPTIONS','keywordTable',s,pred(sizeOf(s)));
    keywordTable(1);
    (* second, check parameters *)
    for i:=1 to paramCount do begin
      s:=paramStr(i);
      case s[1] of
	'/','-': begin
	  if length(s)=1 then errorExit(
	    'Missing option after "'+s+'"',paramErr);
	  case upcase(s[2]) of
	    'B': copyParam(buildExpr,pred(sizeOf(buildExpr)));
		(* legal: any .HPJ [OPTIONS] build= expression *)
	    'C': begin
	      copyParam(compression,pred(sizeOf(compression)));
		(* legal: 0, 1, no, yes, low, medium, high. Not checked *)
	      if compression='' then compression:='YES';
		(* default if "-c" or "-c:" is specified *)
	    end; (* case 'C' *)
	    'F': begin
	      copyParam(filterFileName,pred(sizeOf(filterFileName)));
	      if filterFileName='' then errorExit(
		'No filter file name specified after "'+s+'"',fileErr);
	      filtered:=true;
	    end; (* case 'F' *)
	    '1': singlesInMain:=getBool;
	    '2': twoIndexes:=getBool;
	    'E': errorLog:=getBool;
	    'H': indexHeaders:=getBool;
	    'I': begin getArgVal; indexColumns:=argVal; end;
	    'K': keywordTable(argStart);
	    'L': longKeys:=getBool;
	    'M': markKeys:=getBool;
	    'Q': blanks:=getBool;
	    'R': begin getArgVal; releaseNo:=argVal; end;
	    'S': scrollIndexTitle:=getBool;
	    'T': tableWindow:=getBool;
	    'X': expandedIndex:=getBool;
	    else
	  end; (* case upcase(s[2] of *)
	end; (* case '/','-' *)
	else begin
	  if InPath='' then InPath:=s
	  else if OutPath='' then OutPath:=s
	  else errorExit('Too many parameters: '+s,paramErr);
	end; (* case else *)
      end; (* case s[1] of *)
    end; (* for i:=1 *)
    (* if file paths were not program parameters, try configuration file *)
    if InPath='' then profileString('FILES','InPath',InPath,pred(sizeOf(InPath)));
    if OutPath='' then profileString('FILES','OutPath',OutPath,pred(sizeOf(OutPath)));
    (* read windows settings from configuration file *)
    profileString('CONFIG','pos and size',windowsPosSize,pred(sizeOf(windowsPosSize)));
    profileString('CONFIG','secondary pos and size',
      secWindowsPosSize,pred(sizeOf(secWindowsPosSize)));
    profileString('CONFIG','background',windowsBackgr,pred(sizeOf(windowsBackgr)));
    profileString('CONFIG','header background',windowsHdrBackgr,pred(sizeOf(windowsHdrBackgr)));
    profileString('CONFIG','header font',headerFont,pred(sizeOf(headerFont)));
    profileString('CONFIG','text font',textFont,pred(sizeOf(textFont)));
    profileInt('CONFIG','deciPoints',integer(deciPoints));
    profileInt('CONFIG','header deciPoints',integer(headerDeciPoints));
    profileInt('CONFIG','header 2nd deciPoints',integer(header2ndDeciPoints));
    (* update other values *)
    indexRows:=16; (* in most cases *)
    indexPages:=1; (* in two cases *)
    case indexColumns of
      1: indexRows:=256;
      4: indexPages:=4;
      8: indexPages:=2;
      16: ; (* already ok *)
      else errorExit('Illegal index columns, only 1, 4, 8, or 16 accepted',
	paramErr);
    end; (* case indexColumns of *)
    if NOT blanks then begin
      equStr[4]:='=';
      equStr[0]:=#4; (* equStr = ' Ax=' *)
      equStr2[1]:='=';
      equStr2[0]:=#1; (* equStr2 = '=' *)
      equBlanks:=0;
    end; (* if NOT blanks *)
    setSize(fontSize,deciPoints);
    setSize(headerSize,headerDeciPoints);
    setSize(header2ndSize,header2ndDeciPoints);
    filtered:=filterFileName<>'';
    if NOT indexHeaders then indentIndex:=nl;
    if releaseNo<59 then tableDigits:=4;
    if releaseNo<41 then begin tables:=false; tableWindow:=false; end;
    if NOT tableWindow then begin mainW:=''; tableW:=''; end;
  end; (* procedure interpretParameters *)

