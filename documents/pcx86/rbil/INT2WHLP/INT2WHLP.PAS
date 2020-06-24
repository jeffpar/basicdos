(*
  Interrupt List -> WinHelp converter (c) 1994 by Christian MÅller-Planitz
  ------------------------------------------------------------------------
  e-mail address: see CONST "e_mail"


  The source and the compiled EXE-file can be freely distributed as long as
  no changes are made without my knowledge.

  --------------------------------
  Notes:
   The program was tested with INTLIST38 and INTLIST39 and its output
     was successfully compiled with the MS-Help-compiler "HC31.EXE" V3.10.445.

   The program needs the file "INTWHLP.DAT" in the 'source' directory.

   The program converted all sourcefiles (INTERRUP.* and *.LST) to
     13 RTF files which needed 11MB on my harddrive.

   Compiling the RTF-files without compression took 13 minutes in
     a DOS-Window under Win/NT on a 486-50 (if you run it under DOS
     and if you have a fast hardrive cache, it might be faster).

   The (uncompressed) compiled HLP-File was approximately 7MB large.
   If you want to create a compressed HLP-file, you have to exchange the
     comments in the generated help-project file ("RB.HPJ"). Compressing
     reduces the size of the HLP-file to 3MB but it takes
     *more* (?? 28MB ??)  space on your harddrive while compiling.
     In order to speed up compiling the compressed file, I've included a
     temporary file ("INTWIN.PH") of the helpcompiler in this archive.
     Copy this file into the directory containing all the RTF files
     before starting the compiler. This file is specific for INTERLIST39, so
     if you want to get maximal compression in future versions, remove it.

   After the compilation finishes, you will find the file "INTWIN.HLP".
     Start Windows, create an icon in the program manager and double-click on it.

   Version 1.11:
   The compressed INTWIN.HLP file compiled from Ralf Brown's Interrupt List
     release 42 occupies appr. 4.6 MB.

  --------------------------------

   If you find this program usefull, if it does not work or if you have ideas
   how to expand its functionality, feel fee to write an e-mail to me.

   As usual, I do not take any responsibility for possible damages done by
   this program.


  Two questions and their answers :
  ---------------------------------
   WHY is the HLP-file so large ?
     In contrast to other programs that convert the interrupt list to
     DOS-based hypertext systems, this program generates a large
     index file that allows you to search for keywords.

   WHY did I wrote this program in Pascal and not in C ?
     I think Pascal is a pretty nice language for small projects.
     Another reason is the availability of efficient string handling under Pascal.
*)

{$A+,B-,D+,E-,F-,I+,L+,N-,O-,R-,S-,V-}
{$M 16384,25000,200000}
(* minimum heap estimate (1994): 60*(6+10)+(30+40)*(43+10)+50*256=16770 *)
(* (average entry size times (number of entries + 10) for FLAGS, CATEGORIES,
   and CATEGORYKEYS entries) or times 256 for titles.
   Each string in the [*ALIASES] sections requires (length of string) + 5.
*)

Program INT2WHLP;

uses DOS;

{ Version 1.00 - 1994
  v. 1.01 -
  v. 1.01a - 1994-02-16:
	published with Ralf Brown's Interrupt List release 40.
  v. 1.02 - 1994-04-07:
	Changed program name from RB2HLP/INTWHLP to INT2WHLP.
	Reduced the amount of RTF control codes.
	Introduced program parameter controlled behaviour.
	Improved flexibility by use of constants for parts of the control.
	Changed and added some windows.
	Extended search key facilities.
  v. 1.03 - 1994-04-17:
	Expanded/Compressed index switch.
	Multi columns compressed index.
	Interrupt titles OVERVIEW.LST.
  v. 1.04 - 1994-04-29:
	Configuration file including:
	  Program parameters can be defined in the configuration file. Such
	    definitions are overriden by program parameters.
	  Several WINHELP parameters, like font and size, can be specified.
	  Supplementary information "windows" can be included.
	  An ALIAS list can be compiled and written to the HPJ file.
	  A BUILDTAG list can be copied from the configuration to the HPJ file.
  v. 1.05 - 1994-05-07:
	Reconsidered default directories.
  v. 1.06 - 1994-05-26:
	Cross-references to tables.
  v. 1.07 - 1994-05-29:
	Edited procedure explain.
	Skip "Section" file break sections (from a "--------!-Section--.."
	  divider line up to the next divider line).
	Executable code released with Interrupt List release 41.
	(ProgVers erroneously = '1.06').
  v. 1.08 - 1994-07-10:
	Tables as separate topics.
  v. 1.10 - 1994-07-20:
	Interrupt List release number dependent compilation.
	Published with Interrupt List release 42.
  v. 1.11 - 1994-09-20:
	[INTWINCONFIG] section in configuration file.
  v. 1.12 - 1994-11-04:
	Test for long graphics lines in ReadLine().
	Published with Interrupt List release 43.
  v. 1.13 - 1994-12-26:
	Transformation of DOS graphics in ReadLine().
	Check for duplicate keywords (from CATEGORYKEYS) in NewHlpPage().
	Secondary register references as keywords.
	Separate RTF files for interrupts and tables, check for direct/inderect
	  references to tables from current interrupt.
  v. 1.14 - 1995-03-07:
	Return errorlevel 1 for warnings and >= 2 for errors.
  v. 1.15 - 1995-05-29:
	Avoid empty topic in the beginning of .RTF files.
        Made more tools-tolerant: RTF files for expanded and compressed
        indexes reversed. It is easier for some tools to digest the very
        long expanded index when it is compiled at a later state so all its
        phrases are already known.
	[BAGGAGE] section handling.
	Expanded list of registered warnings.
	Copyright message and credits window include Bent Lynggaard as
	coauthor.
  v. 1.16 - 1995-07-31:
	Christian's new e-mail address.
  v. 1.17 - 1996-01-25:
	Fixed bug in NewHlpPage (bad search keys for AH = xx + secondary reg.).
        Switch to inhibit long search keys for INT topics (in order to support
        limited capacity in WinHelp 4.0).
  v. 1.18 - 1996-10-05:
	Shortcut from Credits topic to Interrup.1st Contact Info.
        Insert icon interrup.ico if it is available in current, INT2WHLP home,
        or source directory.
        intwin.ph no longer included in package, instead download interNNz.zip.
  v. 1.19 - 1997-07-01:
	Returns warning errorlevel if ProcessFile() fails.
	Fixed bug: failed to convert non-ASCII characters in table headers.
  v. 1.20 - 1997-12-15:
	Bug fix: Failed to print backward reference after file sectioning.
        Option -KT: Tabel search string in separate keyword table.
  v. 1.21 - 1998-03-01:
	Fixed two errors introduced in v. 1.20 bugfix: v. 1.20 terminated
        after file section break in concatenated interrup.lst file compilation,
        and it could scramble extended register information.
  v. 1.22 - 1998-11-22:
	5 digits in table numbers. The major part of this fix was written by
	Michael Hall <mjhall3@hotmail.com> - thank you.
	Default extension .LST or .A, .B, ... for type 2 supplementary files.
}

const
  progName  = 'INT2WHLP';
  progVers  = '1.22';
  hfName    = 'INTWIN'; { helpfile name }
  copyright = 'Copyright (C) 1994-1998 by Christian MÅller-Planitz and Bent Lynggaard';
  e_mail    = '"cmp@cs.utah.edu"';
    { e-mail address in Intro/Explain windows }
  e_mailCredits = '"cmp@cs.utah.edu"';
    { e-mail address in the Credits window }
  e_mailCredits2 = '"bent.lynggaard@risoe.dk"';
    { e-mail address in the Credits window, coauthor }

  { the strings ack01 ... are displayed in the Credits window }

  { thanks to (excuse the format): }
  ack01 = '\par{\b Michael Hall} "mjhall3@hotmail.com" for fix for 5 digits in table numbers';
(* The following line is a template for an entry:
  '\par{\b <name>} <reason for the entry>';
*)
  ack02 = '';
  ack03 = '';
  ack04 = '';
  ack05 = '';
  {if extended, update procedure "Credits"}

  {"errorlevel" constants:}
  aliasErr	= 241; (* alias not found, or table exceeded *)
  fileErr	= 242; (* cannot open file *)
  formatErr	= 243; (* table exceeded, or fatal error in input file *)
  paramErr	= 244; (* error in program parameter *)
  rtfErr	= 245; (* unable to open output file *)
  userErr	= 240; (* terminated by user *)

{$I INT2WHLP.INC }

  Procedure NewHlpPage(VAR F : Text; S, ID, BrowseID : String; Classification : Char);
    label
      deleteDone, insertKey;
    type
      intRec = record (* used for fast test and transfer of string *)
	ln: byte;    (* string length *)
	l: longint;  (* 'INT ' *)
	n: word;     (* 'nn' *)
	c7: char;    (* ' ' *)
	l2: longint; (* 'ahal' or 'List' *)
	c12: char;   (* ' ' *)
	w: word;     (* '- ' *)
      end; (* record intRec *)
      nnRec = record ln: byte; w: word; (* for 'nn' *) end;
      ahalRec = record ln: byte; l: longint; (* for 'ahal' *) end;
    const
      linebreak = #13#10'\par\tab';
      intC = ord('I')+ord('N')*$100+ord('T')*$10000+ord(' ')*$1000000;
      listC = ord('L')+ord('i')*$100+ord('s')*$10000+ord('t')*$1000000;
      sepC = ord('-')+ord(' ')*$100;
      int:  string[3] = 'nn';   (* preset length to 2, never changed *)
    VAR
      intR: nnRec absolute int; (* type cast *)
      p,q : Word;
      func: string[5];
      funcR: ahalRec absolute func; (* type cast *)
      ss: string;
      ssR: intRec absolute ss;

    Procedure FootNote(Note: Char; ID : String);
      begin
	writeln(F, '{', Note,'}{\footnote ',Note,' ', ID, '}');
      end;

    procedure insertInt;
      begin
	insert('INT '+int+equStr+func+';'+int+' '+func+';',ss,11);
	  (* "INT nn Ar = XXxx;nn XXxx;"  (XXxx = ahal, ah, or --al) *)
	if equStr[3]='L' then delete(ss,21+equBlanks,2);
	  (* "--" from AL = --al *)
	insert(copy(ss,18,6+equBlanks+2*ord(equStr[3]='X')),ss,11);
	  (* "Ar = XXxx;" *)
      end; (* procedure insertInt in NewHlpPage *)
    procedure insertSecReg(p, l: word);
    (* duplicates part of SS and inserts secondary register *)
      begin
	insert(copy(ss,p,l),ss,p); (* duplicate *)
	insert(secReg,ss,p+l+l-1); (* SXnnnn *)
	insert(secReg,ss,p+l+p-5);
	insert(equStr2,ss,p+l+p-2); (* SX = nnnn *)
	insert(copy(secReg,2,7)+';',ss,p);   (* SXnnnn; *)
	insert(equStr2,ss,p+2);    (* SX = nnnn; *)
      end; (* procedure insertSecReg in NewHlpPage *)

    begin
      PageRTF(F); (* insert '\page' if appropriate *)
      writeln(F, '\pard\keepn\li'+indent+'\fi-'+indent);
      FootNote('#', ID);
      if S<>'' then FootNote('$', S);
      if BrowseID<>'' then FootNote('+', BrowseID);
      if (Classification <> nullClassification) then begin
	ss:=s;
	if Classification=titleOnlyClassification then goto insertKey;
	if (ssR.l=intC) AND (ssR.c7=' ') then begin
	  if (length(ss)>14) AND (ssR.c12=' ') AND (ssR.w=sepC) then begin
	    (* insert highlight in s *)
	    insert('}}',s,7);
	    insert('{'+highlightInt+'{',s,1);
	      (* 2nd '{' terminates attribute, a ' ' distorts if attrib. is empty *)
	    (* insert tiny, short, and full form of INT *)
	    intR.w:=ssR.n;   (* length of "int" is preset to 2 *)
	    (* same as "int:=copy(ss,5,2);": nn from INT nn ahal - xxxx ... *)
	    funcR.l:=ssR.l2;
	    funcR.ln:=4;     (* func = 'ahal' *)
	    ss[7]:=';';      (* INT nn;ahal - xxxx ... *)
	    ss[8]:=int[1];
	    ss[9]:=int[2];
	    ss[10]:=';';     (* INT nn;nn;l - xxxx ... *)
	    delete(ss,11,4); (* INT nn;nn;xxxx ... *)
	    if func<>'----' then begin
	      if func[3]='-' then begin equStr[3]:='H'; func[0]:=#2; end
	      else if func[1]='-' then equStr[3]:='L'
	      else equStr[3]:='X';
	      insertInt;
	(* INT nn;nn;AX = ahal;INT nn AX = ahal;nn ahal;xxxx ... or
	   INT nn;nn;AH = ah;INT nn AH = ah;nn ah;xxxx ... or
	   INT nn;nn;AL = al;INT nn AL = al;nn --al;xxxx ...
	*)
	      if equStr[3]='H'then begin
		insert(copy(ss,29+equBlanks+equBlanks,6)+'--',
		  ss,35+equBlanks+equBlanks);
		insert('AX'+equStr2+copy(ss,39+equBlanks+equBlanks,5),
		  ss,44+equBlanks+equBlanks);
(* INT nn;nn;AH = ah;INT nn AH = ah;nn ah;nn ah--;AX = ah--;xxxx ... *)
	      end; (* equStr[3]='H' *)
	      (* duplicate INT nn Ar = ... and insert secondary register
		 if appropriate.
	      *)
	      if secReg<>'' then case equStr[3] of
		'X': insertSecReg(19+equBlanks, 23+equBlanks);
		'H': insertSecReg(17+equBlanks, 19+equBlanks);
		else insertSecReg(17+equBlanks, 21+equBlanks);
	      end; (* if secReg<>'' then case equStr[3] of *)
	      if equStr[3]='X' then begin (* insert also the AH values *)
		equStr[3]:='H';
		func[0]:=#2;
		insertInt;
(* INT nn;nn;AH = ah;INT nn AH = ah;nn ah;AX = ahal;INT nn AX = ahal;nn ahal;xxxx ... *)
	      end; (* if equStr[3]='X' *)
	    end (* if func<>'----' *)
	    else if secReg<>'' then insertSecReg(1, 10);
	    if NOT longKeys then repeat
	    (* disable long keys by deleting them. It is not very efficient
	       to insert search keys and then delete them again, however,
	       this was introduced at a late state due to restrictions in
	       WinHelp v. 4.00, and implemented the easy way. The long and
               short formats in the preceding code are so integrated that
               it would take hours to write a more efficient implementation.
	    *)
	      p:=pos('INT ',ss);
	      if p=0 then goto deleteDone;
	      q:=p+5;
	      while ss[q]<>';' do inc(q);
	      delete(ss,p,succ(q-p));
	    until false;
	deleteDone:
	  end (* if length(ss)>14 ... *)
	  else if (length(s)=11) and (ssR.l2=listC) then begin
	    insert(copy(ss,1,6)+';',ss,1); (* INT nn;INT nn List *)
	    insert(copy(ss,5,3),ss,8); (* INT nn;nn;INT nn List *)
	  end; (* else if ... *)
	end; (* if (ssR.l=intC) ... *)
	if Classification=tableClassification then begin
	  delete(ss,1,8); (* 'II SUBF ' *)
	  footnote(tableKWT,'#'+currentTable);
	  if highestTableNumber<currentTable then highestTableNumber:=currentTable;
	end (* if Classification=tableClassification *)
	else repeat
	  p := POS(' - ', ss);
	  if p <> 0 then
	    begin
	      ss[p] := ';';
	      delete(ss,succ(p),2);
	    end;
	until p=0;
	if (Classification <> InvalidClassification)
	    AND (Classification > ' ') then begin
	  if categoryKeyStrings[Classification]^<>'' then begin
	    (* check for duplicate before inserting *)
	    p:=pos(categoryKeyStrings[Classification]^,ss);
	    q:=length(categoryKeyStrings[Classification]^);
	    if (p=0) OR ((p+q<>length(ss)) AND (ss[p+q]<>';')) then
	      insert(categoryKeyStrings[Classification]^+';',ss,1);
	  end; (* if categoryKeyStrings[Classification]^<>'' *)
	  if (Classification<'A') OR (Classification>'Z') then
	    insert(Classification+';',ss,1)
	  else insert(Classification+'!;',ss,1);
	end; (* if (Classification<>InvalidClassification) ... *)
      insertKey:
	FootNote('K', SS);
      end; (* if (Classification<>nullClassification) *)

      write(F, '{\f0'+headerAttrib,headerSize,' ');
      if classification=specialClassification then write(F, indexHeader);
      writeln(F, S,'}');
      writeln(F, '\par\pard\keep');
    end;

  Procedure AddTopic(VAR F: Text; ST, S, ID: String);
  { print: ST as a string (normally "\par " for new line), S as a hotspot,
    ID as the corresponding jump address or macro.
  }
    const sp: string[7] = '       ';
    var p: integer;
    begin
      repeat
	(* detab S, otherwise the string cannot be selected with the cursor
	   in a tab position.
	*)
	p:=pos(#9,S);
	if p<>0 then begin S[p]:=' '; sp[0]:=char(7-(pred(p) AND 7)); insert(sp,S,p); end;
	  (* inserts 7..0 spaces for p = 1..8, 9..16 etc., total 8..1 spaces *)
      until p=0;
      writeln(F, ST,'{\uldb ', S, '}{\v ', ID, '}');
    end;

  Procedure CheckKeyWords(VAR s : STring);
    CONST KeyWords = 11;
    CONST Keys : Array[1..KeyWords] of String[10] = ('Desc:', 'Notes:',
      'Note:', 'Warning:', 'Index:', 'SeeAlso:', 'Return:', 'BUG:', 'BUGS:',
      'Program:', 'Range:');
    CONST IStr = '{\b ';
    VAR q,p : Integer;

    begin
      if length(s)<251 then for q:= 1 to KeyWords do begin
	p := POS(Keys[q], S);
	if p <> 0 then begin
	  insert(IStr, S, p);
	  insert('}', S, p+Length(Keys[q]) + Length(IStr));
	  exit;
	end;
      end;
    end;

  Function GetSpecialNote(Note : Char)  : String;
    begin
      if flagStrings[Note]^='' then GetSpecialNote:='<unknown note in header>'
      else GetSpecialNote:=flagStrings[Note]^;
    end;

procedure insertQueued;
  var i,j: word;
  begin
    if (indexColumns>1) OR (queuedEntry='') then exit;
    val('$'+lastSection,i,j);
    if singlesInMain AND (INTcounts[i]=1) then
      AddTopic(IndexFile, nl, queuedEntry, lastSection+'_1')
    else AddTopic(IndexFile, nl, title, lastSection+'_0');
    queuedEntry:='';
  end; (* procedure insertQueued *)

function inArray(n: integer; var arr: tableArray; var top: integer): boolean;
(* returns true if n is in arr, else false *)
  var i: integer;
  begin
    i:=1;
    while (i<=top) AND (arr[i]<>n) do inc(i);
    inArray:=i<=top;
  end; (* function inArray *)

procedure toArray(n: integer; var arr: tableArray; var top: integer);
(* inserts n in arr if not already present *)
  begin
    if inArray(n, arr, top) then exit;
    if top=tableArraySize then errorExit('Table array exceeded',formatErr);
    inc(top);
    arr[top]:=n;
  end; (* procedure toArray *)

Function ProcessIntList(FName : PathStr) : Boolean;
  LABEL STOP, error_Exit, endOfLoop, table, fobi, noTable;
  type
    kind = (firstPart,inOverview,inFlags,inCategories,inKeys,
      inFileBreakSection,pastTest);
    tableId = array[1..8] of char;
    sRec = record
      l: byte; (* length *)
      w: word; (* with '(T' *)
      d: longint; (* with 'able' *)
      c1: char; (* ' ' *)
      ti: tableId; (* digits + ')' *)
    end; (* record sRec *)
    castRec = record
      l: byte;
      case byte of
	1: (w: word);
	2: (d: longint);
	3: (c: char (* space *); r: word; rv: longint);
    end; (* record castRec *)
    dividerRec = record
      s: string[8];	(* '--------' *)
      cat: char;	(* category *)
      c: char;	(* '-' *)
      w: word;	(* Interrupt number, 2 hex digits *)
      d: longint;	(* sub function, 4 hex digits or '-' *)
      r: word;	(* secondary register name, two letters or '--' *)
      rv: longint;	(* sec. reg. value, 4 hex digits or '-' *)
    end; (* record dividerRec *)
  const
    INTno:     integer = 0;
    bufferString: string = ''; (* transfers part of split string *)
    ta = ord('(')+ord('T')*$100; (* (Table nnnnn) *)
    able = ord('a')+ord('b')*$100+ord('l')*$10000+ord('e')*$1000000;
    fo = ord('F')+ord('o')*$100; (* Format of ... *)
    bi = ord('B')+ord('i')*$100; (* Bitfields for ... *)
    Section: String[3] = '--'; (* initialize to length 2 *)
    SubFunc: String[5] = '----'; (* length 4 *)
    allMessages: boolean = false;

  VAR
      tP:          ^tableID;
      hLineP,tLineP : ^string; (* pointers to header and (Table) lines *)
      p,q        : integer;
      curTab     : integer;
      lineCount  : word; (* for error report *)
      NewSection : Boolean;
      Classification,c      : Char;
      current    : kind;
      inTable    : boolean;
      table_Id   : String[7];
      tableTitle : String[119];
      s          : String;
      SpecialNote : String;
      sR         : sRec absolute s; (* for type cast *)
      sectionR   : castRec absolute Section;
      subFuncR   : castRec absolute SubFunc;
      secRegR    : castRec absolute secReg;
      dR         : dividerRec absolute s;
      F1         : Text;

  function isNumber(var ti: tableId): integer;
  (* returns the table number, or negative value if illegal number *)
    var i,res: integer;
    begin
      res:=0;
      for i:=1 to tableDigits do case ti[i] of
	'0'..'9': res:=res*10+ord(ti[i])-ord('0');
	else begin isNumber:=-1; exit; end;
      end; (* for ... do case ... *)
      isNumber:=res;
    end; (* function isNumber in function ProcessIntList *)
  procedure insertRef;
    begin
      if inTable then AddTopic(TabTopics,nl,'INT '+Section+' '+SubFunc, TopicStr+mainW)
      else if current<>inFileBreakSection then
	AddTopic(IntTopics,nl,copy(title,1,6),IntTopicStr);
    end; (* procedure insertRef in function ProcessIntList *)
  procedure wrSection; (* show progress *)
    begin write(Section,#13); end;

  begin
   {$I-}
    assign(F1, InPath + FName);
    reset(F1);
   {$I+}
    if IOResult <> 0 then begin
      ProcessIntList := FALSE;
      EXIT;
    end;
    writeln('Processing : ', InPath + FName);
    wrSection;
    readLine(F1, s);    { ignore copyright in 1st two lines }
    readLine(F1, s);
    lineCount:=2;
    current:=inFileBreakSection;
    inTable:=false;
    SpecialNote := '';
    while not(EOF(F1)) do begin
      readLine(F1, s);
      inc(lineCount);
      NewSection := (s[1]= '-') and (Pos('--------', s) = 1);
      if NewSection then begin
	if inTable then insertRef;
	for p:=1 to tabTop do begin
	  q:=tabArray[p];
	  if NOT inArray(q, refArray, refTop) then begin
	    str(1000000+Longint(q),table_Id); (* 1xxnnnn *)
	    delete(table_Id,1,7-tableDigits);  (* [n]nnnn  *)
	    AddTopic(intTopics,nl,'Table #'+table_Id,'t'+table_Id+tableW);
	    inc(insertCounter);
	  end; (* if NOT inArray() *)
	end; (* for p:=1 *)
	inTable:=false;
	insertRef;
	if tabTop>maxTabTop then maxTabTop:=tabTop;
	tabTop:=0;
	if refTop>maxRefTop then maxRefTop:=refTop;
	refTop:=0;
	Classification := s[9];
	if Classification = '!' then begin
	  delete(s,1,12);
	  q:=0;
	  while (s[q] <> '-') and (q < Length(s)) do
	    Inc(q);
	  s[0] := chr(q-1);  { remove '-' chars at the end }
	  if s='OVERVIEW' then current:=inOverview
	  else if s='FLAGS' then current:=inFlags
	  else if s='CATEGORIES' then current:=inCategories
	  else if s='CATEGORYKEYS' then current:=inKeys
	  else if s='Section' then begin
	    current:=inFileBreakSection;
	    goto endOfLoop;
	  end (* else if s='Section' *)
	  else current:=firstPart;
	  (* Interrupt List release 41 does not include OVERVIEW
	     and CATEGORYKEYS as sections, but as separate files.
	     The program is prepared for this information being
	     parts of the List.
	  *)
	  if s = '' then s:= 'Note';
	  if EOF(F1)  then   { last line of document ?}
	    goto STOP;
	  inc(TopicNo);
	  str(TopicNo, TopicStr);
	  if lastSection > '-' then section:='--'; (* at end of list *)
	end { if Classification = '!' }
	else begin (* (Classification <> '!') *)
	  SectionR.w:=dR.w; (* chars 11..12 of divider line *)
	  SubFuncR.d:=dR.d; (* chars 13..16 of divider line *)
	  secRegR.r:=dR.r;  (* chars 17..18 of divider line *)
	  if secReg[2]='-' then secReg[0]:=#0
	  else begin
	    secRegR.rv:=dR.rv; (* chars 19..22 of divider line *)
	    if secReg[6]='-' then secReg[0]:=#5 else secReg[0]:=#7;
	  end; (* else *)
          if section<>lastSection then begin
	    val('$'+section,INTno,q);
	    if q<>0 then begin
	      writeln('Cannot interpret interrupt number in line ',
		lineCount,': "',section,'".');
	      goto error_Exit;
	    end; (* if q<>0 *)
	  end; (* if section<>lastSection *)
	  current:=pastTest;
	  readLine(F1, s);
	  inc(lineCount);
	  inc(INTcounts[INTno]);
	  str(INTcounts[INTno], TopicStr);
	  insert(section+'_',TopicStr,1);
(* We could compare already here: "while aliasString=s do ..." if we want to
   use the orginal interrupt header line to find aliases. However,
     1. it is easier to identify the original position of an alias line,
     2. it is easier to determine the alias sequense in the config. file,
     3. it is easier to track the reason for a "not found" error, and
     4. the chance for an alias line to be unique is higher
   if we compare after the manipulation of the header line. Also, if we copy
   from the INTWIN index rather than from the original list, the lines are
   already manipulated.
*)
	while (s[8] <> '-') do begin { special flags in titel-line ? }
	  if s[8] <> ' ' then
	    SpecialNote:=SpecialNote+#13#10'\par '+GetSpecialNote(s[8]);
	  delete(s, 8, 1);
	end;
        Insert(subFunc+' ', S, 8);
	while aliasString=S do begin
	  saveAlias(nextAliasPP,aliasId+TopicStr);
	  getNextAlias(aliasP,aliasId,aliasString);
	end; (* while aliasString=S *)
      end; { else (Classification<>'!') }
      if LastSection <> Section then begin
	if Classification = '!' then begin
	  if indexColumns=1 then insertQueued;
	  IntTopicStr:='N_'+TopicStr;
	  title:='Notes';
	  if (notesCount MOD indexColumns)=0 then write(IndexFile,'\par ')
	  else  write(IndexFile,'\tab ');
	  inc(notesCount);
	  writeln(IndexFile,'{\uldb Notes}{\v ',IntTopicStr,'}');
	end (* if Classification = '!' *)
	else begin (* (Classification <> '!') *)
	  if INTno<lastINTno then begin
	    (* we cannot tolerate inconsistent sorting in a
	       multi-column index.
	    *)
	    writeln('Inconsistent sorting in file ',FName,
	      ' line ',lineCount);
	    writeln('INT ',section,' appears after INT ',lastSection);
	    if indexColumns>1 then begin
	      wl('This can be tolerated only with a single column index.');
   error_Exit:
	      errorExit('Please correct the file and try again.',fileErr);
	    end; (* if indexColumns>1 *)
	    wl(#7'It is recommended to correct the file.');
	  end; (* if INTno<lastINTno *)
	  wrSection;
	  IntTopicStr:=Section+'_0';
	  if indexColumns=1 then begin
	    insertQueued;
	    queuedEntry:=s;
	  end; (* if indexColumns=1 *)
	  title:=INTtitles[INTno]^;
	  if title='' then title:='INT '+Section;
	  lastINTno:=INTno;
        end; (* else (Classification <> '!') *)
	if backRef then AddTopic(SubIntFile,nl,'Interrupts','idInterrupts');
	  (* don't insert a backward reference the very first time *)
	backRef:=true; (* but in all the rest *)
	NewHlpPage(SubIntFile, title, IntTopicStr,'i:0', specialClassification);
	if twoIndexes AND indexHeaders then
	  OutLn(IntFile,'\par '+title);
	LastSection := Section;
      end; { if LastSection <> Section }
      if TopicNo=1 then c:=specialClassification
	(* The initial Interrupt List section should cary the
	   indexHeader.
	*)
      else c:=Classification;
      NewHlpPage(IntTopics, s, TopicStr,'l:0', c);
      if SpecialNote <> '' then	begin
	writeln(IntTopics, '{\cf0 ', SpecialNote, '}'#13#10'\par ');
	SpecialNote := '';
      end; { if SpecialNote <> '' }
      OutLN(IntTopics, '{\cf0 Category: '+ Classification +
	' - ' + categoryStrings[Classification]^ + '}\par');
      if Classification='!' then setTabs(IntTopics, 8, deciPoints, 10)
	(* we will set tabs in the few Notes, but not in all the
	   INT entries.
	*)
      else if markKeys then OutLN(IntTopics,'{\b Inp.:}');
      if twoIndexes then AddTopic(IntFile, indentIndex, s, TopicStr);
      AddTopic(SubIntFile, nl, s, TopicStr);
    end { if NewSection }
    else begin { no new section }
      case current of
	pastTest: begin
  { this paragraph is un-indented to gain space for code }
  if markKeys then CheckKeyWords(s);
  { check the first two characters and react on '(T'[able nnnn)],
    'Fo'[rmat of ...] and 'Bi'[tfields for ...]
  }
  if tables then case sR.w of
    ta: if (length(s)>=12) AND (sR.d=able) AND (sR.c1=' ')
      AND (sR.ti[tableDigits+1]=')') AND (isNumber(sR.ti)>=0) then begin
	hLineP:=@bufferString;
	tLineP:=@s;
  table:
	if eof(F1) then begin
	  writeln('Unexpected end of file in table at INT ',Section,
	    ' Subfunc ',SubFunc);
	  wrSection;
	  goto Stop;
	end; (* if eof(F1) *)
	ReadLine(F1, bufferString); (* v. 1.19: rather than readln() *)
	inc(lineCount);
	p:=pos('(Table ',tLineP^);
	if (p=0) OR  (length(tLineP^)<p+tableDigits+7) OR
	  (tLineP^[p+tableDigits+7]<>')') then begin
  noTable:
	  inc(missingTableCounter);
	  if allMessages OR (missingTableCounter<=missingTableLimit) then begin
	    writeln('Missing "(Table nnnn)" in INT ',Section,
	      ' Subfunc ',SubFunc,' (line ',lineCount,'):');
	    writeln(pred(lineCount):5,s:succ(length(s)));
	    writeln(lineCount:5,bufferString:succ(length(bufferString)));
	    if missingTableCounter=missingTableLimit then begin
	      wl(#13#10'Several missing tables encountered. If '
		+progName+' is used on release 58 or lower');
	      wl('of the List, it should be started with the program '
		+'parameter -rXX where XX is');
	      wl('the release number, or with key releaseNo=XX in section '
	        +'[OPTIONS] of the');
	      wl('configuration file.');
	      write('s=stop; m=messages; else continue without messages: ');
	      ProcessTime:=ProcessTime-memL[$40:$6C];
	      p:=readKeyWd;
	      ProcessTime:=ProcessTime+memL[$40:$6C];
		(* sets ProcessTime "pause" ticks later than original *)
	      if word(p)<$100 then writeln (* function key *)
	      else begin
		writeln(char(p));
		case upcase(char(p)) of
		  'S': errorExit('Terminated by user',userErr);
		  'M': allMessages:=true;
		end; (* case upcase(char(p)) of *)
	      end; (* else *)
	    end; (* if missingTableCounter=missingTableLimit *)
	    wrSection;
	  end; (* if allMessages ... *)
	  insert(nl,bufferString,1); (* force newline *)
	end (* if (p=0) ... *)
	else begin
	  tP:=@tLineP^[p+7];
	  curTab:=isNumber(tP^);
	  if curTab<0 then goto noTable;
	  toArray(curTab, tabArray, tabTop);
	  currentTable:=copy(tP^,1,tableDigits);
	  table_Id:='t'+currentTable;
	  if inTable then insertRef;
	  inTable:=true;
	  tableTitle:=Section+' '+SubFunc+' '+hLineP^;
	  while tableAliasString=tableTitle do begin
	    saveAlias(nextAliasPP,tableAliasId+table_id);
	    getNextAlias(tableAliasP,tableAliasId,tableAliasString);
	  end; (* while ... *)
	  NewHlpPage(TabTopics, tableTitle, table_Id,'t:0', tableClassification);
	  if tableWindow then begin
	    AddTopic(TabTopics,nl,'Copy to Main',table_Id+mainW);
	    OutLn(TabTopics,'');
	  end; (* if tableWindow *)
	  if sR.w=ta then begin (* bold Table nnnnn *)
	    s[1]:='{';             (* substitutes '(' *)
	    s[tableDigits+8]:='}'; (*   and ')'       *)
	    insert('\b ',s,2);
	  end (* if sR.w=ta *)
	  else begin
	    writeln(TabTopics,'\par {\b Table ',currentTable,'}');
	    bufferString[0]:=char(pred(p)); (* delete '(Table nnnn)' *)
	  end; (* else *)
	  AddTopic(TableFile,nl+currentTable+'  ',tableTitle,table_Id);
	end; (* else *)
    end; (* case ta *)
    fo: if pos('Format of ',s)=1 then begin
  fobi:
      hLineP:=@s;
      tLineP:=@bufferString;
      goto table;
    end; (* case fo *)
    bi: if pos('Bitfields for ',s)=1 then goto fobi;
    else begin
      p:=length(s)-tableDigits;
      for q:=p downto 1 do begin
	if (s[q]='#') AND ((q=p) OR (s[q+tableDigits+1]<'0') OR
	    (s[q+tableDigits+1]>'9')) then begin
	  tP:=@s[q+1];
	  curTab:=isNumber(tP^);
	  if curTab>=0 then begin
	    toArray(curTab, refArray, refTop);
	    insert('}{\v t'+copy(tP^,1,tableDigits)+tableW+'}', S, q+tableDigits+1);
	    insert('{\uldb ', S, q);
	    if (length(s)-q>150) AND (q>20) then begin
	      (* we must ensure keeping length(S)<256 *)
	      bufferString:=copy(S, q, 255);
	      S[0]:=char(pred(q)); (* delete the copied part *)
	    end; (* if (length(s)-q>150)... *)
	  end; (* if curTab>=0 *)
	end; (* if (s[q]='#')... *)
      end; (* for q=p *)
    end; (* else *)
  end; (* case sR.w of *)
  { indent again }
	  end; (* case pastTest *)
	  firstPart:    check1st(s);
	  inOverview:   getINTtitle(s,INTtitles);
	  inFlags:      scan(s,flagStrings);
	  inCategories: scan(s,categoryStrings);
	  inKeys:       scan(s,categoryKeyStrings);
	  inFileBreakSection: goto endOfLoop;
	end; (* case current of *)
	if inTable then OutLN(TabTopics, s) else OutLN(IntTopics, s);
	if bufferString<>'' then begin
	  if inTable then OutLn(TabTopics, bufferString) (* with "newline" *)
	  else writeln(IntTopics, bufferString); (* no "newline" (\par ) *)
	  bufferString:='';
	end; (* if bufferString<>'' *)
      end; { else (no new section) }
  endOfLoop:
    end; { while not(EOF(F1)) }
  STOP:
    if inTable then insertRef;
    inTable:=false;
    insertRef;
    close(F1);
    ProcessIntList := TRUE;
  end;

procedure missingFile(var fname: string);
  var dir: dirstr; name: namestr; ext: extstr;
  begin
    fsplit(fname, dir, name, ext);
    writeln(#7'Unable to open ', fname);
    inc(warnings);
    outln(indexFile,
      'Unfortunately, file '+name+ext+' was unavailable at compile time.');
  end; (* procedure missingFile() *)

  Procedure NewPage(VAR F: Text; Title : String);
    VAR TopicStr : String;

      begin
	Inc(TopicNo);
	str(TopicNo, TopicStr);
	AddTopic(IndexFile, nl, Title, TopicStr);
	NewHlpPage(F, Title, TopicStr,'p:0', InvalidClassification);
	setTabs(F, 8, deciPoints, 10);
      end;

  Procedure ProcessPorts(FName : PathStr);
(* Compile a file so that it gets its own index and is devided into sub topics.
   If FName has no extension, .LST is assumed, and if a file with extension .LST
   is not found .A and successive files .B, .C, ... are assumed ignoring the first
   two lines of .B and the following files.
*)
    LABEL STOP, ok;
    VAR i, kind    : integer;
	s          : String;
	dir        : dirStr;
	name       : nameStr;
	ext        : extStr;
	NewSection : Boolean;
	F1         : Text;

    begin
      kind:=0;
      defaultDir(FName,InPath);
      fSplit(FName, dir, name, ext);
      if ext='' then begin
        ext:='.LST';
        inc(kind);
      end; (* if ext='' *)
     {$I-}
      assign(F1, dir+name+ext);
      reset(F1);
     {$I+}
      if IOResult <> 0 then begin
	if kind=1 then begin
	  ext:='.A';
	 {$I-}
	  assign(F1, dir+name+ext);
	  reset(F1);
	 {$I+}
	  if IOResult=0 then begin inc(kind); goto ok; end
	end; (* if kind=1 *)
	missingFile(FName);
	EXIT;
      end; (* if IOResult <> 0 *)
    ok:
      writeln('Processing : ', dir, name, ext);
      if kind<3 then NewPage(IntTopics, name+' Note');
      while not(EOF(F1)) do
	begin
	  readLine(F1, s);
	  NewSection := (s[1]= '-') and (Pos('---------', s) <> 0);
	  if NewSection then
	    begin
	      readLine(F1, s);
	      if EOF(F1)  then   { last line of document ?}
		goto STOP;
	      if s <> '' then                { why does this happend }
		NewPage(IntTopics, s);
	    end
	  else
	    begin
	     CheckKeyWords(s);
	     OutLN(IntTopics, s);
	    end;
	end;
    STOP:
      close(F1);
      if (kind>1) AND (kind<=2+ord('Z')-ord('A')) then begin
	inc(ext[2]);
       {$I-}
	assign(F1, dir+name+ext);
	reset(F1);
       {$I+}
	if IOResult=0 then begin inc(kind); readln(F1); readln(F1); goto ok; end
	  (* ignore the first two lines of .B, .C, ... *)
      end; (* if (kind>1)... *)
    end;

  Procedure ProcessFile(FName : String; Title : String);
    VAR s          : String;
	F1, F2     : Text;
        interrup1st: boolean;

    begin
      defaultDir(FName,InPath);
      interrup1st:=pos('INTERRUP.1ST',FName)<>0;
     {$I-}
      assign(F1, FName);
      reset(F1);
     {$I+}
      if IOResult <> 0 then
	begin
	  missingFile(FName);
	  if interrup1st then OutLn(IndexFile,
	    '{K}{\footnote K interrup.1st Contact Info}'#13#10+
	    'For contact information, try keyword '+
	    '{\uldb CONTACT_INFO}{\v !JumpKeyword(qchPath,"CONTACT_INFO")}.');
	  EXIT;
	end;

      writeln('Processing : ', FName);
      setTabs(IndexFile, 8, deciPoints, 10);

      while not(EOF(F1)) do
	begin
	  readLine(F1, s);
	  if interrup1st AND (pos('-CONTACT_INFO-', s)<>0) then
	    insert(#13#10'{K}{\footnote K Ralf Brown}'
              +#13#10'{K}{\footnote K Brown, Ralf}'
              +#13#10'{K}{\footnote K CONTACT_INFO}'
              (* the following is used as JumpKeyword() target from Credits *)
              +#13#10'{K}{\footnote K interrup.1st Contact Info}'
              +#13#10, s, 1);
	  OutLN(IndexFile, s);
	end;

      close(F1);
    end;

  Procedure Credits;
    begin
      OutLn(IndexFile,'');
      AddTopic(IndexFile, nl, 'Credits', 'idCredits');
      OutLn(IndexFile,'');
      OutLn(IndexFile,compilationStr);
      NewHlpPage(IndexFile, 'Credits', 'idCredits','m:1', InvalidClassification);
      OutLn(IndexFile,'\pard{\f0'+headerSize+
	'\qc\par Interrupt List (c) by {\b Ralf Brown}'#13#10 { \qc=centered }
        +'{' + header2ndSize + '\par (See '
        +'{\uldb Contact Info in interrup.1st}'
        +'{\v !JumpKeyword(qchPath,"interrup.1st Contact Info")})}\par');
      OutLn(IndexFile,'\par This list was converted from the released ASCII file'#13#10
		    + '\par to the Windows Help-Format by \par\par'#13#10
		    + '\par {\b Christian M\''81ller-Planitz}'
                    + '{' + header2ndSize + '\par ' + e_mailCredits + '}'
		    + '\par and'
                    + '\par {\b Bent Lynggaard}'+header2ndSize);
      OutLn(IndexFile,e_mailCredits2);
(* an alternative format of the last few lines:
		    + '\par {\b Christian M\''81ller-Planitz}'
		    + '   and   {\b Bent Lynggaard}'+header2ndSize);
      OutLn(IndexFile,e_mailCredits + '  and  ' + e_mailCredits2);}
*)
      if ack01<>'' then begin
	writeIndex('\par\par Thanks to:');
	writeIndex(ack01);
	writeIndex(ack02);
	writeIndex(ack03);
	writeIndex(ack04);
	writeIndex(ack05);
      end; (* if ack01<>'' *)
      writeIndex('\par}');
    end;

procedure processTopics(n: integer);
(* inserts references to n topics in the CONTENTS main index *)
  var i: integer; w: string[13]; title,id: string[39];
  begin
    for i:=1 to n do begin
      str(i,w);
      insert('WINDOW ',w,1);
      title:='';
      profileString(w,'title',title,pred(sizeOf(title)));
      id:='';
      profileString(w,'id',id,pred(sizeOf(id)));
      if (title<>'') AND (id<>'') then AddTopic(IndexFile,nl,title,id);
    end; (* for i:=1 *)
  end; (* procedure processTopics *)

procedure processPages(n: integer);
(* processes n "windows" as defined in the configuration file *)
  var
    i,j,wType,files,fType: integer;
    w: string[13];
    f: string[17];
    id: string[17];
    fId,chain: string[21];
    title,fTitle: string[39];
    fileName: pathStr;
  begin
    for i:=1 to n do begin
      str(i,w);
      insert('WINDOW ',w,1);
      title:='';
      profileString(w,'title',title,pred(sizeOf(title)));
      id:='';
      profileString(w,'id',id,pred(sizeOf(id)));
      if id<>'' then begin
	wType:=1;
	profileInt(w,'type',wType);
	files:=1;
	profileInt(w,'files',files);
	case wType of
	  1: NewHlpPage(IndexFile,title,id,'f:0',InvalidClassification);
	    (* Single entry windows *)
	  2: NewHlpPage(IndexFile,title,id,'m:9',InvalidClassification);
	    (* Multi entries windows *)
	  3: ; (* nop *)   (* Windows with own contents list *)
	end; (* case wType of *)
	for j:=1 to files do begin
	  str(j,f);
	  insert('file ',f,1);
	  fileName:='';
	  profileString(w,f,fileName,pred(sizeOf(fileName)));
	  if fileName<>'' then begin
	    fType:=wType;
	    profileInt(w,f+' type',fType);
	    case fType of
	      1: ProcessFile(fileName,title);
	      2: ProcessPorts(fileName);
	      3: begin
		(* the RTF file is expecte to be in:
		     a. the current directory.
		     b. the program's home directory
		   if no drive or root is specified.
		*)
		if ((length(fileName)<2) OR (fileName[2]<>':'))
		  AND (fileName[1]<>'\') AND (fileName[1]<>'.') then begin
		  if exist(filename) OR NOT exist(homeDir+filename) then
		    insert(currentDir,filename,1)
		  else insert(homeDir,filename,1);
		end; (* if (fileName[2]<':'... *)
		fileName:=fExpand(fileName);
		if NOT exist(fileName) then begin
		  writeln(#7'File ',fileName,' not found, copy to ',currentDir);
                  inc(warnings);
                end; (* if NOT exist(filename) *)
		writeln(HPJ,fileName); (* include the file name *)
	      end;
	      4: begin (* ASCII file in multi file entry *)
		str(j,fTitle);
		str(j,fId);
		insert(title+' - ',fTitle,1);
		insert(id+'_',fId,1);
		chain:=id+':5';
		profileString(w,f+' title',fTitle,pred(sizeOf(fTitle)));
		profileString(w,f+' id',fId,pred(sizeOf(fId)));
		profileString(w,f+' chain',chain,pred(sizeOf(chain)));
		NewHlpPage(IndexFile,fTitle,fId,chain,InvalidClassification);
		defaultDir(fileName,currentDir);
		ProcessFile(fileName,fTitle);
	      end; (* case 4 *)
	    end; (* case fType of *)
	  end (* if fileName<>'' *)
	  else begin
	    writeln(#7'Missing file name for [',w,'] ',f);
	    inc(warnings);
	  end; (* else *)
	end; (* for j:=1 *)
      end (* if (title<>'') ... *)
      else begin
	writeln(#7'Missing identifier in ',w);
	inc(warnings);
      end; (* else *)
    end; (* for i:=1 *)
  end; (* procedure processPages *)

procedure processFilter;
  var d: dirStr;
  begin
    PageRTF(IndexFile); (* insert '\page' if appropriate *)
    writeIndex('\pard');
    writeIndex('#{\footnote{#} idPartComp}');
    writeIndex('{\f0'+header2ndSize+' This compilation of the Interrupt List does '+#13#10
      +'not contain all the information in the List, see the '#13#10
      +'{\uldb INTERRUP.1ST File}{\v id1st} for the availability of the ');
    writeIndex('complete list.\par\par');
    writeIndex('See {\uldb Filter Method}{\v idFlt_meth} and '#13#10
      +'{\uldb Filter File}{\v idFlt_file} for details.\par}');
    d:=currentDir;
    if NOT exist('FLT_METH.RTF') then begin
      if exist(homeDir+'FLT_METH.RTF') then d:=homeDir
      else begin
	writeln(#7'File FLT_METH.RTF not found, copy to ',d);
	inc(warnings);
      end; (* else *)
    end; (* if NOT exist() *)
    writeln(HPJ,d,'FLT_METH.RTF');
    NewHlpPage(IndexFile, 'Filter File', 'idFlt_file','flt:1', invalidClassification);
    processFile(filterFileName,'Filter File');
  end; (* procedure processFilter *)

procedure readCategoryKeys;
(* Opens file CATEGORY.KEY if available, and reads definitions to
   categoryKeyStrings. Definitions are of the type
      A - definition A, B - definition B,
   The definitions are inserted as search keys for the appropriate
   categories. Note that more than one keyword per entry is accepted,
   separated by a semicolon, e.g. " c - cachers;spoolers,".

   Reads also title file OVERVIEW.LST.

   CATEGORY.KEY and OVERVIEW.LST are separate files in Interrupt List
   release 41+.
*)
  var t: text; s: string;
  begin
(*$I-*)
    assign(t,InPath+'category.key');
    reset(t);
(*$I+*)
    if IOresult<>0 then writeln('Unable to open ',InPath,'CATEGORY.KEY')
    else begin
      while NOT eof(t) do begin readln(t,s); scan(s,categoryKeyStrings); end;
      close(t);
    end; (* else *)
(*$I-*)
    assign(t,InPath+'overview.lst');
    reset(t);
(*$I+*)
    if IOresult<>0 then writeln('Unable to open ',InPath,'OVERVIEW.LST')
    else begin
      while NOT eof(t) do begin readln(t,s); getINTtitle(s,INTtitles); end;
      close(t);
    end; (* else *)
  end; (* procedure readCategoryKeys *)

procedure INTsToIndex;
  var i,j,k,l: word; s: string[3];
  begin
    for k:=0 to pred(indexPages) do begin
      l:=k*indexRows*indexColumns;
      for i:=0 to pred(indexRows) do begin
	OutLn(IndexFile, '');
	for j:=0 to pred(indexColumns) do begin
	  if INTcounts[l+i+j*16]<>0 then begin
	    write(IndexFile,'{\uldb INT ',HEX(l+i+j*16));
	    if indexColumns=4 then write(IndexFile,' List');
	    write(IndexFile,'}{\v ',HEX(l+i+j*16),'_0}');
	  end (* if INTcounts[]<>0 *)
	  else if indexColumns=4 then write(IndexFile,'\tab ');
	  if j<pred(indexColumns) then write(IndexFile,'\tab ');
	end; (* for j:=0 *)
      end; (* for i:=0 *)
      if k<pred(indexPages) then OutLn(IndexFile, '');
    end; (* for k:=0 *)
  end; (* procedure INTsToIndex *)

  const
    windows: integer = 0;

  var
    i: integer;
    ch: char;

  begin
    Intro;
    if (paramStr(1)='?') OR (paramStr(1)='-?') OR (paramStr(1)='/?')
      then Explain; (* and exit *)

    fSplit(paramStr(0),homeDir,currentDir,currentDir);
      (* works only with DOS 3.30+ - currentDir is used as a dummy *)
    currentDir:=fExpand('.');
    if length(currentDir)>3 then begin
      inc(currentDir[0]);
      currentDir[length(currentDir)]:='\';
    end; (* if length()... *)
    interpretParameters;
    initializeArrays;
    nextAliasPP:=@firstAliasP;

    if InPath='' then begin
      write('Source directory: ');
      readln(InPath);
    end; (* if InPath='' *)
    if InPath<>'' then begin
      ch:=InPath[length(InPath)];
      if (ch<>':') AND (ch<>'\') then
	begin inc(InPath[0]); InPath[length(InPath)]:='\'; end;
    end; (* if InPath<>'' *)

    if OutPath='' then begin
      write('Dest. directory (has to be created in advance) : ');
      readln(OutPath);
    end; (* if OutPath='' *)
    if OutPath<>'' then begin
      ch:=OutPath[length(OutPath)];
      if (ch<>':') AND (ch<>'\') then
	begin inc(OutPath[0]); OutPath[length(OutPath)]:='\'; end;
    end; (* if OutPath<>'' *)

    ProcessTime:=memL[$40:$6C]; { timer ticks since midnight }
    findDateAndCopyright;
    CreateHPJ;

    OpenRTF(IndexFile, 'INDEX.RTF');
    NewHlpPage(IndexFile, 'Contents:', 'CONTENTS','m:2', specialClassification);

    readCategoryKeys; (* reads also titles *)
    OpenRTF(SubIntFile,'SUBINT.RTF');
    OpenRTF(IntTopics, 'INTTOPIC.RTF');
    if twoIndexes then OpenRTF(IntFile, 'INT.RTF');

    if twoIndexes then
      AddTopic(IndexFile, nl, 'Interrupt Index',
	'!IfThenElse(IsMark("Compressed_Index"), '
	+'`JumpId(qchPath,"idInterrupts")'', `JumpId(qchPath,"idIndex")'')')
    else AddTopic(IndexFile, nl, 'Interrupts', 'idInterrupts');
    if tables then AddTopic(IndexFile, nl, 'Tables', 'idTables');
    AddTopic(IndexFile, nl, 'FILELIST', '1');
    AddTopic(IndexFile, nl, 'INTERRUP.1ST File', 'id1st');
    if filtered then begin
      AddTopic(IndexFile, nl, 'Filter Method', 'idFlt_meth');
      AddTopic(IndexFile, nl, 'Filter File', 'idFlt_file');
    end; (* if filtered *)

    profileInt('WINDOWS','number',windows);
    processTopics(windows); (* insert Ports, Memory etc. in index *)

    Credits;

    if twoIndexes then begin
      NewHlpPage(IntFile, 'Interrupt Index', 'idIndex','m:3', specialClassification);
      AddTopic(IntFile, nl, 'Compress index',
	'!SaveMark("Compressed_Index");JumpId(qchPath,"idInterrupts")');
      { the program adds all following entries }
    end; (* if twoIndexes *)
    NewHlpPage(IndexFile, 'Interrupts', 'idInterrupts','m:4', specialClassification);
    if twoIndexes then begin
      AddTopic(IndexFile, nl, 'Expand index','!IfThen(IsMark("Compressed_Index"),'
	+' `DeleteMark("Compressed_Index")'');JumpId(qchPath,"idIndex")');
      OutLn(IndexFile, '');
      if indexColumns>1 then setTabs(IndexFile, succ(ord(indexColumns<=4))*8,
	deciPoints, pred(indexColumns));
    end; (* if twoIndexes *)

    if tables then begin
      OpenRTF(TableFile, 'TABLE.RTF');
      OpenRTF(TabTopics, 'TABTOPIC.RTF');
      NewHlpPage(TableFile,'Tables\f1'+fontSize+'\par\par Tab# INT Func Title',
	'idTables','m:5', invalidClassification);
      (* "Tab# INT Func Title" in normal text font and size *)
    end; (* if tables *)

    profileList('ALIAS',aliasP); (* read [ALIAS] section from config. file *)
    getNextAlias(aliasP,aliasId,aliasString); (* get the first one (if any) *)
    profileList('TABLEALIAS',tableAliasP);
    getNextAlias(tableAliasP,tableAliasId,tableAliasString);

    (* process either "interrup.lst" or "interrup.a".."interrup.?" *)
    if NOT ProcessIntList('interrup.lst') then begin
      ch := 'a';
      while ProcessIntList('interrup.'+ch) do inc(ch);
    end; (* if NOT ProcessIntList() *)
    if NOT longKeys then writeln(HPJ,'SHORTKEY.RTF');
      (* include short keyword help topic *)
    if tableKWT<>'K' then begin
      NewHlpPage(TableFile,'#Table Search','idTableSearch','ts:1',
	titleOnlyClassification);
      AddTopic(TableFile,nl,'Enter a table number','!SearchSecondaryKey'
	+'(hwndApp,qchPath,84,`IntWin Table'',`Enter a four digit table number 0001 - '
	+highestTableNumber+''',`#'',`'')');
	(* 84 is ord('T') *)
      writeln(TableFile,' (seckey.dll required, see details)');
      AddTopic(TableFile,nl,'Cancel','!back()');
      AddTopic(TableFile,nl,'Table Search Details','idTableDetails');
      writeln(HPJ,'TABLEKWT.RTF');
      (* include table keyword topic *)
    end; (* if tableKWT<>'K' *)

    if aliasString<>'' then begin
      writeln(#7'Alias string not found:'#13#10+'  "',aliasString,'"');
      inc(warnings);
      if aliasP<>NIL then
	wl('One or more alias strings not processed.');
    end; (* if aliasP<>NIL *)
    if tableAliasString<>'' then begin
      writeln(#7'Table alias string not found:'#13#10+'  "',
	tableAliasString,'"');
      inc(warnings);
      if tableAliasP<>NIL then
	wl('One or more table alias strings not processed.');
    end; (* if tableAliasP<>NIL *)

    if indexColumns=1 then insertQueued
    else INTsToIndex;

    NewHlpPage(IndexFile, 'INTERRUP.1ST File', 'id1st','f:0', invalidClassification);
    ProcessFile('interrup.1st', 'INTERRUP.1ST File');
    if filtered then processFilter;

    processPages(windows); (* process Ports, Memory etc. *)

    if firstAliasP<>NIL then begin
      writeln(HPJ,#13#10'[ALIAS]');
      processAliasList(firstAliasP);
    end; (* if (firstAliasP<>NIL)... *)
    if twoIndexes then closeRTF(IntFile);
    closeRTF(SubIntFile);
    closeRTF(IntTopics);
    if tables then begin
      closeRTF(TableFile);
      closeRTF(TabTopics);
    end; (* if tables *)
    closeRTF(IndexFile);
    close(HPJ);
    if missingTableCounter>=missingTableLimit then
      writeln(missingTableCounter,' missing tables encountered.');
    ProcessTime:=memL[$40:$6C]-ProcessTime;
    writeln('The processing took ',(ProcessTime*10+91) DIV 182,' seconds.');
      (* 18.2 clock ticks per second, rounded *)
    i:=(maxTabTop*100) DIV tableArraySize;
    if i>60 then writeln(i,'% table array usage.');
    i:=(maxRefTop*100) DIV tableArraySize;
    if i>60 then writeln(i,'% reference array usage.');
    if insertCounter<>0 then writeln('Inserted ',insertCounter,' table references.');
    if warnings<>0 then begin
      writeln('Issued ',warnings,' warning(s).');
      halt(1);
    end; (* if warnings<>0 *)
  end.
