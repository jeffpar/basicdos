{

Converts Ralf Brown's Interrupt List to .NG Compilable Source Files

Version 1.13

(c) Copyright 1995, Michael Gallias

Target: Real

}


Program RBNG;

{$F-} {$O-} {$A+} {$G-}
{$V-} {$B-} {$X-} {$N+} {$E+}

{$M 8192,0,0}

Uses PasStr,CRT;

Type
  ConvertType = Array [1..100] of
                Record
                  IfThis  :String[10];
                  ThenThis:String[10];
                End;

Var
  BatchJob,
  MenuLink,
  F,G          :Text;
  L            :String;
  SeeAlsoLine  :String;

  IntFiles     :Array[0..255] of String[12];

Procedure Pad(Total,WithChar:Byte);

Begin
  For Total:=1 to Total do      {As many times as requested}
      Write(Chr(WithChar));     {write the char}
End;  {Pad}

Procedure EditString(X,Y,MaxLets:Byte;Upper:Boolean;Var MainStr:String);

Var
  Ins             :Boolean;   {Boolean for the Insert Key Status}
  C               :Char;      {Current Character}
  CurXPos,
  Count           :Byte;      {Number Of Chars In String}

Begin
  Ins:=False;                {The Insert key has not yet been pressed}
  CurXPos:=1;                {Current Relative X Position+1}
  GotoXY(X,Y);
  UnPadVar(MainStr,MainStr);
  If Length(MainStr)>MaxLets Then
    MainStr:=Copy(MainStr,1,MaxLets);
  Write(MainStr);
  Pad(MaxLets-Length(MainStr),32);
  Count:=Length(MainStr)+1;  {How many letters in the string+1}

  Repeat                     {Repeat Until [Return] is Pressed}
    GotoXY(X+CurXPos-1,Y);   {Goto the Requested Area}
    If Upper Then
      C:=UpCase(ReadKey)
    Else
      C:=ReadKey;

    If C=Chr(0) Then         {Check for a cursor key}
    Begin
      C:=ReadKey;            {Which cursor key}         {Numeric Keypad Value}
      If (C='O') Then CurXPos:=Count;                            {1}
      If (C='P') And (CurXPos>=3) Then Dec(CurXPos,2);           {2}
      If (C='Q') And (CurXPos>=4) Then Dec(CurXPos,3);           {3}
      If (C='K') And (CurXPos>1) Then Dec(CurXPos);              {4}
      If (C='M') And (CurXPos<Count) Then Inc(CurXPos);          {6}
      If (C='G') Then CurXPos:=1;                                {7}
      If (C='H') And (CurXPos<=Count-2) Then Inc(CurXPos,2);     {8}
      If (C='I') And (CurXPos<=Count-3) Then Inc(CurXPos,3);     {9}
      If (C=#7 ) Then MainStr[0]:=Chr(CurXPos-1);                {Shift-Del}
      If (C='S') And (Count>1) Then                              {Del}
      Begin
        Delete(MainStr,CurXPos,1);
        GotoXY(X,Y);
        Write(MainStr,' ');
        Dec(Count);
        GotoXY(X-1+CurXPos,Y);
      End;
      If (C='R') Then                                            {Ins}
      Begin
        Ins:=Not Ins;
      End;
      GotoXY(X-1+CurXPos,Y);
    End  {End Extended Key}
    Else
    Begin

      If (C=#17) Then                           {^Q}
      Begin
        C:=ReadKey;
        If C=#0 Then
          C:=ReadKey
        Else
        If C in ['y','Y',#25] Then
        Begin
          MainStr[0]:=Chr(CurXPos-1);
          Count:=CurXPos;
          GotoXY(X,Y);
          Write(MainStr);
          Pad(MaxLets-Length(MainStr),32);
        End;
      End
      Else
      If (C=#27) Then
      Begin
        GotoXY(X,Y);
        Pad(MaxLets,32);
        MainStr:='';
        C:=#13;
      End
      Else
      If (C=#8) Then                     {Was BackSpace Presssed?}
      Begin
        If (CurXPos>1) Then              {Can I BackSpace?}
        Begin
          Delete(MainStr,CurXPos-1,1);   {Delete the char}
          GotoXY(X,Y);
          Write(MainStr,' ');            {Redisplay the String}
          Dec(Count);                    {One less char}
          Dec(CurXPos);                  {Move Back}
          GotoXY(X-1+CurXPos,Y);         {Goto Position}
        End;                             {End 'Can I BackSpace?'}
      End                                {End 'Was BackSpace Pressed?'}
      Else                               {No Not BackSpace - A Normal Letter}
        If (CurXPos<=MaxLets) And (C<>#13) Then    {Is there Space?}
        Begin
          If Ins Or (CurXPos>=Count) Then   {Must I Insert the Char?}
          Begin
            If Count<=MaxLets Then
              Begin
                Insert(C,MainStr,CurXPos);  {Insert the Char}
                Inc(Count);                 {Add 1 to Count}
                Inc(CurXPos);               {Move Cursor}
              End;                          {End Check for Space in String}
          End                               {End Check to see if Ins was True}
          Else                              {No, Do not Insert, Overwrite}
          Begin
            MainStr[CurXPos]:=C;      {Overwrite char}
            Inc(CurXPos);             {Move Cursor}
          End;                        {End Insert / Overwrite}

          If CurXPos<Count Then       {If the char was Inserted, Rewrite}
          Begin                       {the entire String to the screen}
            GotoXY(X,Y);
            Write(MainStr);
            GotoXY(X-1+CurXPos,Y);
          End                         {End Rewrite the String to the screen}
          Else                        {Need Not Rewrite the entire String}
             Write(C);                {Just Display the new char}
        End;
    End;                              {End Area which accepts a BackSpace or a Letter}
  Until C=#13;
End;

Function HexToDec(Hex:String):Word;

Var
  Temp  :Word;

Begin
  Temp:=0;
  UpperCase(Hex,Hex);
  If Hex[1] in ['0'..'9'] Then Temp:=Temp + (Ord(Hex[1])-Ord('0'))*16;
  If Hex[1] in ['A'..'F'] Then Temp:=Temp + (Ord(Hex[1])-Ord('A')+10)*16;
  If Hex[2] in ['0'..'9'] Then Temp:=Temp +  Ord(Hex[2])-Ord('0');
  If Hex[2] in ['A'..'F'] Then Temp:=Temp +  Ord(Hex[2])-Ord('A')+10;
  HexToDec:=Temp;
End;

Procedure CheckIntNumber(Var L:String;Var NewNumber:Boolean;
                         Var IntComment:String;Var IntCount:Word);

Const
  LastInt :Word = 65000;

Var
  DecStr  :String[4];
  DecNum  :Word;

Begin
  NewNumber:=False;
  IntComment:='';
  If Copy(L,1,4)='Int ' Then
  Begin
    Inc(IntCount);
    L[5]:=UpCase(L[5]);
    L[6]:=UpCase(L[6]);
    DecNum:=HexToDec(Copy(L,5,2));
    If (DecNum<>LastInt) And (DecNum<=240) And ((DecNum>=16) Or (DecNum=0)) Then
    Begin
      IntCount:=1;
      LastInt:=DecNum;
      Str(DecNum:3,DecStr);
      IntComment:='Interrupt '+Copy(L,5,2)+'h'+'  ('+DecStr+')';
      If DecNum=240 Then IntComment:=IntComment+' ^Bto^B FFh  (255)';
      If DecNum=  0 Then IntComment:=IntComment+' ^Bto^B 0Fh  ( 15)';
      NewNumber:=True;
    End;
    If (DecNum>240) Or ((DecNum<16) And (DecNum<>0)) Then IntComment:='$$NO$$';
  End;
  If Copy(L,1,19)='Please Redistribute' Then
  Begin
    IntComment:='Final Comments From Ralf';
    NewNumber:=True;
  End;
End;

Function NGOFName(FName:String):String;
Begin
  NGOFName:=Copy(FName,1,Pos('.',FName))+'NGO';
End;

Procedure NewMenuItem(Comment,FName:String);
Begin
  WriteLn(MenuLink,'   '+Comment+'  '+NGOFName(FName));
End;

Procedure NewBatchItem(Command:String);
Begin
  WriteLn(BatchJob,Command);
End;

Function NextOutputFileName:String;

Const
  Total   :Word = 0;

Var
  Temp  :String[3];

Begin
  Inc(Total);
  Str(Total,Temp);
  FormatVar(Temp,Temp,3,RightText);
  SpacesToZeros(Temp,Temp);
  NextOutputFileName:='RB'+Temp+'.';
End;

Procedure I(Var S:String);
Begin
  ReadLn(F,S);
End;

Procedure O(S:String);
Begin
  WriteLn(G,S);
End;

Procedure OLn;
Begin
  WriteLn(G);
End;

Procedure BoldEtc(StIn:String;Var StOut:String);

Var
  SpPos:Byte;

Begin
  StOut:=StIn;

  SpPos:=Pos('Desc:',StOut);
  If SpPos>0 Then
  Begin
    Delete(StOut,SpPos,5);
    Insert('^BDesc:^B',StOut,SpPos);
  End;

  SpPos:=Pos('Note:',StOut);
  If SpPos>0 Then
  Begin
    OLn;
    Delete(StOut,SpPos,5);
    Insert('^BNote:^B',StOut,SpPos);
  End;

  SpPos:=Pos('SeeAlso:',StOut);
  If SpPos>0 Then
  Begin
    OLn;
    Delete(StOut,SpPos,8);
    Insert('^BSee Also:^B',StOut,SpPos);
  End;

  SpPos:=Pos('Return:',StOut);
  If SpPos>0 Then
  Begin
    OLn;
    Delete(StOut,SpPos,7);
    Insert('^BReturn:^B',StOut,SpPos);
  End;

  SpPos:=Pos('Notes:',StOut);
  If SpPos>0 Then
  Begin
    OLn;
    Delete(StOut,SpPos,6);
    Insert('^BNotes:^B',StOut,SpPos);
  End;
End;

Procedure TabTo(StIn:String;Var StOut:String;TabSize:Byte);

Var
  SpPos:Byte;
  Spc  :String;

Begin
  StOut:=StIn;

  Repeat
    SpPos:=Pos(#9,StOut);
    If SpPos>0 Then
    Begin
      Delete(StOut,SpPos,1);
      PadVar('',Spc,TabSize - (SpPos Mod TabSize));
      Insert(Spc,StOut,SpPos);
    End;
  Until SpPos=0;
End;

Procedure LoadConvertList(FromFile:String;Var CList:ConvertType);

Var
  F     :Text;
  Cnt   :Word;
  St    :String;
  SpPos :Byte;

Begin
  FillChar(CList,SizeOf(CList),0);
  Cnt:=0;
  Assign(F,FromFile);
  Reset(F);
  If IOResult>0 Then Exit;
  While (Not EOF(F)) And (Cnt<99) do
  Begin
    Inc(Cnt);
    ReadLn(F,St);
    SpPos:=Pos('|',St);
    If SpPos>0 Then
    Begin
      If SpPos>11 Then SpPos:=11;
      CList[Cnt].IfThis:=Copy(St,1,SpPos-1);
      Delete(St,1,SpPos);
      CList[Cnt].ThenThis:=Copy(St,1,10);
    End;
  End;
  Close(F);
End;

Var
  UserStyle2    :String[20];    {Sub & Fn}
  UserStyle1    :String[20];    {Fn}
  UserStyle0    :String[20];    {Niether}
  PercentFn     :String[2];     {Function Number}
  PercentSubFn  :String[2];     {Sub Function Number}
  OtherCode     :String[9];     {Code after the Interrupt Number}

Procedure UserModify(Var S:String);

Var
  y, z  :Byte;
  c     :Byte;
  Style :String[20];

Begin
  If (PercentFn<>'  ') And (PercentSubFn<>'  ') Then
    Style:=UserStyle2
  Else
  If PercentFn<>'  ' Then
    Style:=UserStyle1
  Else
    Style:=UserStyle0;

  y:=Pos('%f',Style);
  z:=Pos('%s',Style);
  c:=Pos('%c',Style);

  If (y>0) Then
  Begin
    Delete(Style,y,2);
    Insert(PercentFn,Style,y);
  End;

  If (z>0) Then
  Begin
    Delete(Style,z,2);
    Insert(PercentSubFn,Style,z);
  End;

  If (c>0) Then
  Begin
    Delete(Style,c,2);
    Insert(OtherCode,Style,c);
  End;

  S:=S+Style;
End;

Const
  TabSize       = 4;
  ConvertFile   = 'CONVERT.TXT';
  MainRBFile    = 'RBINT';
  BatchFile     = 'CRB.BAT';
  NGC           = 'CALL NGC';
  NGML          = 'CALL NGML';

Var
  IntCount      :Word;
  Cnt           :LongInt;
  CodeLetter,
  C             :Char;
  TempLine,
  LastIntComment,
  IntComment    :String;
  RBDir         :String;
  OutDir        :String;
  NewNumber     :Boolean;
  IntLetter     :Char;
  IntListFile,
  FName         :String[12];
  LongCount     :Word;
  CList         :ConvertType;
  StopProc      :Boolean;

Procedure CapWords(StIn:String;Var StOut:String);

Var
  X      :Word;
  SpPos  :Byte;

Begin
  PasStr.CapWords(StIn,StOut);
  X:=1;
  While CList[X].IfThis<>'' do
  Begin
    SpPos:=Pos(CList[X].IfThis,StOut);
    If SpPos>0 Then
    Begin
      Delete(StOut,SpPos,Length(CList[X].IfThis));
      Insert(CList[X].ThenThis,StOut,SpPos);
    End;
    Inc(X);
  End;
End;

Var
  LastWasBlank  :Boolean;       {For CMOS Convert}

Begin
  PercentFn:='  ';
  PercentSubFn:='  ';
  SeeAlsoLine:='';

  RBDir:='';
  OutDir:='';
  StopProc:=False;
  IntLetter:='A';

  ClrScr;
  WriteLn('Ralf Brown''s Text Format to .NG Source Format               Version  1.16');
  WriteLn('Copyright (c) Michael Gallias, 1995');
  WriteLn;
  WriteLn('Note that this program does NOT convert directly to .NG format, it converts');
  WriteLn('the files to a new text format so that they can be compiled with the Norton');
  WriteLn('Guides Compiler.  You thus require the Norton Guides Compiler to convert the');
  WriteLn('files.  If you do not have this program, Ralf''s list is available in .NG');
  WriteLn('format already.  It should be at the same FTP site where you obtained this');
  WriteLn('file.');
  WriteLn;
  WriteLn('Also note that the process requires 16 megabytes of free disk space.');
  WriteLn('The program will run about 10 times faster if you use the SmartDrv write cache.');
  WriteLn('For further details, please see the documentation.');
  WriteLn;
  WriteLn('If you don''t want GLOSSARY.LST, PORTS.LST, 86BUGS.LST, CMOS.LST and MEMORY.LST');
  WriteLn('included, delete them before running this program and they will not be included');
  WriteLn('in the .NG file.');
  WriteLn;
  WriteLn('Copy your CONVERT.TXT file to the directory with the INTERUPT.? files.');
  WriteLn;
  WriteLn('* This program has only been tested on release 46, but it might work on other');
  WriteLn('  releases too.  If you find this program useful, please send me a postcard.');
  WriteLn;
  Write('Do you want to continue  (Y)es (N)o  ?');
  C:=UpCase(ReadKey);
  If C<>'Y' Then Halt;
  ClrScr;

  WriteLn('Specify the directory where this program and the original text files');
  WriteLn('are to be found.');
  WriteLn;
  EditString(1,WhereY,60,True,RBDir);
  If Length(RBDir)>2 Then
    If RBDir[Length(RBDir)]<>'\' Then RBDir:=RBDir+'\';
  WriteLn;
  WriteLn;
  WriteLn;
  WriteLn('Specify the output directory for the new text files which need compiling.');
  WriteLn;
  EditString(1,WhereY,60,True,OutDir);
  If Length(OutDir)>2 Then
    If OutDir[Length(OutDir)]<>'\' Then OutDir:=OutDir+'\';
  ClrScr;
  WriteLn('Select a style for the headings:');
  WriteLn;
  WriteLn('  xx is the Interrpt Number, yy the Function Number, zz is the Subfunction');
  WriteLn('  Number and cc are the code letters found after the Interrupt Number in');
  WriteLn('  Ralf''s List.  Format 2 is how it appears in Ralf''s List.');
  WriteLn;
  WriteLn('  1. Int xx Description');
  WriteLn('  2. Int xx cc - Description');
  WriteLn('  3. Int xx Fn yyzz cc - Description');
  WriteLn('  4. Int xx, yyzz (cc) - Description');
  WriteLn('  5. Int xxyyzz cc - Description');
  WriteLn;
  WriteLn('  U. User defined style');
  WriteLn;
  Repeat
    C:=UpCase(ReadKey);
  Until C in ['1','2','3','4','5','U'];
  If C<>'U' Then
    Case C Of
      '2': Begin
             UserStyle2:=' %c -';
             UserStyle1:=' %c -';
             UserStyle0:=' %c -';
           End;
      '3': Begin
             UserStyle2:=' Fn %f%s %c -';
             UserStyle1:=' Fn %f %c -';
             UserStyle0:=' %c -';
           End;
      '4': Begin
             UserStyle2:=', %f%s (%c) -';
             UserStyle1:=', %f (%c) -';
             UserStyle0:=' (%c) -';
           End;
      '5': Begin
             UserStyle2:='%f%s %c -';
             UserStyle1:='%f %c -';
             UserStyle0:=' %c -';
           End;
      Else
           Begin
             UserStyle2:='';
             UserStyle1:='';
             UserStyle0:='';
           End;
    End
  Else
  Begin
    ClrScr;
    WriteLn('Examples (don''t type the quotes):');
    WriteLn;
    WriteLn('  Int xx Description                       ""');
    WriteLn('  Int xx - Description                     " -"');
    WriteLn('  Int xx Fn yyzz cc - Description          " Fn %f%s %c -"');
    WriteLn('  Int xx, yyzz (cc) - Description          ", %f%s (%c) -"');
    WriteLn('  Int xx, Fn yy, SubFn zz -> Description   "Fn %f, SubFn %s ->"');
    WriteLn;
    WriteLn('Type in the style you would like, %f is the Function number, %s is the');
    WriteLn('Subfunction number.  What you type will be appended to the Int xx and');
    WriteLn('then a space followed by the description will follow it.');
    WriteLn;
    WriteLn('Note that when you type the %f and %s, they must be lower case!');
    WriteLn;
    WriteLn('Assuming a function and subfunction number do exist, enter the format:');
    WriteLn;
    Write('Int xx');
    EditString(WhereX,WhereY,18,False,UserStyle2);
    WriteLn;
    WriteLn;
    WriteLn('Assuming a function number do exists, but no subfunction, enter the format:');
    WriteLn;
    Write('Int xx');
    EditString(WhereX,WhereY,18,False,UserStyle1);
    WriteLn;
    WriteLn;
    WriteLn('Assuming no function and subfunction numbers exist, enter the format:');
    WriteLn;
    Write('Int xx');
    EditString(WhereX,WhereY,18,False,UserStyle0);
  End;
  ClrScr;
  WriteLn;
  WriteLn;
  WriteLn;
  WriteLn;
  WriteLn('Press any key to start the process or [Esc] to quit to DOS.');
  C:=ReadKey;
  If C=#27 Then Halt;
  ClrScr;
  WriteLn('Converting Ralf''s list:');
  WriteLn;

  LoadConvertList(RBDir+ConvertFile,CList);

  Assign(MenuLink,OutDir+MainRBFile);
  Rewrite(MenuLink);
  WriteLn(MenuLink,'!Name: Ralf Brown');
  WriteLn(MenuLink,'!Credits: Ralf Brown''s Interrupt List Converted by Michael Gallias');
  WriteLn(MenuLink,'!Menu: Lists');

  Assign(BatchJob,OutDir+BatchFile);
  Rewrite(BatchJob);
  WriteLn(BatchJob,'@Echo Off');

  Assign(F,RBDir+'INTERRUP.'+IntLetter);
  Reset(F);

  FName:=NextOutputFileName;
  NewBatchItem(NGC+' '+FName);
  NewMenuItem('Comments',FName);
  Assign(G,OutDir+FName);
  Rewrite(G);

  O('!Short: Credits');
  OLn;
  O('^UCredits^U');
  OLn;
  Repeat
    I(L);
    If Copy(L,1,5)<>'-----' Then O(L);
  Until Copy(L,1,5)='-----';
  OLn;
  O('This list was converted from the released text format to the');
  O('Norton Guides / Expert Help Popup format by Michael Gallias.');
  OLn;
  O('Michael Gallias');
  O('P O Box 51231');
  O('Musgrave Road');
  O('4062');
  O('South Africa');
  OLn;
  O('gallias@iafrica.com');
  OLn;

  Cnt:=1;
  Repeat
    Str(Cnt,L);
    L:='Ralf''s Comment '+L;
    O('!Short: '+L);
    OLn;
    O('^U'+L+'^U');
    OLn;
    Repeat
      I(L);
      If Copy(L,1,5)<>'-----' Then O(L);
    Until Copy(L,1,5)='-----';
    OLn;
    Inc(Cnt);
    CodeLetter:=L[9];
    Delete(L,1,10);
  Until L='00---------------------------------';

  Close(G);

  FName:=NextOutputFileName;
  NewMenuItem('Interrupts',FName);
  IntListFile:=FName;
  Assign(G,OutDir+IntListFile);
  Rewrite(G);
  OLn;
  NewBatchItem(NGC+' '+IntListFile);
  WriteLn;

  Cnt:=1;
  IntCount:=1;
  Repeat
    I(L);
    If Copy(L,1,3)='INT' Then
    Begin
      TempLine:=Copy(L,1,6);            {INT xx}
      TempLine[2]:='n';
      TempLine[3]:='t';                 {Int xx}
      Delete(L,1,6);                    {Delete 'INT xx' Part From L}
      OtherCode:=Copy(L,1,Pos('-',L));  {Get Code Letters and the '-'}
      Delete(L,1,Length(OtherCode));    {Get the int. description into L}
      Delete(OtherCode,Length(OtherCode)-1,2);  {Get rid of the ' -'}
      LowerCase(L,L);
      CapWords(L,L);                    {Set Caps Nicely}
      UserModify(TempLine);             {Append user Fn and SubFn style}
      L:=TempLine+L;                    {Append description}
    End
    Else
    Begin
      LowerCase(L,L);
      CapWords(L,L);
    End;

    CheckIntNumber(L,NewNumber,IntComment,IntCount);

    If (NewNumber) And (IntComment<>'$$NO$$') Then
    Begin
      LastIntComment:=IntComment;
      Close(G);
      Assign(G,OutDir+IntListFile);
      Append(G);
      FName:=NextOutputFileName;
      O('!Short: '+IntComment);
      O('!File:'+NGOFName(FName));
      OLn;
      Close(G);
      NewBatchItem(NGC+' '+FName);
      Assign(G,OutDir+FName);
      Rewrite(G);
    End;

    If IntCount>200 Then
    Begin
      IntCount:=1;
      Close(G);
      Assign(G,OutDir+IntListFile);
      Append(G);
      FName:=NextOutputFileName;
      O('!Short: '+LastIntComment+'  ^B(Cont.)^B');
      O('!File:'+NGOFName(FName));
      OLn;
      Close(G);
      NewBatchItem(NGC+' '+FName);
      Assign(G,OutDir+FName);
      Rewrite(G);
    End;

    GotoXY(1,WhereY-1);
    Write('                                                                               ');
    GotoXY(1,WhereY);
    WriteLn(Cnt,' ',Copy(L,1,60));
    O('!Short: '+Copy(L,1,76));
    OLn;
    If Copy(L,1,3)='Int' Then
    Begin
      TempLine:=Copy(L,1,73);
      FormatVar(TempLine,TempLine,73,LeftText);
      TempLine:='^U'+TempLine+'^U  [^B'+CodeLetter+'^B]';
    End
    Else
      TempLine:='^U'+Copy(L,1,76)+'^U';
    O(TempLine);
    OLn;
    IntComment:=L;
    LongCount:=0;
    Repeat
      I(L);
      BoldEtc(L,L);
      TabTo(L,L,TabSize);
      Inc(LongCount,Length(L));

      If (LongCount>11500) And (Copy(L,1,5)<>'-----') Then
      Begin
        Inc(IntCount);
        LongCount:=0;
        OLn;
        O('^B.NG limit reached, continued in next section...^B');
        OLn;
        O('!Short: '+IntComment+'  ^B(Cont.)^B');
        OLn;
        O('^U'+IntComment+'  ^B(Cont.)^B');
        OLn;
      End;

      If Copy(L,1,5)<>'-----' Then
        O(L);

    Until (Copy(L,1,5)='-----') Or (EOF(F));
    CodeLetter:=L[9];
    PercentFn:=Copy(L,13,2);
    PercentSubFn:=Copy(L,15,2);
    If PercentFn='--' Then PercentFn:='  ';
    If PercentSubFn='--' Then PercentSubFn:='  ';
    OLn;
    Inc(Cnt);

    If EOF(F) Then
    Begin
      Close(F);
      IntLetter:=Chr(Ord(IntLetter)+1);
      Assign(F,RBDir+'INTERRUP.'+IntLetter);
      Reset(F);
      If IOResult=0 Then
      Begin
        ReadLn(F);
        ReadLn(F);
        ReadLn(F);
      End
      Else
        StopProc:=True;
    End;

  Until StopProc;

  Close(G);

  {End Interrupts}

  {Check For Glossary}

  Assign(F,RBDir+'GLOSSARY.LST');
  Reset(F);
  If IOResult=0 Then
  Begin
    I(L);
    I(L);
    I(L);
    I(L);
    Cnt:=1;
    FName:=NextOutputFileName;
    NewMenuItem('Glossary',FName);
    IntListFile:=FName;
    Assign(G,OutDir+IntListFile);
    Rewrite(G);
    OLn;
    NewBatchItem(NGC+' '+IntListFile);

    Repeat
      GotoXY(1,WhereY-1);
      Write('                                                                               ');
      GotoXY(1,WhereY);
      WriteLn(Cnt,' ',Copy(L,1,60));
      O('!Short: '+Copy(L,1,76));
      OLn;
      TempLine:='^U'+Copy(L,1,76)+'^U';
      O(TempLine);
      OLn;
      Repeat
        I(L);
        BoldEtc(L,L);
        TabTo(L,L,TabSize);
        If L<>'' Then O(L);
      Until (L='') Or (EOF(F));
      OLn;
      If Not EOF(F) Then I(L);
      Inc(Cnt);
    Until EOF(F);

    Close(F);
    Close(G);
  End;

  {End Check For Glossary}

  {Check For Low Memory}

  Assign(F,RBDir+'MEMORY.LST');
  Reset(F);
  If IOResult=0 Then
  Begin
    I(L);
    I(L);
    I(L);
    I(L);
    Cnt:=1;
    FName:=NextOutputFileName;
    NewMenuItem('Memory',FName);
    IntListFile:=FName;
    Assign(G,OutDir+IntListFile);
    Rewrite(G);
    OLn;
    NewBatchItem(NGC+' '+IntListFile);

    Repeat
      GotoXY(1,WhereY-1);
      Write('                                                                               ');
      GotoXY(1,WhereY);
      If (L[Length(L)]=':') Then Delete(L,Length(L),1);
      WriteLn(Cnt,' ',Copy(L,1,60));
      O('!Short: '+Copy(L,1,76));
      LastIntComment:=Copy(L,1,68);
      OLn;
      TempLine:='^U'+Copy(L,1,76)+'^U';
      O(TempLine);
      OLn;
      I(L);
      IntCount:=1;
      Repeat
        BoldEtc(L,L);
        If L<>'' Then O(L);
        If Not EOF(F) Then I(L);
        TabTo(L,L,TabSize);

        {Check for >12kb entries}

        Inc(IntCount);
        If IntCount>200 Then
        Begin
          O('!Short: '+LastIntComment+'  ^B(Cont.)^B');
          OLn;
          TempLine:='^U'+LastIntComment+'  ^B(Cont.)^B';
          O(TempLine);
          OLn;
          IntCount:=1;
        End;

      Until (Copy(L,1,9)='Format of') Or (EOF(F));
      OLn;
      Inc(Cnt);
    Until EOF(F);

    Close(F);
    Close(G);
  End;

  {End Check For Low Memory}

  {Check For Ports}

  Assign(F,RBDir+'PORTS.LST');
  Reset(F);
  If IOResult=0 Then
  Begin
    Cnt:=1;
    FName:=NextOutputFileName;
    NewMenuItem('Ports',FName);
    IntListFile:=FName;
    Assign(G,OutDir+IntListFile);
    Rewrite(G);
    OLn;
    NewBatchItem(NGC+' '+IntListFile);

    Repeat

      If Cnt>200 Then   {File too long for one NGO file}
      Begin
        Cnt:=1;
        FName:=NextOutputFileName;
        NewMenuItem('More Ports',FName);
        IntListFile:=FName;
        Close(G);
        Assign(G,OutDir+IntListFile);
        Rewrite(G);
        OLn;
        NewBatchItem(NGC+' '+IntListFile);
      End;

      Repeat
        I(L)
      Until L<>'';

      TabTo(L,L,TabSize);
      GotoXY(1,WhereY-1);
      Write('                                                                               ');
      GotoXY(1,WhereY);
      WriteLn(Cnt,' ',Copy(L,1,60));
      O('!Short: '+Copy(L,1,76));
      OLn;
      TempLine:='^U'+Copy(L,1,76)+'^U';
      O(TempLine);
      OLn;
      I(L);
      Repeat
        BoldEtc(L,L);
        If Copy(L,1,9)<>'---------' Then O(L);
        If Not EOF(F) Then I(L);
        TabTo(L,L,TabSize);
      Until (Copy(L,1,9)='---------') Or (EOF(F));
      OLn;
      Inc(Cnt);
    Until EOF(F);

    Close(F);
    Close(G);
  End;

  {End Check For Ports}

  {Check For CMOS}

  Assign(F,RBDir+'CMOS.LST');
  Reset(F);
  If IOResult=0 Then
  Begin
    Cnt:=1;
    FName:=NextOutputFileName;
    NewMenuItem('CMOS',FName);
    IntListFile:=FName;
    Assign(G,OutDir+IntListFile);
    Rewrite(G);
    OLn;
    NewBatchItem(NGC+' '+IntListFile);

    I(L);
    While (L='') And Not EOF(F) do
      I(L);

    TabTo(L,L,TabSize);
    UnPadVar(L,L);
    Repeat
      GotoXY(1,WhereY-1);
      Write('                                                                               ');
      GotoXY(1,WhereY);
      WriteLn(Cnt,' ',Copy(L,1,60));
      O('!Short: '+Copy(L,1,76));
      LastIntComment:=Copy(L,1,68);
      OLn;
      TempLine:='^U'+Copy(L,1,76)+'^U';
      O(TempLine);
      OLn;
      If L='' Then LastWasBlank:=True Else LastWasBlank:=False;
      I(L);
      IntCount:=0;
      Repeat
        Inc(IntCount);
        If (IntCount>250) And LastWasBlank And (Copy(L,1,7)<>'       ') Then
        Begin
          O('!Short: '+LastIntComment+'  ^B(Cont.)^B');
          OLn;
          TempLine:='^U'+LastIntComment+'  ^B(Cont.)^B';
          O(TempLine);
          OLn;
          IntCount:=1;
        End;

        BoldEtc(L,L);
        If Not ((Copy(L,1,7)='       ') And (LastWasBlank)) Then O(L);
        If L='' Then LastWasBlank:=True Else LastWasBlank:=False;
        If (Not EOF(F)) And (Not ((Copy(L,1,7)='      ') And (LastWasBlank))) Then I(L);
        TabTo(L,L,TabSize);
      Until ((Copy(L,1,7)='       ') And (LastWasBlank)) Or (EOF(F));
      If Not EOF(F) Then UnPadVar(L,L);
      OLn;
      Inc(Cnt);
    Until EOF(F);

    Close(F);
    Close(G);
  End;

  {End Check For CMOS}

  {Check For 86BUGS}

  Assign(F,RBDir+'86BUGS.LST');
  Reset(F);
  If IOResult=0 Then
  Begin
    Cnt:=1;
    FName:=NextOutputFileName;
    NewMenuItem('86 Bugs',FName);
    IntListFile:=FName;
    Assign(G,OutDir+IntListFile);
    Rewrite(G);
    OLn;
    NewBatchItem(NGC+' '+IntListFile);

    I(L);
    Repeat
      While (L='') And Not EOF(F) do
        I(L);

      GotoXY(1,WhereY-1);
      Write('                                                                               ');
      GotoXY(1,WhereY);
      WriteLn(Cnt,' ',Copy(L,1,60));
      O('!Short: '+Copy(L,1,76));
      OLn;
      TempLine:='^U'+Copy(L,1,76)+'^U';
      O(TempLine);
      OLn;
      I(L);
      Repeat
        BoldEtc(L,L);
        If Pos(':',Copy(L,1,9))=0 Then O(L);
        If Not EOF(F) Then I(L);
        TabTo(L,L,TabSize);
      Until (Pos(':',Copy(L,1,9))>0) Or (EOF(F));
      OLn;
      Inc(Cnt);
    Until EOF(F);

    Close(F);
    Close(G);
  End;

  {End Check For 86BUGS}


  NewBatchItem(NGML+' '+MainRBFile);

  Close(MenuLink);
  Close(BatchJob);

  ClrScr;
  WriteLn('Complete.');
  WriteLn;
  WriteLn('Now, go to the output directory and type CRB to compile the database.');
  WriteLn('The database will be around 4 megabytes when complete.');
  WriteLn;
  WriteLn('Make sure the NGC (Norton Guides Compiler) and the NGML (Norton Guides');
  WriteLn('Menu Linker) programs are on the path (or setup a batch file).');
  WriteLn;
End.
