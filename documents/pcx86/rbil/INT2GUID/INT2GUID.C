/* INT2GUID.C
 *
 * from:
 * INT2QH.C
 *
 * Author:   Kai Uwe Rommel
 * Date:     Sun 07-Oct-1990
 * Update:   Sat 20-Oct-1990
 * Update:   Sun 11-Nov-1990  Ralf Brown
 *
 * Compiler: MS C 5.00 and newer / compact model, or TC 2.0 / compact model
 * System:   PC/MS-DOS 3.20 and newer, OS/2 1.0 and newer
 *
 *
 * INT2GUID.C is a GUIDE/MAKEHELP version of INT2QH.C. GUIDE and MAKEHELP
 * are programs for pop-up help included the TurboPower Software package
 * Turbo Professional.
 *
 * Transscriptor:	Bent Lynggaard
 * Date:	1.00	Sun 24-Mar-1991
 * Update:	1.01	Tue 02-Apr-1991	- test '!', ';' in line pos 1.
 *					- test disk full
 *		1.02	Sun 14-Apr-1991	- smaller index pages
 *					- main index always leads to start of
 *					  an INT #
 *		1.03	Sun 12-May-1991	- configuration file.
 *		1.04	Sat 18-May-1991 - conditional mask in *.cfg
 *		1.05	Sun 29-Dec-1991 - fixed \n bug in configure()
 *		1.06	Sun 09-May-1992 - adjusted for change in file format
 *					- "dividerline" info as headings
 *					- all registers can carry parameters
 *		1.07	Sat 19-Dec-1992 - fixed bug (reading from closed file)
 *					- "dividerline" info as topics
 *					- "dividerline" char 9 function info
 *					- new subtopic criteria
 *					- program initialization in
 *					    configuration file
 *					- splitting up long topics
 *		1.08	Sun 04-Apr-1993 - topic # in "Missing divider line"
 *					    to ease manual editing
 *		1.09	Sat 03-Jul-1993 - fixed bug introduced in v. 1.07
 *		1.10    Sat 19-Mar-1994 - [no]filter and help options
 *
 * This program creates output to the standard output device. The output
 * should be redirected to a file INTERRUP.TXT. The created file should
 * be compiled by the TurboPower MAKEHELP program to a INTERRUP.HLP file,
 * which can be interpreted by the TurboPower GUIDE TSR program:
 *	INT2GUID > [ramdisk:]INTERRUP.TXT
 *	MAKEHELP [ramdisk:INTERRUPT] INTERRUP[.HLP] /Q
 *	GUIDE INTERRUP	(or enter GUIDE with a hot key, press F3,
 *			enter INTERRUP)
 *
 * TurboPower Software supplies a program called POPHELP in their Object
 * Professional package, which is a successor to GUIDE. INT2GUID has
 * facilities for conditional interpretation of supplementary files, so
 * these files can include code optimized for both GUIDE and POPHELP, and
 * the parts compiled depends on a mask defined in the configuration file.
 *
 * The following is considered in creating the topic (and popup window)
 * headers:
 * The first word in the header is the interrupt number, so that GUIDE's
 * search mechanism can find the entry if the hot key is pressed when
 * the cursor is at an interrupt number.
 * MAKEHELP restricts the (length of longest header + 1) times the number
 * of topics to 64 kB. INTER191 had about 2200 topics, so the length of
 * the headers should be limited to 25 characters. However, rather than
 * truncating the INTERRUP.LST header lines to some nonsense, this
 * program uses only the interrupt number as topic headings, plus the
 * AH or AX values where applicable.
 * (v. 1.06: "divider line" info (e.g. "214C" in "--------214C------...")
 * is used for headings, thus allowing a more selective search by GUIDE's
 * cursor-word search.)
 * The main index references some subindeces. The subindeces use the
 * MAKEHELP cross reference facility. MAKEHELP limits the number of cross
 * references to 50 per topic, however, this program limits each subindex
 * to 18 entries, so each "topic" can be shown on one single screen with
 * height 20 lines. For each interrupt number, the entries are temporarily
 * stored, and written to the current subindex page only if all entries
 * for the interrupt number fit on the page.
 *
 * MAKEHELP's text wrapping mechanism is disabled, and as the active
 * window is limited to 76 characters, some lines are missing one or two
 * characters.
 * The amount of text that can be displayed per topic is limited by
 * GUIDE's setting of pages/topic (default = 20) and the screen height
 * defined when GUIDE was initialized.
 *
 */

#define LABEL    "int2guid.c"
#define VERSION  "1.10"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#define divider_line(s) (strncmp(s,"--------",8)==0)
#define maxIndeces 18
  /* max 50, 18 gives one page with height 20 (18 active lines) */
#define mainIndex 200
  /* 1-99 reserved for program, 100-199 reserved for user */
/* NB! The value 200 is used as text in main() after Topic 2 and in
   file INT2GUID.REF.
*/
#define false 0
#define true 1

FILE *input, *output, *topics, *subtopics, *config;

char line1[128];
char line2[128];
char configline[128];
char tempBuffer[50 * 128];
char *tempPtr;
char category[4] = "--";
char nextHeader[16] = "??"; /* v. 1.07: 16 rather than 14 */
char infilename[14] = "interrup.lst";
#define infileExt 9
int splitInfile = 0;
int classification = 0;
int WIDTH = 80;
  /* WIDTH is the screen with for GUIDE/POPHELP. 80 is the best choice for
     GUIDE, 78 is the best choice for POPHELP (which does not count the
     frame as a part of the screen). The configuration file can change
     this value. v. 1.07.
  */
long topicStart = 0; /* v. 1.07 */
unsigned maxTopicLength = 32000; /* v. 1.07 */
  /* texts longer than maxTopicLength are split into two or more topics.
     The configuration file can change this value.
  */
char currentHeader[16]; /* v. 1.07 */

char configfile[14] = "int2guid.cfg";
char configmarker[18] = "INT2GUIDE CONFIG";

char missingFile[] = "Missing include file.";

int sub = 0, indexed = 1;
int filter = 1; /* v. 1.10, suggest filtering */
char filterFileName[120] = ""; /* v. 1.10 */
FILE *filterFile; /* v. 1.10 */
unsigned currentID = 1, activeID = 1, indeces = 0, indexNo = 0, buffered = 0,
  subindeces, activeSub, mask;
int headerlength; /* v. 1.07 */
unsigned reservedID = mainIndex; /* v. 1.07 */
  /* reservedID reserves some topic numbers for long texts that are split
     into more than one topic. currentID must then be incremented via a
     function call in order to skip the reserved topics.
  */

void usage(void) /* v. 1.10 */
{
  fputs(
  "\n"
  "INT2GUID transcribes information in Ralf Brown's Interrupt files to input for\n"
  "TurboPower Software's MAKEHELP program for the GUIDE or POPHELP TSR programs.\n"
  "\n"
  "Use one of the forms:\n"
  "    INT2GUID -?                 displays this help\n"
  "    INT2GUID -nofilter          for a transcription of the entire list\n"
  "    INT2GUID -f<filter file>    for a partial transcription\n"
  "\n"
  "INT2GUID reads input from one input file INTERRUP.LST, or from multiple input\n"
  "files INTERRUP.A and successive extensions .B, .C, ..., and writes output to\n"
  "stdout. The output can be redirected to a file.\n"
  "\n"
  "The program requires either the parameter \"-nofilter\" to specify that the\n"
  "transcription includes all the information in Ralf Brown's Interrupt List, or\n"
  "\"-f\" immediately followed by the name of an INTPRINT filter file to specify a\n"
  "partial transcription. The information is used to include the right copyright\n"
  "information in the program's output. The contents of a filter file is included\n"
  "in the output.\n"
  , stderr);
  exit(0);
} /* usage */

void exitfunc(void)
{
  fcloseall();
  unlink("topic.tmp");
  unlink("subtopic.tmp");
}

void errorexit(char *msg)
/* writes msg to stderr and exits with error code 1 */
{
  fputs(msg, stderr);
  fputs("\n", stderr);
  exit(1);
} /* errorexit */

void explain(char *s)
{
  fputs("\7\n", stderr);
  fputs(s, stderr);
  errorexit("\n\nUse \"INT2GUID -?\" for help.");
} /* explain */

void diskFull(int temporary)
/* reports disk full and exits */
{
  char msg[80];
  sprintf(msg,"\n\nDisk full, %s file\n", temporary ? "temporary" : "output");
  errorexit(msg);
} /* diskFull */


int _fputs(char *line, FILE *stream)
/* filters TABs to spaces, and inserts a leading space in lines starting
   with the MAKEHELP command and comment characters '!' and ';'. "_fputs"
   should be used when copying from unknown sources. Use "fputs" when
   copying files with information specifically for this program.
*/
{
  char buffer[128];
  int cnt = 0;

  if ( (*line=='!') || (*line==';') ) /* MAKEHELP command/comment? */
    buffer[cnt++] = ' '; /* start with a space */

  while ( *line )
  {
    switch ( *line )
    {
      case '\t': do buffer[cnt++] = ' '; while ( cnt & 7 ); break;
			/* MAKEHELP does not interpret tabs */
      default  : buffer[cnt++] = *line;
    }
    line++;
  }

  buffer[cnt] = 0;

  if ( (cnt = fputs(buffer, stream)) == EOF )
    diskFull(stream != output);

  return cnt;
}

char *_fgets(char *s, int n, FILE *stream)
{
  char *ptr;
  ptr = fgets(s, n, stream);
  if ( (ptr==NULL) && (stream==input) ) /* v. 1.09: edited */
  {
    fclose(input); /* 1.09: also unsplit file must be closed */
    input=NULL;
    if ( splitInfile )
    {
      infilename[infileExt]++;
      input = fopen(infilename, "r");
      if ( input != NULL )
      {
	fprintf(stderr, "%s\n", infilename);
	ptr = fgets(s, n, input);
      }
    }
  }
  return ptr;
} /* _fgets */

void Initialize(void)
{
  input     = fopen(infilename, "r");
  if ( input == NULL )
  {
    infilename[infileExt] = 'a';
    infilename[infileExt+1] = 0;
    input = fopen(infilename, "r");
    if ( input == NULL )
    {
      fputs("Cannot open input file (INTERRUP.LST or INTERRUP.A)\n", stderr);
      exit(1);
    }
    splitInfile = 1;
  }
  fprintf(stderr, "%s\n", infilename);
  output    = stdout;
  topics    = fopen("topic.tmp", "w");
  subtopics = fopen("subtopic.tmp", "w");

  tempPtr = tempBuffer;

  fprintf(output,
    ";INTERRUPT help text for MAKEHELP/GUIDE.\n;\n!WIDTH %u\n;\n",WIDTH);
    /* v. 1.07: WIDTH  rather than constant 80. WIDTH is initialized to 80
       and can be changed in the configuration file.
    */
  fprintf(topics, "!TOPIC 1 Interrupt List\n!INDEX %u\n", mainIndex);
}

int incrementID(void)
/* v. 1.07: introduced in order to skip reserved IDs when incrementing currentID */
{
  ++currentID;
  if (currentID == mainIndex)
    currentID = reservedID;
  return currentID;
} /* incrementID */

void testTopic(void) /* limit xrefs/topic to maxIndeces */
{
  if ( indeces+buffered >= maxIndeces ) /* leave one entry for forw. ref */
  {
    incrementID();
    fprintf(topics, "\004%u\005INT %s\005 (index continued)\n"
      "!TOPIC %u INT %s (cont)\n!INDEX %u\n"
      "(continued \004%u\005from\005)\n",
      currentID, category, currentID, category, ++indexNo, activeID);
    indeces = 1; /* the backwards ref */
    activeID = currentID;
  }
} /* testTopic */

void copyBuffer(void)
{
  if ( buffered == 0 )
    return;

  testTopic();
  if ( fputs(tempBuffer, topics) == EOF )
      diskFull(true);
  indeces += buffered;
  buffered = 0;
  tempPtr = tempBuffer;
} /* copyBuffer */

void Cleanup(void)
{
  copyBuffer();
  fclose(topics);
  fclose(subtopics);
  fputs("Cleaning up\n", stderr);

  topics = fopen("topic.tmp", "r");
  subtopics = fopen("subtopic.tmp", "r");

  while ( fgets(line1, sizeof(line1), topics) )
    if ( fputs(line1, output) == EOF )
      diskFull(false);

  while ( fgets(line1, sizeof(line1), subtopics) )
    if ( fputs(line1, output) == EOF )
      diskFull(false);
} /* Cleanup */

void putAndCount(int putFunc(), char *line)
/* split topic if maxTopicLength is exceeded. v. 1.07 */
{
  int ID, rID;
  if ((ftell(output) - topicStart) > maxTopicLength)
  {
    ID = currentID;
    rID = (reservedID > currentID) ? reservedID++ : ++currentID;
    if (fprintf(output,"\004%u\005(text continues)\005\n"
      "!TOPIC %u %s\n!NOINDEX\n"
      "\004%u\005(text continued from)\005\n",
      rID, rID, currentHeader, ID) == EOF)
	diskFull(false);
    topicStart = ftell(output);
  }
  if (putFunc(line, output) == EOF)
    diskFull(false);
} /* putAndCount */

int CopyFile(char *name, int commands)
/* copies a file to the database, returns 0 for success or 1 for error */

/* If commands!=0, also interprets lines starting with "!! <number>" as
   an update to variable "condition", and copies lines to the database
   only if condition == 0 or (condition & mask) != 0
*/
{
  int condition = 0;
  FILE *temp = fopen(name, "r");
  char s[128];
  fprintf(stderr, "%s\n", name);
  if ( temp == NULL )
  {
    fprintf(stderr, "WARNING: Could not open %s\n", name);
    fputs("Information was not available\n", output);
    return 1;
  }
  else
  {
    while ( fgets(line2, sizeof(line2), temp) )
      if ( !commands )
	putAndCount(_fputs, line2);
      else
	/* does line start with "!! <number>" ? */
	if ( sscanf(line2, "!!%i", &condition) != 1 )
	  /* yes: condition updated, sscanf returns 1 */
	  if ( (condition==0) || (condition & mask) )
	  {
	    if (sscanf(line2, "!%s", s) == 1)
	      if (strcmp(strupr(s), "TOPIC") == 0)
	        topicStart = ftell(output);
	    putAndCount(fputs, line2);
	  }
    fputs("!NOWRAP\n", output); /* in case it was left in !WRAP state */
    fclose(temp);
    return 0;
  }
} /* CopyFile */

void testTemp(void)
/* v. 1.06: allow no more than 50 entries in tempBuffer */
/* v. 1.07: allow no more than 48 entries in tempBuffer */
{
  if (buffered >= 48)
  {
    copyBuffer();
    fprintf(stderr,"INT %s has more than 48 subtopics and therefore more than one entry\n"
      "in the main index (topic %u).\n", category, currentID);
  }
} /* testTemp */

void testSubtopic(char *marker)
{
  if ( ++subindeces >= maxIndeces )
  {
    testTemp();
    sprintf(tempPtr, "\004%u\005%s\005  (list cont.)\n",
      incrementID(), marker);
    tempPtr += strlen(tempPtr);
    buffered++;
    fprintf(subtopics,
      "\004%u\005%s\005  (list cont.)\n!TOPIC %u %s (list cont)\n!NOINDEX\n"
      "(continued \004%u\005from\005)\n",
      currentID, marker, currentID, category, activeSub);
      activeSub = currentID;
    subindeces = 2;
  }
} /* testSubtopic */


void StartTopic(char *header, char *marker, char *desc)
{
  topicStart = ftell(output); /* v. 1.07 */
  strncpy(currentHeader, header, sizeof(currentHeader));
  currentHeader[sizeof(currentHeader)-1] = 0;
  if (sub)
  {
    testSubtopic(marker);
    if ( fprintf(subtopics, "\004%u\005%s\005  %s",
      incrementID(), marker, desc) == EOF )
	diskFull(true);
    if (fprintf(output, "\004%u\005INT %s\005 (continued)\n",
      currentID, category) == EOF)
        diskFull(false);
    /* insert a reference to this one in the former topic */
  } /* if (sub) */
  else
  {
    testTemp();
    sprintf(tempPtr, "\004%u\005%s\005  %s", incrementID(), marker, desc);
    tempPtr += strlen(tempPtr);
    buffered++;
  } /* else */

  fprintf(output, "!TOPIC %u %s\n", currentID, header);
  if ( indexed )
    indexNo++;
  fprintf(output, indexed ? "!INDEX %u\n" : "!NOINDEX\n", indexNo);
} /* StartTopic */

void StartList(void)
/* v. 1.07: reorganized and edited */
{
  fprintf(subtopics, "!TOPIC %u %s (list)\n!NOINDEX\n", incrementID(), category);
  if (fputs(tempBuffer, subtopics) == NULL)
    diskFull(true); /* copy one entry in buffer to subtopics */
  sub = 1;
  subindeces = 1;
  activeSub = currentID;
  tempPtr = tempBuffer; /* reset buffer pointer */
  buffered = 1; /* the entry we are going to use now */
  sprintf(tempPtr, "\004%u\005%s\005  (list)\n", currentID, category);
  tempPtr += strlen(tempPtr);
} /* StartList */

/* void EndList(void) - not used */

/* char *NextID(void) - not used */

int RecognizedTopic(void)
{
/* v. 1.07: revised to use newheader info for marker string rather than
   interpreting lines 1 and 2, and to use subtopics when there is more
   than one entry rather than when there are entries with parameters.
*/
  char *ptr, *pdesc, topic[4], marker[20];

  if (input == NULL)
    return 0; /* v. 1.07: check input == NULL rather than read second line */

  if ( (pdesc = strchr(line1, '-')) == NULL )
    pdesc = "(description not found)\n";

  if (headerlength==0) /* if info was missing in the dividerline */
  { /* take INT # from line1[4]-[5] */
    strncpy(nextHeader, &line1[4], 2);
    nextHeader[2] = '\0';
    fprintf(stderr,"Missing divider line info in topic %u:\n%s",
      currentID, line1); /* 1.08: edited */
  }
  strncpy(topic, nextHeader, 2); /* interrupt number */
  topic[2] = '\0';

  if ( strcmp(category, topic) )
  {
    sub = 0;
    copyBuffer();
    strcpy(category, topic);
    fprintf(stderr, "%s\015", topic); /* show progress */
  }
  else
  {
    if (sub==0) /* v. 1.07 */
      StartList();
    /* v. 1.07: insert reference was moved to StartTopic */
  }

  strcpy(marker, nextHeader); /* v. 1.07: use nextHeader for marker */
  /* nextheader format: IIAHALXXNNNN_F (_F only if headerlength<0 */
  /* marker format: II AHAL XXNNNN F */
  if (headerlength < 0)
  {
    headerlength = abs(headerlength);
    marker[headerlength-2] = ' '; /* '_' to space */
  }

  if (headerlength > 2)
  {
    for (ptr = marker+headerlength+1; ptr >= &marker[2]; ptr--)
      ptr[1] = *ptr;
    /* memcpy(&marker[3], &marker[2], headerlength - 1);
       did not work properly (compiler direction handling error)
    */
    marker[2] = ' ';
    if (headerlength > 6+2)
    {
      for (ptr = marker+headerlength+2; ptr >= &marker[7]; ptr--)
	ptr[1] = *ptr;
      /* memcpy(&marker[8], &marker[7], headerlength - 5);
        again. compiler error
      */
      marker[7] = ' ';
      ptr = &marker[6];
      while (*ptr == '_')
	*ptr-- = ' '; /* spaces for AL or AX if unused */
    } /* if (headerlength > 6+2) */
  } /* if (headerlength > 2) *

/* v. 1.06: use global "nextHeader" rather than local "header" */
/* v. 1.07: local "header" deleted */
  StartTopic(nextHeader, marker, pdesc);

  _fputs(line1, output);

  return 1;
} /* RecognizedTopic */

void CopyTopic(void)
{
/* v. 1.07: edited to split long texts into two or more topics */
  char *ptr, *ptr2;

  for (;;)
  {
    if ( _fgets(line1, sizeof(line1), input) == NULL )
      break;

    if ( !divider_line(line1) )
      putAndCount(_fputs, line1);
    else
    {
      if ( _fgets(line2, sizeof(line2), input) == NULL )
	break;

      if ( strncmp(line2, "INT ", 4) )
      {
	putAndCount(_fputs, line1);
	putAndCount(_fputs, line2);
      }
      else
      {
	/* v. 1.06: store divider line info as a header */
	/* v. 1.07: edited */
	strncpy(nextHeader, line1+10, 12);
	for (ptr=nextHeader+11; *ptr=='-'; ptr--)
	  ;
	if (ptr>&nextHeader[4])
	  for (ptr2=&nextHeader[2]; ptr2<ptr && ptr2<&nextHeader[6]; ptr2++)
	    if (*ptr2 == '-')
	      *ptr2 = '_';
	headerlength = ptr - nextHeader + 1;
	if (classification && line1[8]!='-')
	{
	  *++ptr='_'; /* add char. 9 function classification */
	  *++ptr=line1[8];
	  headerlength = -headerlength-2;
	}
	*++ptr=0;
	strcpy(line1, line2);
	break;
      } /* else */
    } /* else */
  } /* for (;;) */
} /* CopyTopic */

void configError(void)
{
  errorexit("\nFormat error in configuration file.\n");
} /* configError */

void readconfig(void)
/* reads one line from file config to configline */
{
  if ( fgets(configline, sizeof(configline), config) == NULL )
    configError();
} /* readconfig */

void openconfig(void)
/* opens configuration file and reads the initial part up to a line starting
   with "=". This code defines how the initial lines are interpreted.
   v. 1.07 defines:
   configline[0] == '=': end of initial part
   configline[0] == ';': comment
   configline[0] == 'W': assign value to WIDTH
   configline[0] == 'M': assign value to maxTopicLength
   configline[0] == 'C': assign true to classification
   The definitions are case sensitive.
*/
{
  int confv, confsubv;
  char dummy[128];
  config = fopen(configfile, "r");
  if ( config == NULL )
  {
    fputs("\nWarning: No configuration file.\n", stderr);
    return;
  }
  readconfig();
  if (strncmp(configline, configmarker, strlen(configmarker)))
    configError();
  readconfig();
  if (sscanf(configline, "%u%u", &confv, &confsubv) < 2)
    configError();
  if ((confv = ((confv << 8) + confsubv)) < 0x104)
    errorexit ("\nThe configuration file is incompatible with this"
    " version of INT2GUID");
  if (confv < 0x107)
    return;
  while (!feof(config))
  {
    readconfig();
    switch (configline[0])
    {
      case '=': return; /* done */
      case ';': break; /* comment */
      case 'W':
      case 'M':
	if ( sscanf(configline, "%s%u", &dummy,
	  configline[0]=='W' ? &WIDTH : &maxTopicLength) < 2 )
	  configError();
	break;
      case 'C': classification = true; break; /* include classification */
      default: fprintf(stderr, "\nWARNING: Error in configuration file:\n%s",
	configline);
    } /* switch */
  } /* while */
} /* openconfig */

void copyline(char *str, int len)
/* copies configline (after deleting the terminating '\n') to str
	for max len characters. */
{
  configline[strlen(configline)-1] = 0; /* ignore '\n' */
  strncpy(str, configline, len);
  str[len] = 0; /* edited: v. 1.05 */
} /* copyline */

void configure(void)
/* parses configuration file */
{
#define maxHeader 14
#define markerLen 12
  int command, extraTopics, i;
  char header[(maxHeader+2) & 0xFE], marker[(markerLen+2) & 0xFE],
    desc[(76-markerLen) & 0xFE], filename[80];
  /* v. 1.07: initial part moved to openconfig() */
  while ( !feof(config) )
  {
    while ( (fgets(configline, sizeof(configline), config) != NULL)
      && (configline[0] == ';') ) ;
    if feof(config) break;
    copyline(filename, 79);
    readconfig();
    copyline(header, maxHeader);
    readconfig();
    copyline(marker, markerLen);
    i = strlen(marker);
    while ( i<markerLen-1 ) /* pad with spaces if short */
      marker[i++] = ' '; /* is already 0-terminated at markerLen */
    readconfig();
    copyline(desc, 76-markerLen-2);
    i = strlen(desc); /* edited: v. 1.05 */
    desc[i] = '\n';
    desc[++i] = 0;
    readconfig();
    if ( sscanf(configline, "%u%u%i", &command, &extraTopics, &mask) < 3 )
      configError();

    StartTopic(header, marker, desc);
    CopyFile(filename, command);
    currentID += extraTopics;
  }
  fclose(config);
#undef maxHeader
#undef markerLen
} /* configure */

void main(int argc, char *argv[])
{
  int i;

  setcbrk(1);
  fprintf(stderr, "\nINT2GUID %s - (c) Kai Uwe Rommel/Bent Lynggaard - %s\n",
    VERSION, __DATE__);

  /* start of v. 1.10 update */
  for (i=1; i<argc; i++) {
    if (argv[i][0] == '-' || argv[i][0] == '/') {
      if (!stricmp(&argv[i][1],"nofilter")) filter = 0;
      else if (toupper(argv[i][1]) == 'F')
	strcpy(filterFileName, &argv[i][2]);
      else if (argv[i][1] == '?') usage();
      else goto paramError;
    } /* if (argv...) */
    else
  paramError:
      explain("Illegal parameter.");
  } /* for (i=0; ...) */

  if (filter && *filterFileName==0)
    explain("INT2GUID must have parameter \"-nofilter\" or \"-f<filename>\".");

  if (filter) {
    if ((filterFile = fopen(filterFileName, "r")) == NULL)
      explain("Couldn't open filter file.");
    fclose(filterFile);
    reservedID++; /* topic mainIndex (200) is used for the filter file topic */
  } /* if (filter) */
  /* end of v. 1.10 update */

  atexit(exitfunc);

  openconfig();

  Initialize(); /* uses topic 1 */

  fputs("Including:\n",stderr);
  StartTopic("Copyright etc.", "Copyright  ", "and references.\n");
  if (filter) /* v. 1.10 */
    mask = 2;
  else
    mask = 1;
  if ( CopyFile("int2guid.ref", true) ) /* topic 2 */
    errorexit(missingFile);
  mask = 0;

  if (filter) { /* v. 1.10 */
    topicStart = ftell(output);
    if (fputs("!TOPIC 200 Filter File\n", output) == EOF)
	/* here is a reference to 200, the value of mainIndex */
      diskFull(false);
    if (CopyFile("int2guid.re2", true))
      errorexit(missingFile);
    fputc('\1',output); /* toggle GUIDE/POPHELP attribute 1 */
    if (CopyFile(filterFileName, false))
      errorexit(missingFile);
    fputs("\1\n",output); /* toggle attribute 1 back to normal */
  } /* if (filter) */

  StartTopic("INTERRUP.LST", "HEADER     ", "Overview of the Interrupt List\n");
  fputs("(See also \4""4\5INTERRUP.1ST\5)\n", output); /* insert reference */
  CopyTopic(); /* topic 3 */

  StartTopic("INTERRUP.1ST", "Mail etc.  ", "How to get/update INTERRUP.LST\n");
  if ( CopyFile("interrup.1st", false) ) /* topic 4 */
    errorexit(missingFile);

  StartTopic("GUIDE Program", "GUIDE      ", "Popup Reference Engine.\n");
  if ( CopyFile("int2guid.gui", true) ) /* topic 5 */
    errorexit(missingFile);

  configure();

  indexed = 0;
  indexNo = mainIndex;

  while ( RecognizedTopic() )
    CopyTopic();

  Cleanup();

  exit(0);
}

/* End of INT2GUID.C */
